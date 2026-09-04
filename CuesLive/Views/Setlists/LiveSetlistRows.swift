import SwiftUI
import UniformTypeIdentifiers

struct LiveSetlistHeaderRow: View {
    let title: String
    var timeText: String = "0:00"

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Text(timeText)
                .font(.subheadline.monospaced())
                .foregroundStyle(AppColors.textTertiary)
                .frame(width: 52, alignment: .trailing)
                .accessibilityLabel("Time \(timeText)")

            Text(title)
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(AppColors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .frame(minHeight: 40, alignment: .leading)
    }
}

struct LiveSetlistSongRow: View {
    let title: String
    let durationText: String
    let index: Int
    let currentIndex: Int
    var keyText: String? = nil
    var bpmText: String? = nil
    var hasMissingMedia: Bool = false
    var transition: SetlistTransition? = nil
    var onOverlapBadgeTap: (() -> Void)? = nil

    private var isFinished: Bool {
        index < currentIndex
    }

    private var isCurrent: Bool {
        index == currentIndex
    }

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Text(durationText)
                .font(.subheadline.monospaced().weight(isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? AppColors.textSecondary : AppColors.textTertiary)
                .frame(width: 52, alignment: .trailing)
                .accessibilityLabel("Duration \(durationText)")

            HStack(spacing: AppSpacing.xs) {
                Text(title)
                    .font(isCurrent ? .headline.weight(.semibold) : .body.weight(.medium))
                    .foregroundStyle(isFinished ? AppColors.textTertiary : AppColors.textPrimary)
                    .lineLimit(2)
                    .layoutPriority(1)

                if let keyText {
                    AppBadge(title: keyText, style: .neutral)
                        .accessibilityLabel("Key \(keyText)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if hasMissingMedia {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .accessibilityLabel("Missing audio files")
                    .help("Missing audio files — use Relink Missing Files in the context menu")
            }

            Text(bpmText ?? "")
                .font(.caption.monospaced().weight(.medium))
                .foregroundStyle(isCurrent ? AppColors.textSecondary : AppColors.textTertiary)
                .frame(width: 64, alignment: .trailing)
                .accessibilityLabel(bpmText.map { "\($0)" } ?? "")
                .accessibilityHidden(bpmText == nil)

            if let transition {
                SetlistTransitionBadge(
                    transition: transition,
                    size: 24,
                    onTap: onOverlapBadgeTap
                )
            }
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.sm)
        .frame(maxWidth: .infinity, minHeight: isCurrent ? 64 : 56, alignment: .leading)
        .contentShape(Rectangle())
        .opacity(isFinished ? 0.55 : 1)
    }
}

extension LiveSetlistSongRow {
    init(
        song: Song,
        duration: TimeInterval,
        index: Int,
        currentIndex: Int,
        hasMissingMedia: Bool = false,
        transition: SetlistTransition? = nil,
        onOverlapBadgeTap: (() -> Void)? = nil
    ) {
        let bpmText: String? = {
            guard let bpm = song.bpm else { return nil }
            return String(format: "%.0f BPM", bpm.rounded())
        }()
        self.init(
            title: song.name,
            durationText: LiveSetlistDurationFormat.clock(for: duration),
            index: index,
            currentIndex: currentIndex,
            keyText: song.displayedKeyText,
            bpmText: bpmText,
            hasMissingMedia: hasMissingMedia,
            transition: transition,
            onOverlapBadgeTap: onOverlapBadgeTap
        )
    }
}

// MARK: - Shared setlist chrome

struct LiveSetlistAddMenu: View {
    var onAddHeader: () -> Void
    var onAddSong: () -> Void

    var body: some View {
        HStack {
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
            .liveSetlistAddMenuFittedSizing()
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
    func liveSetlistAddMenuFittedSizing() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            buttonSizing(.fitted)
        } else {
            self
        }
    }
}

enum LiveSetlistDurationFormat {
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

