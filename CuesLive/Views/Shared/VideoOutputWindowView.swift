import SwiftUI

enum VideoWindowID {
    static let value = "video-output"
}

/// The Video window: the active song's movie, full bleed on black, following its audio.
/// It is meant for a projector or second display, so status text only appears on hover or tap.
@MainActor
struct VideoOutputWindowView: View {
    @Bindable private var output = VideoOutputController.shared
    @State private var showsStatus = false

    var body: some View {
        ZStack {
            AppColors.Video.pictureBackground
            VideoPlayerSurface(player: output.player)
                .aspectRatio(output.info?.aspectRatio ?? 16.0 / 9.0, contentMode: .fit)
                .opacity(output.placement != nil && output.isPictureVisible ? 1 : 0)
            if showsStatus, let status = statusText {
                Text(status)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.Video.statusText)
                    .padding(AppSpacing.md)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        #if os(macOS)
        .onHover { showsStatus = $0 }
        .videoWindowFullScreen()
        #else
        .onTapGesture { showsStatus.toggle() }
        .persistentSystemOverlays(.hidden)
        .statusBarHidden()
        #endif
        .onAppear { output.windowDidAppear() }
        .onDisappear { output.windowDidDisappear() }
    }

    private var statusText: String? {
        guard let songName = output.songName, !songName.isEmpty else {
            return "No song is playing. Open a setlist or a song to show its video."
        }
        if output.isVideoMissing {
            return "Can’t find the video file for \(songName)."
        }
        if output.placement == nil {
            return "\(songName) has no video."
        }
        return output.isPictureVisible ? songName : "\(songName): the playhead is outside the video."
    }
}
