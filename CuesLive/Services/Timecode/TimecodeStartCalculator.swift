import Foundation

struct TimecodeValue: Equatable, Sendable {
    var hours: Int
    var minutes: Int
    var seconds: Int
    var frames: Int

    static let zero = TimecodeValue(hours: 0, minutes: 0, seconds: 0, frames: 0)

    var displayString: String {
        let hh = String(format: "%02d", hours)
        let mm = String(format: "%02d", minutes)
        let ss = String(format: "%02d", seconds)
        let ff = String(format: "%02d", frames)
        return "\(hh):\(mm):\(ss):\(ff)"
    }

    static func atHour(_ hour: Int) -> TimecodeValue {
        TimecodeValue(
            hours: TimecodeSettings.clampedHour(hour),
            minutes: 0,
            seconds: 0,
            frames: 0
        )
    }

    func totalFrames(frameRate: TimecodeFrameRate) -> Int {
        if frameRate.isDropFrame {
            return Self.dropFrameTotalFrames(
                hours: hours,
                minutes: minutes,
                seconds: seconds,
                frames: frames
            )
        }

        let fps = frameRate.timecodeFramesPerSecond
        return ((hours * 60 + minutes) * 60 + seconds) * fps + frames
    }

    static func from(totalFrames: Int, frameRate: TimecodeFrameRate) -> TimecodeValue {
        let clamped = max(0, totalFrames)
        if frameRate.isDropFrame {
            return fromDropFrame(totalFrames: clamped)
        }

        let fps = frameRate.timecodeFramesPerSecond
        let frames = clamped % fps
        let totalSeconds = clamped / fps
        let seconds = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let minutes = totalMinutes % 60
        let hours = (totalMinutes / 60) % 24
        return TimecodeValue(hours: hours, minutes: minutes, seconds: seconds, frames: frames)
    }

    func advanced(byFrames delta: Int, frameRate: TimecodeFrameRate) -> TimecodeValue {
        Self.from(totalFrames: totalFrames(frameRate: frameRate) + delta, frameRate: frameRate)
    }

    func advanced(bySeconds seconds: TimeInterval, frameRate: TimecodeFrameRate) -> TimecodeValue {
        let deltaFrames = Int((seconds * frameRate.framesPerSecond).rounded(.down))
        return advanced(byFrames: deltaFrames, frameRate: frameRate)
    }

    /// SMPTE drop-frame frame count for 29.97 DF.
    private static func dropFrameTotalFrames(
        hours: Int,
        minutes: Int,
        seconds: Int,
        frames: Int
    ) -> Int {
        let totalMinutes = 60 * hours + minutes
        let dropFrames = 2 * (totalMinutes - totalMinutes / 10)
        return (
            (hours * 3600 + minutes * 60 + seconds) * 30
                + frames
                - dropFrames
        )
    }

    private static func fromDropFrame(totalFrames: Int) -> TimecodeValue {
        let framesPer10Minutes = 17982
        let framesPerMinute = 1798

        let d = totalFrames / framesPer10Minutes
        let m = totalFrames % framesPer10Minutes

        let totalFramesIncludingDrops: Int
        if m < 2 {
            // Exactly on a 10-minute boundary; no extra dropped frames in remainder.
            totalFramesIncludingDrops = totalFrames + 18 * d
        } else {
            totalFramesIncludingDrops = totalFrames + 18 * d + 2 * ((m - 2) / framesPerMinute)
        }

        let frames = totalFramesIncludingDrops % 30
        let totalSeconds = totalFramesIncludingDrops / 30
        let seconds = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let minutes = totalMinutes % 60
        let hours = (totalMinutes / 60) % 24
        return TimecodeValue(hours: hours, minutes: minutes, seconds: seconds, frames: frames)
    }
}

enum TimecodeStartCalculator {
    static func startTimecode(
        mode: TimecodeMode,
        startingHour: Int,
        songIndex: Int,
        priorSongDurations: [TimeInterval],
        frameRate: TimecodeFrameRate
    ) -> TimecodeValue {
        let hour = TimecodeSettings.clampedHour(startingHour)
        let index = max(0, songIndex)

        switch mode {
        case .resetPerSong:
            return .atHour(hour)

        case .perSongHour:
            return .atHour(hour + index)

        case .continuousShowTime:
            let base = TimecodeValue.atHour(hour)
            let priorSeconds = priorSongDurations.prefix(index).reduce(0, +)
            return base.advanced(bySeconds: priorSeconds, frameRate: frameRate)
        }
    }

    static func startTimecode(
        settings: TimecodeSettingsSnapshot,
        songIndex: Int,
        priorSongDurations: [TimeInterval]
    ) -> TimecodeValue {
        startTimecode(
            mode: settings.mode,
            startingHour: settings.startingHour,
            songIndex: songIndex,
            priorSongDurations: priorSongDurations,
            frameRate: settings.frameRate
        )
    }
}