    /// Parses `m:ss`, `mm:ss`, or `h:mm:ss`. Empty / whitespace → `0`.
    static func seconds(fromClock text: String) -> TimeInterval? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }

        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return nil
        }

        let values = parts.compactMap { Int($0) }
        guard values.count == parts.count else { return nil }

        switch values.count {
        case 1:
            return TimeInterval(max(0, values[0]))
        case 2:
            let minutes = values[0]
            let seconds = values[1]
            guard (0..<60).contains(seconds) else { return nil }
            return TimeInterval(max(0, minutes) * 60 + seconds)
        case 3:
            let hours = values[0]
            let minutes = values[1]
            let seconds = values[2]
            guard (0..<60).contains(minutes), (0..<60).contains(seconds) else { return nil }
            return TimeInterval(max(0, hours) * 3600 + minutes * 60 + seconds)
        default:
            return nil
        }
    }
}

private struct LiveSetlistReorderHandle: View {
    let accessibilityNoun: String
    var isCurrent: Bool = false
    let onDragBegan: () -> NSItemProvider

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.body.weight(.semibold))
            .foregroundStyle(isCurrent ? AppColors.textSecondary : AppColors.textTertiary)
            .frame(width: 36)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .accessibilityLabel("Reorder \(accessibilityNoun)")
            .help("Drag to reorder")
            .onDrag(onDragBegan) {
                // The list reorders in place, so the floating drag image would only be noise.
                Color.clear.frame(width: 1, height: 1)
            }
    }
}

/// Keeps a stable HStack row root on both platforms (needed so iOS List reorder
/// isn't fighting a Button as the row's root). Trailing grip is macOS-only;
/// iOS uses the native edit-mode control in the same trailing slot.
private struct LiveSetlistTrailingReorderHandleModifier: ViewModifier {
    let accessibilityNoun: String
    var isCurrent: Bool = false
    let onDragBegan: () -> NSItemProvider

    func body(content: Content) -> some View {
        HStack(spacing: 0) {
            content
            #if os(macOS)
            LiveSetlistReorderHandle(
                accessibilityNoun: accessibilityNoun,
                isCurrent: isCurrent,
                onDragBegan: onDragBegan
            )
            #endif
        }
    }
}

/// Shared list styling used by local and remote live setlist panes.
struct LiveSetlistListChromeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 1)
            #if os(iOS)
            .listSectionSpacing(0)
            .contentMargins(.vertical, 0, for: .scrollContent)
            // Native trailing reorder control (custom onDrag/onDrop is unreliable in iOS List).
            .environment(\.editMode, .constant(.active))
            #endif
    }
}

private struct LiveSetlistSongRowChromeModifier: ViewModifier {
    let isDragging: Bool
    let isCurrent: Bool
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .opacity(isDragging ? 0.3 : 1)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowSeparator(.hidden)
            .listRowBackground(rowBackground)
            .onHover { isHovered = $0 }
    }

    private var rowBackground: Color {
        if isCurrent {
            return AppColors.accent
        }
        if isHovered {
            return AppColors.surface
        }
        return Color.clear
    }
}

extension View {
    func liveSetlistListChrome() -> some View {
        modifier(LiveSetlistListChromeModifier())
    }

    func liveSetlistTrailingReorderHandle(
        accessibilityNoun: String,
        isCurrent: Bool = false,
        onDragBegan: @escaping () -> NSItemProvider
    ) -> some View {
        modifier(
            LiveSetlistTrailingReorderHandleModifier(
                accessibilityNoun: accessibilityNoun,
                isCurrent: isCurrent,
                onDragBegan: onDragBegan
            )
        )
    }

    func liveSetlistHeaderRowChrome(isDragging: Bool) -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(isDragging ? 0.3 : 1)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowSeparator(.hidden)
            .listRowBackground(AppColors.backgroundSecondary)
    }

    func liveSetlistSongRowChrome(isDragging: Bool, isCurrent: Bool) -> some View {
        modifier(
            LiveSetlistSongRowChromeModifier(
                isDragging: isDragging,
                isCurrent: isCurrent
            )
        )
    }
}

/// Reorders live as the drag passes over a row. A nil `targetID` marks the list background,
/// which only needs to commit whatever order the drag left behind.
struct LiveSetlistEntryDropDelegate<ID: Hashable>: DropDelegate {
    let targetID: ID?
    let draggedID: ID?
    let onMove: (ID, ID) -> Void
    let onCommit: () -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggedID != nil
    }

    func dropEntered(info: DropInfo) {
        guard let draggedID, let targetID, draggedID != targetID else { return }
        onMove(draggedID, targetID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        onCommit()
        return true
    }
}
