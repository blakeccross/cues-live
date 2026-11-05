import SwiftUI

private let mixerMeterGreen = Color(red: 0.22, green: 0.82, blue: 0.36)

struct TrackMixButton: View {
    let label: String
    let isActive: Bool
    let activeColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .frame(width: 22, height: 20)
                .foregroundStyle(isActive ? Color.black.opacity(0.85) : AppColors.textSecondary)
                .background(isActive ? activeColor : AppColors.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .appPressable()
    }
}

/// Parsing and display for the per-track volume (dB) and pan (-50…50) readouts.
enum TrackMixReadout {
    static let panRange: Double = 50

    static func volumeText(forGain gain: Double) -> String {
        guard gain > 0.000_001 else { return "-inf" }
        let db = MixerFaderScale.decibels(forLinearGain: gain)
        if db <= -MixerFaderScale.maxAttenuationDB { return "-inf" }
        let rounded = (db * 10).rounded() / 10
        if rounded == 0 { return "0" }
        let body = rounded.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(rounded))
            : String(format: "%.1f", rounded)
        return rounded > 0 ? "+\(body)" : body
    }

    /// Linear gain for typed text such as "-10", "+3.5" or "-inf". Boosts cap at +6 dB.
    static func gain(fromVolumeText text: String) -> Double? {
        let cleaned = text
            .replacingOccurrences(of: "dB", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "−", with: "-")
            .trimmingCharacters(in: .whitespaces)
        if cleaned.lowercased().hasSuffix("inf") { return 0 }
        guard let db = Double(cleaned) else { return nil }
        if db <= -MixerFaderScale.maxAttenuationDB { return 0 }
        return MixerFaderScale.linearGain(forDecibels: db)
    }

    static func panText(forPan pan: Double) -> String {
        let value = Int((pan * panRange).rounded())
        return value == 0 ? "C" : String(value)
    }

    /// Stored pan (-1…1) for typed text such as "-50", "25" or "C". Clamped to ±50.
    static func pan(fromPanText text: String) -> Double? {
        let cleaned = text
            .replacingOccurrences(of: "−", with: "-")
            .trimmingCharacters(in: .whitespaces)
        if cleaned.lowercased() == "c" { return 0 }
        guard let value = Double(cleaned) else { return nil }
        return min(panRange, max(-panRange, value)) / panRange
    }
}

/// Fader-style readout box. Drag horizontally to change the value, click to type one.
/// Return commits typed text, Escape cancels.
struct TrackValueField: View {
    let text: String
    /// Portion of the box (0…1 from the leading edge) filled to show the current value.
    let fill: ClosedRange<CGFloat>
    /// Horizontal drag distance in points from where the drag began; `isFinal` on release.
    let onDrag: (CGFloat, _ isFinal: Bool) -> Void
    /// Double-click: back to the default value.
    let onReset: () -> Void
    /// Returns `true` when the typed text was valid and applied.
    let onCommit: (String) -> Bool

    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    private let boxHeight: CGFloat = 22
    private let cornerRadius: CGFloat = 4

