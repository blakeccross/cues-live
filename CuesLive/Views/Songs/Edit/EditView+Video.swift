import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#endif

extension EditView {
    var videoFileURL: URL? {
        FileStore.videoURL(for: song)
    }

    func videoLane(_ video: VideoTrack, height: CGFloat, originY: CGFloat) -> some View {
        VideoLaneView(
            video: video,
            fileURL: videoFileURL,
            durationSeconds: videoInfo?.durationSeconds ?? video.sourceDurationSeconds,
            aspectRatio: videoInfo?.aspectRatio ?? 16.0 / 9.0,
            timelineDuration: timelineDuration,
            timelineContentWidth: timelineContentWidth,
            laneHeight: height,
            laneOriginY: originY,
            tempoChanges: normalizedTempoChanges,
            timeSignatureChanges: normalizedTimeSignatureChanges,
            actions: clipLaneActions,
            onMoveStart: moveVideoStart(to:)
        )
        .frame(width: timelineContentWidth, alignment: .leading)
    }

    func videoTrackHeader(_ video: VideoTrack) -> some View {
        VideoTrackHeaderView(
            video: video,
            laneHeight: TrackLaneHeight.resolved(video.laneHeight),
            isSelected: selectedTrackIDs.contains(video.id),
            isFileMissing: videoFileURL == nil,
            canAlignToInsertion: abs(insertionTime - video.startSeconds) > ClipEditing.tolerance,
            onSelect: { modifiers in
                selectedTrackIDs = TrackSelection.click(
                    id: video.id,
                    in: selectedTrackIDs,
                    order: displayedTrackIDs,
                    modifiers: modifiers
                )
            },
            onRename: renameVideo,
            onShowWindow: showVideoWindow,
            onReplace: presentVideoImporter,
            onAlignToInsertion: { moveVideoStart(to: insertionTime) },
            onResetStart: { moveVideoStart(to: 0) },
            onDelete: removeVideo,
            onResize: { resizeLane(video.id, by: $0) },
            onResizeEnded: finishLaneResize
        )
    }

    func showVideoWindow() {
        openWindow(id: VideoWindowID.value)
    }

    /// Where the movie ends on the timeline, so the editor lays out room for all of it.
    var videoEndSeconds: TimeInterval {
        guard let video = song.videoTrack,
              let duration = videoInfo?.durationSeconds ?? video.sourceDurationSeconds else { return 0 }
        return video.startSeconds + duration
    }

    func presentVideoImporter() {
        #if os(macOS)
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = FileStore.supportedVideoTypes
            panel.prompt = song.videoTrack == nil ? "Add" : "Replace"
            panel.message = "Choose a video to play in the Video window with this song."
            guard panel.runModal() == .OK, let url = panel.url else { return }
            attachVideo(from: url)
        }
        #else
        showingVideoImporter = true
        #endif
    }

    func handleVideoImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            attachVideo(from: url)
        }
    }

    /// Adds `url` as the song's movie, or swaps the file of the existing one and keeps its start.
    func attachVideo(from url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        Task { @MainActor in
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            guard let info = await FileStore.videoInfo(at: url) else {
                importError = "\(url.lastPathComponent) has no video that can be played."
                return
            }
            do {
                let projectURL = try SongProjectBridge.ensureProjectFile(for: song, context: modelContext)
                let media = MediaReference.from(url: url, relativeTo: projectURL)
                let name = url.deletingPathExtension().lastPathComponent
                performUndoableChange(song.videoTrack == nil ? "Add Video" : "Replace Video") {
                    setVideo(media: media, name: name, info: info)
                }
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    private func setVideo(media: MediaReference, name: String, info: VideoFileInfo) {
        if let video = song.videoTrack {
            video.mediaReference = media
            video.displayName = name
            video.sourceDurationSeconds = info.durationSeconds
        } else {
            let video = VideoTrack(displayName: name, media: media)
            video.sourceDurationSeconds = info.durationSeconds
            video.song = song
            modelContext.insert(video)
            song.videoTrack = video
        }
        videoInfo = info
        try? modelContext.save()
        persistProjectState()
    }

    func moveVideoStart(to seconds: TimeInterval) {
        guard let video = song.videoTrack, seconds.isFinite, video.startSeconds != seconds else { return }
        performUndoableChange("Move Video") {
            video.startSeconds = seconds
            try? modelContext.save()
            persistProjectState()
        }
    }

    func renameVideo() {
        try? modelContext.save()
        persistProjectState()
    }

    func removeVideo() {
        guard let video = song.videoTrack else { return }
        performUndoableChange("Remove Video") {
            selectedTrackIDs.remove(video.id)
            song.videoTrack = nil
            modelContext.delete(video)
            videoInfo = nil
            try? modelContext.save()
            persistProjectState()
        }
    }

    /// Reads the movie's size and length for the lane, and caches the length in the song.
    func refreshVideoInfo() async {
        guard let url = videoFileURL else {
            videoInfo = nil
            return
        }
        let info = await FileStore.videoInfo(at: url)
        videoInfo = info
        if let info, let video = song.videoTrack, video.sourceDurationSeconds != info.durationSeconds {
            video.sourceDurationSeconds = info.durationSeconds
            try? modelContext.save()
            persistProjectState()
        }
    }
}
