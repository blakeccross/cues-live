import SwiftUI

/// Points the Video window at `song` while the view is on screen, following `engine`'s playhead.
/// The claim is updated whenever the song's video changes and handed back when the view goes away.
@MainActor
struct VideoOutputClaimModifier: ViewModifier {
    let song: Song?
    let engine: AudioEngineManager
    var isEnabled = true

    @State private var owner = UUID()

    private struct ClaimKey: Equatable {
        var isEnabled: Bool
        var songID: UUID?
        var songName: String?
        var videoID: UUID?
        var mediaPath: String?
        var startSeconds: Double?
        var durationSeconds: Double?
        var engine: ObjectIdentifier
    }

    private var claimKey: ClaimKey {
        let video = song?.videoTrack
        return ClaimKey(
            isEnabled: isEnabled,
            songID: song?.id,
            songName: song?.name,
            videoID: video?.id,
            mediaPath: video?.mediaPath,
            startSeconds: video?.startSeconds,
            durationSeconds: video?.sourceDurationSeconds,
            engine: ObjectIdentifier(engine)
        )
    }

    func body(content: Content) -> some View {
        content
            .onAppear(perform: updateClaim)
            .onChange(of: claimKey) { _, _ in updateClaim() }
            .onDisappear {
                VideoOutputController.shared.release(owner)
            }
    }

    private func updateClaim() {
        if isEnabled {
            VideoOutputController.shared.claim(owner, song: song, engine: engine)
        } else {
            VideoOutputController.shared.release(owner)
        }
    }
}

extension View {
    func videoOutputClaim(song: Song?, engine: AudioEngineManager, isEnabled: Bool = true) -> some View {
        modifier(VideoOutputClaimModifier(song: song, engine: engine, isEnabled: isEnabled))
    }
}
