import SwiftUI

/// Shown while the audio output is gone and the engine is waiting to rebuild it.
struct AudioOutputLostBanner: View {
    /// The device is listed but will not start, so waiting will not help.
    var isUnresponsive = false

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(isUnresponsive ? "Audio device is not responding" : "Audio output disconnected")
                    .font(.headline)
                Text(detail)
                    .font(.caption)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.85))
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        if isUnresponsive {
            return "The system can see the device but cannot start it. Power-cycle the interface, or restart Core Audio."
        }
        return "Playback is paused. It will reconnect when the device returns; press play to continue."
    }
}
