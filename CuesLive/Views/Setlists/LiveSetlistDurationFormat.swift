import Foundation

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
