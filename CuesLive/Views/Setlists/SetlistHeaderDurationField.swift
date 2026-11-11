import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Minutes and seconds for a setlist header. The list still shows the compact duration.
struct SetlistHeaderDurationField: View {
    @Binding var seconds: TimeInterval

    #if os(macOS)
    /// Height of the text bezel, so callers can center labels on the field rather than its unit captions.
    static var macBezelHeight: CGFloat { MacHeaderDurationControl.bezelHeight }
    #endif

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
