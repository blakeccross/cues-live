import SwiftUI

extension AppTypography {
    /// Fixed-size fonts for the timeline, rulers, lane headers, and mixer, where even `caption2` is
    /// too large. These do not scale with Dynamic Type, so use them only inside dense editor UI.
    enum Compact {
        /// Small labels and buttons: lane titles, clip names, "UP NEXT", ruler lane names.
        static let label = Font.system(size: 9, weight: .semibold)
        /// Tiny captions over a value, such as the tempo/key/meter labels under the editor's song title.
        static let microLabel = Font.system(size: 7, weight: .semibold)
        /// Secondary detail beside a `label`, such as a MIDI lane's routing.
        static let detail = Font.system(size: 9)
        /// Tempo and time signature values on the rulers. Pair with `.monospacedDigit()`.
        static let rulerValue = Font.system(size: 9, weight: .semibold, design: .rounded)
        /// Times on the seconds ruler.
        static let timecode = Font.system(size: 9, design: .monospaced)
        /// Assigned MIDI/key shortcut pill.
        static let badge = Font.system(size: 9, weight: .bold)
        /// Clip gain readout while dragging the gain line.
        static let clipGain = Font.system(size: 9.5)
        /// Section name on a marker row: the edit timeline's, and the live waveform's section ribbon.
        static let sectionName = Font.system(size: 11, weight: .semibold)
        /// Device name tag on a live MIDI lane.
        static let laneTag = Font.system(size: 8, weight: .semibold, design: .monospaced)
        /// Clip trim handle glyphs.
        static let trimHandle = Font.system(size: 10, weight: .heavy, design: .monospaced)

        /// Inline SF Symbols beside compact text, such as a menu chevron.
        static let glyph = Font.system(size: 8, weight: .semibold)
        /// Inline SF Symbols that mark state, such as the loop-section icon.
        static let glyphEmphasized = Font.system(size: 8, weight: .bold)
        /// Transition symbol between songs in the live setlist strip.
        static let transitionGlyph = Font.system(size: 10, weight: .bold)
        /// Large warning glyph centered over a waveform segment.
        static let overlayGlyph = Font.system(size: 22, weight: .semibold)

        /// Solo/mute button letters.
        static let mixButton = Font.system(size: 10, weight: .bold, design: .rounded)
        /// Volume and pan readouts. Pair with `.monospacedDigit()`.
        static let mixReadout = Font.system(size: 11, weight: .semibold, design: .rounded)
        /// Fader dB scale; unity gain uses the emphasized variant.
        static let faderScale = Font.system(size: 8, weight: .medium, design: .rounded)
        static let faderScaleEmphasized = Font.system(size: 8, weight: .bold, design: .rounded)
    }
}
