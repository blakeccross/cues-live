import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Row model

/// Display data for one setlist row. Local (SwiftData) and remote (DTO) setlists both map into this,
/// so they share a single list implementation.
struct SetlistRowModel: Identifiable {
    struct Song {
        var title: String
        var durationText: String
        var keyText: String? = nil
        var bpmText: String? = nil
        /// Position among songs only (headers are not counted).
        var playbackIndex: Int
        var hasMissingMedia: Bool = false
        var hasSmartGuide: Bool = false
        /// Transition to the next song; nil for the last song.
        var transition: SetlistTransition? = nil
    }

    enum Kind {
        case header(title: String, timeText: String?)
        case song(Song)
    }

    let id: AnyHashable
    let kind: Kind
}

/// What a row can do. Optional closures are hidden from the menu, swipe actions and
/// context menu when nil, so the remote list can offer a smaller set than the local one.
struct SetlistRowActions {
    var play: (() -> Void)?
    var edit: (() -> Void)?
    var relink: (() -> Void)?
    var transitions: [SetlistTransition] = []
    var setTransition: ((SetlistTransition) -> Void)?
    var remove: () -> Void
}

// MARK: - List

/// A plain native list: tap to play, drag to reorder (Edit mode on iOS), and one shared set of
/// row actions surfaced through the context menu, the trailing "…" button and iOS swipe actions.
struct SetlistListView: View {
    let rows: [SetlistRowModel]
    let currentIndex: Int
    let isPlaying: Bool
    @Binding var isEditing: Bool
    let actions: (SetlistRowModel) -> SetlistRowActions
    let onMove: (IndexSet, Int) -> Void
    var onAddHeader: (() -> Void)? = nil

    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    var body: some View {
        List {
            ForEach(rows) { row in
                rowView(row)
            }
            .onMove(perform: onMove)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentShape(Rectangle())
        .contextMenu {
            if let onAddHeader {
                Button(action: onAddHeader) {
                    Label("Add Header", systemImage: "text.line.first.and.arrowtriangle.forward")
                }
            }
        }
        #if os(iOS)
        .environment(\.editMode, editModeBinding)
        // Avoid GeometryReader+List: after compact→regular rotation on device the list
        // can keep a blank content area. Recreate when size class changes.
        .id(verticalSizeClass)
        #endif
    }

    #if os(iOS)
    private var editModeBinding: Binding<EditMode> {
        Binding(
            get: { isEditing ? .active : .inactive },
            set: { isEditing = $0.isEditing }
        )
    }
    #endif

    @ViewBuilder
    private func rowView(_ row: SetlistRowModel) -> some View {
        let rowActions = actions(row)

        switch row.kind {
        case .header(let title, let timeText):
            SetlistHeaderRowView(
                title: title,
                timeText: timeText,
                showsMenu: !isEditing,
                menu: { SetlistRowMenuContent(model: row, actions: rowActions) }
            )
            .listRowSeparator(.hidden)
            .listRowBackground(AppColors.backgroundSecondary)
            .setlistSwipeActions(actions: rowActions)
            .contextMenu { SetlistRowMenuContent(model: row, actions: rowActions) }

        case .song(let song):
            let isCurrent = song.playbackIndex == currentIndex
            SetlistSongRowView(
                song: song,
                isCurrent: isCurrent,
                isFinished: song.playbackIndex < currentIndex,
                isPlaying: isPlaying,
                showsMenu: !isEditing,
                menu: { SetlistRowMenuContent(model: row, actions: rowActions) }
            )
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isEditing else { return }
                rowActions.play?()
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Play") { rowActions.play?() }
            .appLinkPointer()
            .mappableLiveControl(.goToSong(song.playbackIndex), cornerRadius: AppRadius.sm)
            .listRowBackground(isCurrent ? AppColors.accent.opacity(0.18) : Color.clear)
            .setlistSwipeActions(actions: rowActions)
            .contextMenu { SetlistRowMenuContent(model: row, actions: rowActions) }
        }
    }
}

private extension View {
    /// Swipe to play (leading) or remove / edit (trailing). iOS only; macOS uses the menu.
    @ViewBuilder
    func setlistSwipeActions(actions: SetlistRowActions) -> some View {
        #if os(iOS)
        self
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if let play = actions.play {
                    Button(action: play) {
                        Label("Play", systemImage: "play.fill")
                    }
                    .tint(AppColors.accent)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive, action: actions.remove) {
                    Label("Remove", systemImage: "trash")
                }
                if let edit = actions.edit {
                    Button(action: edit) {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
        #else
        self
        #endif
    }
}

// MARK: - Row menu

/// The single source of truth for row actions: used by the context menu and the "…" button.
private struct SetlistRowMenuContent: View {
    let model: SetlistRowModel
    let actions: SetlistRowActions

    var body: some View {
        if let play = actions.play {
            Button(action: play) {
                Label("Play", systemImage: "play.fill")
            }
        }

        if case .song(let song) = model.kind,
           let current = song.transition,
           let setTransition = actions.setTransition,
           !actions.transitions.isEmpty {
            Menu {
                ForEach(actions.transitions) { option in
                    Button {
                        setTransition(option)
                    } label: {
                        Label(option.label, systemImage: option == current ? "checkmark" : option.systemImage)
                    }
                }
            } label: {
                Label("Transition to Next", systemImage: current.systemImage)
            }
        }

        if let edit = actions.edit {
            Button(action: edit) {
                Label("Edit", systemImage: "pencil")
            }
        }

        if let relink = actions.relink {
            Button(action: relink) {
                Label("Relink Missing Files…", systemImage: "exclamationmark.triangle")
            }
        }

        Button(role: .destructive, action: actions.remove) {
            Label("Remove from Setlist", systemImage: "trash")
        }
    }
}

private struct SetlistRowMenuButton<MenuContent: View>: View {
    @ViewBuilder let menu: () -> MenuContent

    var body: some View {
        SwiftUI.Menu {
            menu()
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .fixedSize()
        .setlistMenuFittedSizing()
        .appLinkPointer()
        .accessibilityLabel("More actions")
    }
}

// MARK: - Rows

private struct SetlistHeaderRowView<MenuContent: View>: View {
    let title: String
    let timeText: String?
    let showsMenu: Bool
    @ViewBuilder let menu: () -> MenuContent

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Text(title)
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(AppColors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let timeText {
                Text(timeText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(AppColors.textTertiary)
                    .accessibilityLabel("Time \(timeText)")
            }

            if showsMenu {
                SetlistRowMenuButton(menu: menu)
            }
        }
        .frame(minHeight: 40)
    }
}

private struct SetlistSongRowView<MenuContent: View>: View {
    let song: SetlistRowModel.Song
    let isCurrent: Bool
    let isFinished: Bool
    let isPlaying: Bool
    let showsMenu: Bool
    @ViewBuilder let menu: () -> MenuContent

    private var detailText: String? {
        let parts = [song.keyText, song.bpmText].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            leadingIndicator
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.body.weight(isCurrent ? .semibold : .medium))
                    .foregroundStyle(isFinished ? AppColors.textTertiary : AppColors.textPrimary)
                    .lineLimit(2)

                if let detailText {
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if song.hasMissingMedia {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .accessibilityLabel("Missing audio files")
                    .help("Missing audio files — use Relink Missing Files in the menu")
            }

            if song.hasSmartGuide {
                SmartGuideBadge()
            }

            if let transition = song.transition {
                Image(systemName: transition.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(transition.badgeColor)
                    .accessibilityLabel("Transition to next: \(transition.label)")
                    .help("Transition to next: \(transition.label)")
            }

            Text(song.durationText)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(isCurrent ? AppColors.textSecondary : AppColors.textTertiary)
                .accessibilityLabel("Duration \(song.durationText)")

            if showsMenu {
                SetlistRowMenuButton(menu: menu)
            }
        }
        .frame(minHeight: AppSpacing.rowMinHeight)
        .opacity(isFinished ? 0.55 : 1)
    }

    @ViewBuilder
    private var leadingIndicator: some View {
        if isCurrent {
            Image(systemName: "speaker.wave.2.fill")
                .font(.subheadline)
                .foregroundStyle(AppColors.accent)
                .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                .accessibilityLabel("Now playing")
        } else {
            Text("\(song.playbackIndex + 1)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(AppColors.textTertiary)
                .accessibilityHidden(true)
        }
    }
}

/// Marks songs that have Smart Guide section call-outs turned on.
struct SmartGuideBadge: View {
    var body: some View {
        Image(systemName: "person.wave.2.fill")
            .font(.caption)
            .foregroundStyle(AppColors.accent)
            .accessibilityLabel("Smart Guide on")
            .help("Smart Guide on")
    }
}

// MARK: - Shared setlist chrome

struct LiveSetlistAddMenu: View {
    /// iOS only: shows an Edit/Done button that toggles drag-to-reorder. Pass nil when there is nothing to edit.
    var isEditing: Binding<Bool>? = nil
    var onAddHeader: () -> Void
    var onAddSong: () -> Void

    var body: some View {
        HStack {
            #if os(iOS)
            if let isEditing {
                Button(isEditing.wrappedValue ? "Done" : "Edit") {
                    withAnimation { isEditing.wrappedValue.toggle() }
                }
                .font(.body)
                .accessibilityLabel(isEditing.wrappedValue ? "Done reordering" : "Edit setlist order")
            }
            #endif

            Spacer(minLength: 0)

            Menu {
                Button(action: onAddHeader) {
                    Label("Header", systemImage: "text.line.first.and.arrowtriangle.forward")
                }

                Button(action: onAddSong) {
                    Label("Song", systemImage: "music.note")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
            .fixedSize()
            .setlistMenuFittedSizing()
            .appLinkPointer()
            .accessibilityLabel("Add to setlist")
            .help("Add to Setlist")
        }
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, AppSpacing.sm)
    }
}

private extension View {
    /// iOS 26+ Menu defaults to flexible (full-width) button sizing.
    @ViewBuilder
    func setlistMenuFittedSizing() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            buttonSizing(.fitted)
        } else {
            self
        }
    }
}

enum LiveSetlistDurationFormat {
    /// Longest minutes value the header duration fields accept.
    static let maximumMinutes = 999

    static func components(from duration: TimeInterval) -> (minutes: Int, seconds: Int) {
        let total = min(max(0, Int(duration.rounded())), maximumMinutes * 60 + 59)
        return (total / 60, total % 60)
    }

    static func seconds(minutes: Int, seconds: Int) -> TimeInterval {
        let mins = min(max(0, minutes), maximumMinutes)
        let secs = min(max(0, seconds), 59)
        return TimeInterval(mins * 60 + secs)
    }

    static var maximumTotalSeconds: Int { maximumMinutes * 60 + 59 }

    /// Fixed `HH:MM:SS` duration, the way a Final Cut timecode field draws a length.
    static func finalCutDisplay(for duration: TimeInterval) -> String {
        let total = min(max(0, Int(duration.rounded())), maximumTotalSeconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    /// Right-aligned digit entry. `536` is 5 minutes 36 seconds. Extra digits fall off the left.
    static func seconds(fromFinalCutDigits digits: String) -> Int {
        let filtered = digits.filter(\.isNumber)
        let trimmed = String(filtered.suffix(6))
        let padded = String(repeating: "0", count: max(0, 6 - trimmed.count)) + trimmed
        let chars = Array(padded)
        func pair(at index: Int) -> Int {
            Int(String(chars[index]) + String(chars[index + 1])) ?? 0
        }
        let total = pair(at: 0) * 3600 + pair(at: 2) * 60 + pair(at: 4)
        return min(max(0, total), maximumTotalSeconds)
    }

    /// In-progress entry, including pairs above 59, until the field commits and carries them.
    static func finalCutEntryDisplay(digits: String) -> String {
        let trimmed = String(digits.filter(\.isNumber).suffix(6))
        let padded = String(repeating: "0", count: max(0, 6 - trimmed.count)) + trimmed
        let chars = Array(padded)
        return "\(chars[0])\(chars[1]):\(chars[2])\(chars[3]):\(chars[4])\(chars[5])"
    }

    /// Per-song clock like `5:36`, or `1:05:36` when an hour or longer.
    static func clock(for duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// Minutes and seconds for a setlist header. The list still shows the compact duration.
struct SetlistHeaderDurationField: View {
    @Binding var seconds: TimeInterval

    var body: some View {
        #if os(iOS)
        SetlistHeaderDurationWheel(seconds: $seconds)
            .frame(height: 216)
            .accessibilityElement(children: .contain)
        #else
        MacHeaderDurationControl(seconds: $seconds)
            .frame(width: MacHeaderDurationControl.preferredWidth, height: MacHeaderDurationControl.preferredHeight)
        #endif
    }
}

#if os(macOS)
/// Final Cut–style duration: one `HH:MM:SS` field. Click a unit to type it, or drag that unit.
private struct MacHeaderDurationControl: NSViewRepresentable {
    @Binding var seconds: TimeInterval

    static let font = NSFont.monospacedDigitSystemFont(ofSize: 16, weight: .medium)
    static let preferredWidth: CGFloat = ceil(
        ("00:00:00" as NSString).size(withAttributes: [.font: font]).width
    ) + 28
    static let bezelHeight: CGFloat = 28
    static let unitLabelFont = NSFont.systemFont(ofSize: 10, weight: .medium)
    static let unitLabelGap: CGFloat = 1
    static let unitLabelHeight: CGFloat = ceil(unitLabelFont.boundingRectForFont.height)
    static let preferredHeight: CGFloat = bezelHeight + unitLabelGap + unitLabelHeight

    func makeCoordinator() -> Coordinator {
        Coordinator(seconds: $seconds)
    }

    func makeNSView(context: Context) -> FinalCutDurationField {
        let field = FinalCutDurationField()
        field.onChange = { context.coordinator.commit($0) }
        field.setTotalSeconds(clamped($seconds.wrappedValue))
        return field
    }

    func updateNSView(_ field: FinalCutDurationField, context: Context) {
        context.coordinator.seconds = $seconds
        field.onChange = { context.coordinator.commit($0) }
        guard !field.isAdjusting else { return }
        field.setTotalSeconds(clamped(seconds))
    }

    func sizeThatFits(_: ProposedViewSize, nsView: FinalCutDurationField, context: Context) -> CGSize? {
        CGSize(width: Self.preferredWidth, height: Self.preferredHeight)
    }

    private func clamped(_ duration: TimeInterval) -> Int {
        min(max(0, Int(duration.rounded())), LiveSetlistDurationFormat.maximumTotalSeconds)
    }

    final class Coordinator: NSObject {
        var seconds: Binding<TimeInterval>

        init(seconds: Binding<TimeInterval>) {
            self.seconds = seconds
        }

        func commit(_ totalSeconds: Int) {
            let next = TimeInterval(totalSeconds)
            guard seconds.wrappedValue != next else { return }
            seconds.wrappedValue = next
        }
    }
}

private final class FinalCutDurationField: NSView {
    var onChange: ((Int) -> Void)?

    private enum Component: Int, CaseIterable {
        case hours, minutes, seconds

        var digitStart: Int {
            switch self {
            case .hours: 0
            case .minutes: 3
            case .seconds: 6
            }
        }
    }

    private var totalSeconds = 0
    private var valueAtFocus = 0
    private var selected: Component?
    /// Digits typed into the selected unit. One digit waits for a second; two digits finish the unit.
    private var segmentEntry: String?
    private var entryDigits: String?
    private var dragComponent: Component?
    private var dragAccum: CGFloat = 0
    private var scrollAccum: CGFloat = 0

    var isAdjusting: Bool { entryDigits != nil || segmentEntry != nil || dragComponent != nil }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func setTotalSeconds(_ seconds: Int) {
        let next = min(max(0, seconds), LiveSetlistDurationFormat.maximumTotalSeconds)
        guard next != totalSeconds else { return }
        totalSeconds = next
        needsDisplay = true
    }

    override func resetCursorRects() {
        addCursorRect(bezelRect, cursor: .resizeUpDown)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bezelRect.insetBy(dx: 1, dy: 1)
        let background = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSColor.controlBackgroundColor.setFill()
        background.fill()
        let focused = window?.firstResponder === self
        let border = focused ? NSColor.controlAccentColor : NSColor.separatorColor
        border.setStroke()
        background.lineWidth = focused ? 1.5 : 1
        background.stroke()

        let display = currentDisplay
        let metrics = textMetrics(for: display)
        if focused {
            NSColor.selectedTextBackgroundColor.setFill()
            highlightPath(metrics: metrics, display: display).fill()
        }
        (display as NSString).draw(in: metrics.textRect, withAttributes: [
            .font: MacHeaderDurationControl.font,
            .foregroundColor: NSColor.labelColor
        ])
        drawUnitLabels(metrics: metrics)
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bezelRect.insetBy(dx: 2, dy: 2), xRadius: 6, yRadius: 6).fill()
    }

    override var focusRingMaskBounds: NSRect { bezelRect }

    private var bezelRect: NSRect {
        NSRect(x: 0, y: bounds.height - MacHeaderDurationControl.bezelHeight, width: bounds.width, height: MacHeaderDurationControl.bezelHeight)
    }

    private func drawUnitLabels(metrics: TextMetrics) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: MacHeaderDurationControl.unitLabelFont,
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let titles = ["hr", "min", "sec"]
        for (component, title) in zip(Component.allCases, titles) {
            let start = metrics.advances[component.digitStart]
            let end = metrics.advances[component.digitStart + 2]
            let size = (title as NSString).size(withAttributes: attributes)
            let center = metrics.textRect.minX + (start + end) / 2
            let rect = NSRect(
                x: center - size.width / 2,
                y: bezelRect.minY - MacHeaderDurationControl.unitLabelGap - size.height,
                width: size.width,
                height: size.height
            )
            (title as NSString).draw(in: rect, withAttributes: attributes)
        }
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            valueAtFocus = totalSeconds
            needsDisplay = true
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            commitEntry()
            selected = nil
            needsDisplay = true
        }
        return resigned
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        commitEntry()
        let component = component(at: convert(event.locationInWindow, from: nil)) ?? .seconds
        selected = component
        dragComponent = component
        dragAccum = 0
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragComponent else { return }
        dragAccum += event.deltaY
        applyAccumulatedSteps(&dragAccum, threshold: 4, component: dragComponent)
    }

    override func mouseUp(with event: NSEvent) {
        dragComponent = nil
    }

    override func scrollWheel(with event: NSEvent) {
        window?.makeFirstResponder(self)
        commitEntry()
        let component = component(at: convert(event.locationInWindow, from: nil)) ?? selected ?? .seconds
        selected = component
        let precise = event.hasPreciseScrollingDeltas
        scrollAccum += event.scrollingDeltaY
        applyAccumulatedSteps(&scrollAccum, threshold: precise ? 10 : 0.01, component: component)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126:
            nudgeSelected(by: 1)
        case 125:
            nudgeSelected(by: -1)
        case 123:
            moveSelection(by: -1)
        case 124:
            moveSelection(by: 1)
        case 36, 76:
            commitEntry()
        case 53:
            cancelEntry()
        case 51, 117:
            backspace()
        default:
            guard let character = event.charactersIgnoringModifiers?.first else {
                super.keyDown(with: event)
                return
            }
            if character.isNumber {
                appendDigit(character)
            } else if character == "." {
                appendDigitPair()
            } else {
                super.keyDown(with: event)
            }
        }
    }

    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityRole() -> NSAccessibility.Role? { .textField }

    override func accessibilityLabel() -> String? { "Duration" }

    override func accessibilityValue() -> Any? {
        LiveSetlistDurationFormat.finalCutDisplay(for: TimeInterval(totalSeconds))
    }

    override func accessibilityPerformIncrement() -> Bool {
        nudgeSelected(by: 1)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        nudgeSelected(by: -1)
        return true
    }

    private var currentDisplay: String {
        if let entryDigits {
            return LiveSetlistDurationFormat.finalCutEntryDisplay(digits: entryDigits)
        }
        return LiveSetlistDurationFormat.finalCutDisplay(for: TimeInterval(totalSeconds))
    }

    private func appendDigit(_ character: Character) {
        entryDigits = nil
        let component = selected ?? .seconds
        selected = component
        var digits = segmentEntry ?? ""
        if digits.count >= 2 {
            digits = ""
        }
        digits.append(character)
        let typed = Int(digits) ?? 0
        setComponent(component, to: typed)
        let finished = digits.count >= 2 || typed > leadingDigitLimit(for: component)
        if finished {
            segmentEntry = nil
            advance(from: component)
        } else {
            segmentEntry = digits
        }
    }

    /// A first digit above this cannot be the tens place of a valid pair, so the unit is complete.
    private func leadingDigitLimit(for component: Component) -> Int {
        switch component {
        case .hours: 1
        case .minutes, .seconds: 5
        }
    }

    private func appendDigitPair() {
        entryDigits = nil
        segmentEntry = nil
        advance(from: selected ?? .hours)
    }

    private func backspace() {
        let component = selected ?? .seconds
        if var digits = segmentEntry, !digits.isEmpty {
            digits.removeLast()
            segmentEntry = digits.isEmpty ? nil : digits
            setComponent(component, to: Int(digits) ?? 0)
            return
        }
        setComponent(component, to: 0)
    }

    private func setComponent(_ component: Component, to value: Int) {
        var hours = totalSeconds / 3600
        var minutes = (totalSeconds % 3600) / 60
        var seconds = totalSeconds % 60
        switch component {
        case .hours:
            hours = max(0, value)
        case .minutes:
            minutes = min(max(0, value), 59)
        case .seconds:
            seconds = min(max(0, value), 59)
        }
        publish(hours * 3600 + minutes * 60 + seconds)
    }

    private func advance(from component: Component) {
        let next = min(component.rawValue + 1, Component.seconds.rawValue)
        selected = Component(rawValue: next)
        needsDisplay = true
    }

    private func commitEntry() {
        entryDigits = nil
        segmentEntry = nil
        needsDisplay = true
    }

    private func cancelEntry() {
        entryDigits = nil
        segmentEntry = nil
        publish(valueAtFocus)
    }

    private func nudgeSelected(by delta: Int) {
        commitEntry()
        let component = selected ?? .seconds
        selected = component
        nudge(component, by: delta)
    }

    private func moveSelection(by delta: Int) {
        commitEntry()
        let current = selected ?? .seconds
        let next = min(max(0, current.rawValue + delta), Component.allCases.count - 1)
        selected = Component(rawValue: next)
        needsDisplay = true
    }

    private func nudge(_ component: Component, by delta: Int) {
        var hours = totalSeconds / 3600
        var minutes = (totalSeconds % 3600) / 60
        var seconds = totalSeconds % 60
        switch component {
        case .hours: hours += delta
        case .minutes: minutes += delta
        case .seconds: seconds += delta
        }
        publish(hours * 3600 + minutes * 60 + seconds)
    }

    private func applyAccumulatedSteps(_ accum: inout CGFloat, threshold: CGFloat, component: Component) {
        guard abs(accum) >= threshold else {
            needsDisplay = true
            return
        }
        let delta = accum > 0 ? 1 : -1
        accum = 0
        nudge(component, by: delta)
    }

    private func publish(_ rawSeconds: Int) {
        let next = min(max(0, rawSeconds), LiveSetlistDurationFormat.maximumTotalSeconds)
        totalSeconds = next
        onChange?(next)
        needsDisplay = true
    }

    private struct TextMetrics {
        var textRect: NSRect
        var advances: [CGFloat]
    }

    private func textMetrics(for display: String) -> TextMetrics {
        let attributes: [NSAttributedString.Key: Any] = [.font: MacHeaderDurationControl.font]
        var advances: [CGFloat] = [0]
        var width: CGFloat = 0
        for character in display {
            width += (String(character) as NSString).size(withAttributes: attributes).width
            advances.append(width)
        }
        let height = ("0" as NSString).size(withAttributes: attributes).height
        let rect = NSRect(
            x: (bezelRect.width - width) / 2,
            y: bezelRect.minY + (bezelRect.height - height) / 2,
            width: width,
            height: height
        )
        return TextMetrics(textRect: rect, advances: advances)
    }

    private func highlightPath(metrics: TextMetrics, display: String) -> NSBezierPath {
        let range: Range<Int>
        if entryDigits != nil {
            range = 0..<display.count
        } else {
            let component = selected ?? .seconds
            range = component.digitStart..<(component.digitStart + 2)
        }
        let start = metrics.advances[range.lowerBound]
        let end = metrics.advances[range.upperBound]
        let rect = NSRect(
            x: metrics.textRect.minX + start - 1,
            y: metrics.textRect.minY - 1,
            width: end - start + 2,
            height: metrics.textRect.height + 2
        )
        return NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
    }

    private func component(at point: NSPoint) -> Component? {
        let metrics = textMetrics(for: currentDisplay)
        let localX = point.x - metrics.textRect.minX
        guard localX >= 0 else { return .hours }
        var index = currentDisplay.count - 1
        for slot in metrics.advances.indices.dropLast() where localX < metrics.advances[slot + 1] {
            index = slot
            break
        }
        switch index {
        case 0...2: return .hours
        case 3...5: return .minutes
        default: return .seconds
        }
    }
}
#endif


#if os(iOS)
/// Minutes and seconds wheels. UIDatePicker's countdown timer is hours and minutes only,
/// and it discards leftover seconds, so this uses the same wheel control with those two columns.
private struct SetlistHeaderDurationWheel: UIViewRepresentable {
    @Binding var seconds: TimeInterval

    func makeCoordinator() -> Coordinator {
        Coordinator(seconds: $seconds)
    }

    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.dataSource = context.coordinator
        picker.delegate = context.coordinator
        context.coordinator.apply(seconds, to: picker)
        return picker
    }

    func updateUIView(_ picker: UIPickerView, context: Context) {
        context.coordinator.seconds = $seconds
        context.coordinator.apply(seconds, to: picker)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIPickerView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 320, height: 216)
    }

    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
        var seconds: Binding<TimeInterval>
        private var isApplying = false
        private var appliedSeconds: Int?

        init(seconds: Binding<TimeInterval>) {
            self.seconds = seconds
        }

        func numberOfComponents(in pickerView: UIPickerView) -> Int { 2 }

        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            component == 0 ? LiveSetlistDurationFormat.maximumMinutes + 1 : 60
        }

        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
            let available = pickerView.bounds.width
            guard available > 0 else { return 140 }
            return available / 2
        }

