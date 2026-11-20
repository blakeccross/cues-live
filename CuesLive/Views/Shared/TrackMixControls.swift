import SwiftUI

struct TrackMixButton: View {
    /// `compact` for track headers; `large` for group mixer strips.
    enum Size {
        case compact
        case large

        var width: CGFloat { self == .compact ? 22 : 34 }
        var height: CGFloat { self == .compact ? 20 : 26 }
        var font: Font { self == .compact ? AppTypography.Compact.mixButton : AppTypography.Compact.mixButtonLarge }
        var inactiveFill: Color { self == .compact ? AppColors.surface : AppColors.Mixer.groupButton }
    }

    let label: String
    let isActive: Bool
    let activeColor: Color
    var size: Size = .compact
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(size.font)
                .frame(width: size.width, height: size.height)
                .foregroundStyle(isActive ? AppColors.Mixer.buttonActiveLabel : AppColors.textSecondary)
                .background(
                    isActive ? activeColor : size.inactiveFill,
                    in: RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous)
                )
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

    /// Peak-hold readout to one decimal, such as "-12.3" or "+0.4". Unlike the fader it is not
    /// capped at +6 dB, so overs show their real level.
    static func peakText(forPeak peak: Float) -> String {
        guard peak > 0.000_001 else { return "-inf" }
        let db = 20 * log10(Double(peak))
        if db <= -MixerFaderScale.maxAttenuationDB { return "-inf" }
        let rounded = (db * 10).rounded() / 10
        let body = String(format: "%.1f", abs(rounded))
        if rounded == 0 { return body }
        return rounded > 0 ? "+\(body)" : "-\(body)"
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
                    #if os(macOS)
                    .onExitCommand { isEditing = false }
                    #endif
                    .onChange(of: isFocused) { _, focused in
                        if !focused, isEditing { commit() }
                    }
            } else {
                Text(text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .font(AppTypography.Compact.mixReadout.monospacedDigit())
        .foregroundStyle(AppColors.textPrimary)
        .frame(maxWidth: .infinity)
        .frame(height: boxHeight)
        .background {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .bottomLeading) {
                    Rectangle().fill(AppColors.surface)

                    Rectangle()
                        .fill(AppColors.Mixer.readoutLevel)
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
