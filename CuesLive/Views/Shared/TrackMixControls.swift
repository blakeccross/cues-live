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

struct LogicStyleVolumeSlider: View {
    @Binding var value: Double
    let meterLevel: Float
    let onEditingEnded: () -> Void

    @State private var isDragging = false

    private let controlHeight: CGFloat = 26
    private let meterBarHeight: CGFloat = 2.5

    var body: some View {
        GeometryReader { geometry in
            let trackWidth = geometry.size.width
            let travel = max(trackWidth - controlHeight, 1)
            let thumbCenterX = controlHeight / 2 + CGFloat(value) * travel
            let thumbX = thumbCenterX - controlHeight / 2
            let meterWidth = trackWidth * MixerFaderScale.meterFillFraction(forPeak: meterLevel)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppColors.separator.opacity(0.45))
                    .frame(height: controlHeight)

                meterBars(width: meterWidth)
                    .padding(.leading, 8)
                    .frame(height: controlHeight, alignment: .center)
                    .clipShape(Capsule())

                Circle()
                    .fill(isDragging ? Color.white.opacity(0.60) : Color.white.opacity(0.45))
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                    }
                    .frame(width: controlHeight, height: controlHeight)
                    .offset(x: thumbX)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isDragging = true
                        setValue(fromCenterX: drag.location.x, trackWidth: trackWidth, travel: travel)
                    }
                    .onEnded { _ in
                        isDragging = false
                        onEditingEnded()
                    }
            )
        }
        .frame(height: controlHeight)
    }

    private func meterBars(width: CGFloat) -> some View {
        VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(mixerMeterGreen)
                .frame(width: max(0, width - 8), height: meterBarHeight)

            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(mixerMeterGreen)
                .frame(width: max(0, width - 8), height: meterBarHeight)
        }
    }

    private func setValue(fromCenterX x: CGFloat, trackWidth: CGFloat, travel: CGFloat) {
        let clampedCenter = min(max(x, controlHeight / 2), trackWidth - controlHeight / 2)
        let normalized = Double((clampedCenter - controlHeight / 2) / travel)
        value = min(1, max(0, normalized))
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

    /// Horizontal track meters: 0 dBFS fills the bar.
    static func meterFillFraction(forPeak peak: Float) -> CGFloat {
        guard peak > 0.000_001 else { return 0 }
        let db = min(maxAttenuationDB, max(0, -20 * log10(Double(peak))))
        return CGFloat(1 - (db / maxAttenuationDB))
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