        func pickerView(
            _ pickerView: UIPickerView,
            viewForRow row: Int,
            forComponent component: Int,
            reusing view: UIView?
        ) -> UIView {
            let label = (view as? UILabel) ?? UILabel()
            label.textAlignment = .center
            label.font = .monospacedDigitSystemFont(ofSize: 22, weight: .regular)
            label.textColor = .label
            if component == 0 {
                label.text = "\(row) min"
            } else {
                label.text = String(format: "%02d sec", row)
            }
            return label
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            guard !isApplying else { return }
            let minutes = pickerView.selectedRow(inComponent: 0)
            let secs = pickerView.selectedRow(inComponent: 1)
            guard minutes >= 0, secs >= 0 else { return }
            let value = minutes * 60 + secs
            appliedSeconds = value
            seconds.wrappedValue = TimeInterval(value)
        }

        func pickerView(_ pickerView: UIPickerView, accessibilityLabelForComponent component: Int) -> String? {
            component == 0 ? "Minutes" : "Seconds"
        }

        func apply(_ seconds: TimeInterval, to picker: UIPickerView) {
            let parts = LiveSetlistDurationFormat.components(from: seconds)
            let total = parts.minutes * 60 + parts.seconds
            guard appliedSeconds != total else { return }
            let rows = [parts.minutes, parts.seconds]
            isApplying = true
            for (component, row) in rows.enumerated() where picker.selectedRow(inComponent: component) != row {
                picker.selectRow(row, inComponent: component, animated: false)
            }
            appliedSeconds = total
            isApplying = false
        }
    }
}
#endif