    var body: some View {
        ZStack {
            if isEditing {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .focused($isFocused)
                    .focusEffectDisabled()
                    .tint(.clear)
                    .onSubmit(commit)
                    .onExitCommand { isEditing = false }
                    .onChange(of: isFocused) { _, focused in
                        if !focused, isEditing { commit() }
                    }
            } else {
                Text(text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
        .foregroundStyle(AppColors.textPrimary)
        .frame(maxWidth: .infinity)
        .frame(height: boxHeight)
        .background {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .bottomLeading) {
                    Rectangle().fill(AppColors.surface)

                    Rectangle()
                        .fill(mixerMeterGreen.opacity(0.55))
                        .frame(width: width * (fill.upperBound - fill.lowerBound))
                        .offset(x: width * fill.lowerBound)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { drag in
                    guard !isEditing else { return }
                    onDrag(drag.translation.width, false)
                }
                .onEnded { drag in
                    guard !isEditing else { return }
                    onDrag(drag.translation.width, true)
                }
        )
        .gesture(
            TapGesture(count: 2)
                .onEnded {
                    guard !isEditing else { return }
                    onReset()
                }
                .exclusively(before: TapGesture().onEnded {
                    guard !isEditing else { return }
                    draft = text
                    isEditing = true
                    isFocused = true
                })
        )
    }

    private func commit() {
        guard isEditing else { return }
        isEditing = false
        _ = onCommit(draft.trimmingCharacters(in: .whitespaces))
    }
}

struct TrackVolumeField: View {
    @Binding var volume: Double
    /// Audible update while dragging; nothing is persisted until `onEditingEnded`.
    let onLiveChange: () -> Void
    let onEditingEnded: () -> Void

    @State private var dragStartDB: Double?

    private let dbPerPoint = 0.5

    var body: some View {
        TrackValueField(
            text: TrackMixReadout.volumeText(forGain: volume),
            fill: 0...CGFloat(1 - MixerFaderScale.normalizedPosition(forLinearGain: volume)),
            onDrag: { dx, isFinal in
                let start = dragStartDB ?? MixerFaderScale.decibels(forLinearGain: volume)
                dragStartDB = isFinal ? nil : start
                let db = min(MixerFaderScale.maxBoostDB, start + Double(dx) * dbPerPoint)
                volume = db <= -MixerFaderScale.maxAttenuationDB ? 0 : MixerFaderScale.linearGain(forDecibels: db)
                if isFinal { onEditingEnded() } else { onLiveChange() }
            },
            onReset: {
                volume = 1
                onLiveChange()
                onEditingEnded()
            },
            onCommit: { typed in
                guard let gain = TrackMixReadout.gain(fromVolumeText: typed) else { return false }
                volume = gain
                onEditingEnded()
                return true
            }
        )
        .help("Volume in dB (max +6). Drag to adjust, click to type a value, double-click to reset.")
    }
}

struct TrackPanField: View {
    @Binding var pan: Double
    let onLiveChange: () -> Void
    let onEditingEnded: () -> Void

    @State private var dragStartPan: Double?

    private let panPerPoint = 0.01

    var body: some View {
        let position = CGFloat((pan + 1) / 2)
        TrackValueField(
            text: TrackMixReadout.panText(forPan: pan),
            fill: min(position, 0.5)...max(position, 0.5),
            onDrag: { dx, isFinal in
                let start = dragStartPan ?? pan
                dragStartPan = isFinal ? nil : start
                pan = min(1, max(-1, start + Double(dx) * panPerPoint))
                if isFinal { onEditingEnded() } else { onLiveChange() }
            },
            onReset: {
                pan = 0
                onLiveChange()
                onEditingEnded()
            },
            onCommit: { typed in
                guard let value = TrackMixReadout.pan(fromPanText: typed) else { return false }
                pan = value
                onEditingEnded()
                return true
            }
        )
        .help("Pan from -50 (left) to 50 (right). Drag to adjust, click to type a value, double-click to reset.")
    }
}

enum MixerFaderScale {
    /// Top of the group fader. Unity (0 dB) sits one step below this.
    static let maxBoostDB: Double = 6
    static let maxAttenuationDB: Double = 60
    static let markerStepDB: Double = 6
    /// Matches the fader cap so scale marks line up with the thumb center.
    static let thumbHeight: CGFloat = 28

    static var spanDB: Double { maxBoostDB + maxAttenuationDB }

    /// +6, 0, −6, −12 … −60.
    static var markerDecibels: [Int] {
        Array(stride(from: Int(maxBoostDB), through: -Int(maxAttenuationDB), by: -Int(markerStepDB)))
    }

    static func decibels(forLinearGain gain: Double) -> Double {
        guard gain > 0.000_001 else { return -maxAttenuationDB }
        let db = 20 * log10(gain)
        return min(maxBoostDB, max(-maxAttenuationDB, db))
    }

    static func linearGain(forDecibels db: Double) -> Double {
        let clamped = min(maxBoostDB, max(-maxAttenuationDB, db))
        return pow(10, clamped / 20)
    }

    static func normalizedPosition(forDecibels db: Double) -> Double {
        let clamped = min(maxBoostDB, max(-maxAttenuationDB, db))
        return (maxBoostDB - clamped) / spanDB
    }

    static func normalizedPosition(forLinearGain gain: Double) -> Double {
        normalizedPosition(forDecibels: decibels(forLinearGain: gain))
    }

    static func linearGain(forNormalizedPosition position: Double) -> Double {
        let clamped = min(1, max(0, position))
        let db = maxBoostDB - clamped * spanDB
        return linearGain(forDecibels: db)
    }

    /// Group fader meters, on the same +6…−60 scale as the numbered marks.
    static func faderMeterFillFraction(forPeak peak: Float) -> CGFloat {
        guard peak > 0.000_001 else { return 0 }
        let db = min(maxBoostDB, max(-maxAttenuationDB, 20 * log10(Double(peak))))
        return CGFloat((db + maxAttenuationDB) / spanDB)
    }

    static func markerLabel(for db: Int) -> String {
        if db > 0 { return "+\(db)" }
        if db == 0 { return "0" }
        return "−\(abs(db))"
    }
}

struct MixerFaderColumn: View {
    @Binding var value: Double
    let groupID: UUID?
    let height: CGFloat
    /// Audible mix only — must not write SwiftData (avoids @Query rebuilds mid-drag).
    let onLiveVolumeChange: (Double) -> Void
    let onEditingEnded: () -> Void

    @State private var isDragging = false
    @State private var dragValue: Double = 0

    private let trackWidth: CGFloat = 4
    private let thumbWidth: CGFloat = 52
    private let thumbHeight: CGFloat = MixerFaderScale.thumbHeight
    private let meterWidth: CGFloat = 5
    private let labelWidth: CGFloat = 22
    private let labelGap: CGFloat = 2
    private let tickWidth: CGFloat = 8
    private let tickGapFromTrack: CGFloat = 4

    private var columnWidth: CGFloat {
        labelWidth + labelGap + thumbWidth
    }

    private var displayedValue: Double {
        isDragging ? dragValue : value
    }

    var body: some View {
        HStack(alignment: .top, spacing: 3) {
            faderTrack
            GroupPeakMeterBar(groupID: groupID, width: meterWidth, height: height)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: height)
    }

    private var faderTrack: some View {
        GeometryReader { geometry in
            let trackHeight = geometry.size.height
            let travel = max(trackHeight - thumbHeight, 1)
            let trackCenterX = labelWidth + labelGap + thumbWidth / 2
            let thumbCenterY = markY(
                forNormalized: MixerFaderScale.normalizedPosition(forLinearGain: displayedValue),
                in: trackHeight
            )
            let thumbY = thumbCenterY - thumbHeight / 2

            ZStack(alignment: .topLeading) {
                scaleLabels(in: trackHeight)
                scaleTicks(in: trackHeight, trackCenterX: trackCenterX)

                RoundedRectangle(cornerRadius: trackWidth / 2, style: .continuous)
                    .fill(AppColors.separator)
                    .frame(width: trackWidth, height: trackHeight)
                    .offset(x: trackCenterX - trackWidth / 2)

                faderThumb
                    .offset(x: labelWidth + labelGap, y: thumbY)
            }
            .frame(width: columnWidth, height: trackHeight, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if !isDragging {
                            dragValue = value
                            isDragging = true
                        }
                        setLiveValue(fromCenterY: drag.location.y, trackHeight: trackHeight, travel: travel)
                    }
                    .onEnded { _ in
                        if isDragging {
                            value = dragValue
                        }
                        isDragging = false
                        onEditingEnded()
                    }
            )
        }
        .frame(width: columnWidth)
        .transaction { transaction in
            if isDragging {
                transaction.disablesAnimations = true
            }
        }
    }

    private var faderThumb: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(AppColors.backgroundPrimary)
            .overlay {
                VStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        Rectangle()
                            .fill(AppColors.textTertiary.opacity(0.35))
                            .frame(height: 1)
                    }
                }
                .padding(.horizontal, 6)
            }
            .overlay {
                Rectangle()
                    .fill(Color.white.opacity(0.9))
                    .frame(height: 2)
                    .padding(.horizontal, 4)
            }
            .frame(width: thumbWidth, height: thumbHeight)
    }

    private func scaleLabels(in trackHeight: CGFloat) -> some View {
        let labelHeight: CGFloat = 10
        let marks = visibleMarkerLabels(in: trackHeight, labelHeight: labelHeight)

        return ZStack(alignment: .topLeading) {
            ForEach(marks, id: \.self) { db in
                let y = markY(
                    forNormalized: MixerFaderScale.normalizedPosition(forDecibels: Double(db)),
                    in: trackHeight
                )
                let isUnity = db == 0

                Text(MixerFaderScale.markerLabel(for: db))
                    .font(.system(size: 8, weight: isUnity ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isUnity ? AppColors.textSecondary : AppColors.textTertiary)
                    .frame(width: labelWidth, height: labelHeight, alignment: .trailing)
                    .offset(y: y - labelHeight / 2)
            }
        }
        .frame(width: labelWidth, height: trackHeight, alignment: .topLeading)
    }

    /// Every 6 dB gets a tick. Labels that would collide are dropped, except +6 and 0.
    private func visibleMarkerLabels(in trackHeight: CGFloat, labelHeight: CGFloat) -> [Int] {
        let minGap = labelHeight + 1
        var chosen: [(db: Int, y: CGFloat)] = []

        for db in MixerFaderScale.markerDecibels {
            let y = markY(
                forNormalized: MixerFaderScale.normalizedPosition(forDecibels: Double(db)),
                in: trackHeight
            )
            let pinned = db == Int(MixerFaderScale.maxBoostDB) || db == 0
            if let last = chosen.last, y - last.y < minGap {
                if pinned, last.db != Int(MixerFaderScale.maxBoostDB), last.db != 0 {
                    chosen.removeLast()
                    chosen.append((db, y))
                }
                continue
            }
            chosen.append((db, y))
        }

        return chosen.map(\.db)
    }

    private func scaleTicks(in trackHeight: CGFloat, trackCenterX: CGFloat) -> some View {
        let trackHalf = trackWidth / 2

        return ZStack(alignment: .topLeading) {
            ForEach(MixerFaderScale.markerDecibels, id: \.self) { db in
                let y = markY(
                    forNormalized: MixerFaderScale.normalizedPosition(forDecibels: Double(db)),
                    in: trackHeight
                )
                let isUnity = db == 0
                let width = isUnity ? tickWidth + 4 : tickWidth
                let tickColor = isUnity ? AppColors.textSecondary : AppColors.textTertiary.opacity(0.6)

                Rectangle()
                    .fill(tickColor)
                    .frame(width: width, height: 1)
                    .offset(
                        x: trackCenterX - trackHalf - tickGapFromTrack - width,
                        y: y - 0.5
                    )

                Rectangle()
                    .fill(tickColor)
                    .frame(width: width, height: 1)
                    .offset(
                        x: trackCenterX + trackHalf + tickGapFromTrack,
                        y: y - 0.5
                    )
            }
        }
        .frame(width: columnWidth, height: trackHeight, alignment: .topLeading)
    }

    private func markY(forNormalized normalized: Double, in trackHeight: CGFloat) -> CGFloat {
        thumbHeight / 2 + CGFloat(normalized) * max(trackHeight - thumbHeight, 1)
    }

    private func setLiveValue(fromCenterY y: CGFloat, trackHeight: CGFloat, travel: CGFloat) {
        let clampedCenter = min(max(y, thumbHeight / 2), trackHeight - thumbHeight / 2)
        let normalized = Double((clampedCenter - thumbHeight / 2) / travel)
        let newValue = MixerFaderScale.linearGain(forNormalizedPosition: normalized)
        dragValue = newValue
        onLiveVolumeChange(newValue)
    }
}

/// Reads peak meters in isolation so 30 Hz updates don't rebuild parent fader geometry.
private struct GroupPeakMeterBar: View {
    let groupID: UUID?
    let width: CGFloat
    let height: CGFloat

    @Bindable private var audioEngine = AudioEngineManager.shared

    var body: some View {
        let meterLevel = audioEngine.groupMeterLevel(for: groupID)

        GeometryReader { geometry in
            let inset = MixerFaderScale.thumbHeight / 2
            let travel = max(geometry.size.height - MixerFaderScale.thumbHeight, 1)
            let fill = travel * MixerFaderScale.faderMeterFillFraction(forPeak: meterLevel)

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(AppColors.separator)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(mixerMeterGreen.opacity(0.85))
                    .frame(height: fill)
            }
            .padding(.vertical, inset)
        }
        .frame(width: width, height: height)
    }
}