/// Title and time editor shared by local and remote header creation.
struct SetlistHeaderEditorSheet: View {
    let navigationTitle: String
    let confirmTitle: String
    @Binding var headerTitle: String
    @Binding var timeSeconds: TimeInterval
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private var canConfirm: Bool {
        !headerTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            editorContent
            .navigationTitle(navigationTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmTitle, action: onConfirm)
                        .disabled(!canConfirm)
                }
            }
        }
    }

    private var editorContent: some View {
        headerForm
            #if os(macOS)
            .formStyle(.grouped)
            .frame(minWidth: 420, idealWidth: 460)
            #endif
    }

    private var headerForm: some View {
        Form {
            Section {
                TextField("Title", text: $headerTitle)
                #if os(macOS)
                LabeledContent {
                    SetlistHeaderDurationField(seconds: $timeSeconds)
                        .alignmentGuide(VerticalAlignment.center) { _ in
                            MacHeaderDurationControl.bezelHeight / 2
                        }
                } label: {
                    Text("Duration")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, -10)
                #else
                SetlistHeaderDurationField(seconds: $timeSeconds)
                #endif
            } footer: {
                Text(durationFooter)
            }
        }
    }

    private var durationFooter: String {
        #if os(macOS)
        "Shown beside the header, like a song length."
        #else
        "Headers divide the setlist into sections. The duration is shown in the same column as song durations."
        #endif
    }
}

/// Shared Finder-drop parsing for song-folder imports.
enum SongFolderDrop {
    /// Resolves dropped file providers to the URLs of the directories among them.
    static func folderURLs(from providers: [NSItemProvider]) async -> [URL] {
        var folderURLs: [URL] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            guard let url = await loadFileURL(from: provider) else { continue }
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                folderURLs.append(url)
            }
        }
        return folderURLs
    }

    private static func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                switch item {
                case let url as URL:
                    continuation.resume(returning: url)
                case let data as Data:
                    continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil))
                default:
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

/// Accepts a Finder folder drag on the song library.
struct LiveSetlistSongFolderDropDelegate: DropDelegate {
    let onHover: () -> Void
    let onExit: () -> Void
    let onPerform: ([NSItemProvider]) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }

    func dropEntered(info: DropInfo) {
        onHover()
    }

    func dropExited(info: DropInfo) {
        onExit()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        onPerform(info.itemProviders(for: [.fileURL]))
    }
}
