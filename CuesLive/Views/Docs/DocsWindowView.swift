import SwiftUI

struct DocsWindowView: View {
    @State private var selectedTopic: DocsTopic = .gettingStarted

    var body: some View {
        NavigationSplitView {
            docsSidebar
        } detail: {
            DocsTopicDetailView(topic: selectedTopic)
        }
        .navigationSplitViewStyle(.balanced)
        .background(AppColors.backgroundSecondary)
        .preferredColorScheme(.dark)
    }

    private var docsSidebar: some View {
        List(selection: $selectedTopic) {
            ForEach(DocsSection.allCases) { section in
                let topics = DocsTopic.visibleTopics(in: section)
                if !topics.isEmpty {
                    Section(section.title) {
                        ForEach(topics) { topic in
                            Label(topic.title, systemImage: topic.systemImage)
                                .tag(topic)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Help")
        #if os(macOS)
        .frame(minWidth: 200)
        #endif
    }
}

struct DocsTopicDetailView: View {
    let topic: DocsTopic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                Text(topic.title)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(AppColors.textPrimary)

                topicContent
            }
            .padding(AppSpacing.lg)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.backgroundSecondary)
        #if os(macOS)
        .navigationTitle(topic.title)
        #endif
    }

    @ViewBuilder
    private var topicContent: some View {
        switch topic {
        case .gettingStarted:
            GettingStartedDocContent()
        case .songsAndEditing:
            SongsAndEditingDocContent()
        case .setlists:
            SetlistsDocContent()
        case .livePlayback:
            LivePlaybackDocContent()
        case .mapping:
            MappingDocContent()
        case .remoteSessions:
            RemoteSessionsDocContent()
        case .audioOutputs:
            AudioOutputsDocContent()
        case .timecode:
            TimecodeDocContent()
        case .fileFormats:
            FileFormatsDocContent()
        case .keyboardShortcuts:
            KeyboardShortcutsDocContent()
        case .about:
            AboutDocContent()
        }
    }
}

// MARK: - Shared doc components

struct DocParagraph: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(AppColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct DocHeading: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(AppColors.textPrimary)
            .padding(.top, AppSpacing.xs)
    }
}

struct DocBulletList: View {
    let items: [LocalizedStringKey]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: AppSpacing.sm) {
                    Text("•")
                        .foregroundStyle(AppColors.accent)
                    Text(item)
                        .font(.body)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct DocNumberedList: View {
    let items: [LocalizedStringKey]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: AppSpacing.sm) {
                    Text("\(index + 1).")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppColors.accent)
                        .frame(width: 22, alignment: .trailing)
                    Text(item)
                        .font(.body)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct DocDefinitionRow: View {
    let term: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(term)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary)
            Text(detail)
                .font(.body)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct DocLinkRow: View {
    let title: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: AppSpacing.xs) {
                Text(title)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
            }
            .font(.body.weight(.medium))
            .foregroundStyle(AppColors.accent)
        }
    }
}

#if os(macOS)
struct DocShortcutRow: View {
    let title: String
    let shortcut: String

    var body: some View {
        HStack {
            Text(title)
                .font(.body)
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
            Text(shortcut)
                .font(.body.monospaced())
                .foregroundStyle(AppColors.textPrimary)
        }
        .padding(.vertical, 2)
    }
}
#endif

// MARK: - Topic content

private struct GettingStartedDocContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            DocParagraph("cues.live is a live multitrack stem player for macOS and iPadOS. Import stems per song, build setlists, and perform with transport controls, fades, and section loops.")

            DocHeading(title: "Quick workflow")
            DocNumberedList(items: [
                "Create a **song** in the Songs sidebar and import stem files.",
                "Open the song to trim tracks, edit the arrangement, and set mix levels.",
                "Create a **setlist** and add songs in performance order.",
                "Open the setlist for live playback with next, previous, fade, and loop controls.",
            ])
        }
    }
}

private struct SongsAndEditingDocContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            DocParagraph("Each song holds multiple audio stems that play in sync. Open a song from the Songs sidebar to enter the editor.")

            DocHeading(title: "Importing stems")
            DocBulletList(items: [
                "Supported formats: .wav, .aiff, .mp3, .m4a",
                "Import multiple files at once — each becomes a track",
                "Use **Song → Add Ableton File** to import from an Ableton project",
            ])

            DocHeading(title: "Editing")
            DocBulletList(items: [
                "Set non-destructive trim in/out points on each track",
                "Arrange sections on the timeline and adjust tempo or time signature changes",
                "Use **Auto Group** to organize tracks into mix groups",
                "Add click, cue, and MIDI tracks for live cues",
            ])
        }
    }
}

private struct SetlistsDocContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            DocParagraph("Setlists define the order of songs for a show. Save setlists as .cueshow files and open them for live performance.")

            DocHeading(title: "Building a setlist")
            DocBulletList(items: [
                "Create a new setlist from the setlist switcher in the toolbar",
                "Add songs from your library and drag to reorder",
                "Configure **overlap transitions** between songs for crossfades",
            ])

            DocHeading(title: "Missing media")
            DocParagraph("If audio files move on disk, cues.live shows a warning on affected songs. Use **Relink Missing Files** from the song's context menu to point to the new location.")
        }
    }
}

private struct LivePlaybackDocContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            DocParagraph("The setlist screen is your live performance view. Transport controls drive playback across all stems in the current song.")

            DocHeading(title: "Transport")
            DocBulletList(items: [
                "**Play / Pause** — start or pause the current song",
                "**Stop** — stop and return to the start",
                "**Fade** — fade out the current song and advance",
                "**Loop** — loop the current section",
                "**Next / Previous** — move between setlist songs",
            ])

            DocHeading(title: "Mixer")
            DocParagraph("Open the **Group Mixer** to adjust group levels and mutes during performance. Track groups are configured in Settings → Groups.")

            DocHeading(title: "Song library")
            DocParagraph("Toggle the **Songs** sidebar to browse your library without leaving the live screen. On macOS you can also open a song editor from here.")
        }
    }
}

private struct MappingDocContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            DocParagraph("Assign keyboard keys or MIDI notes to transport actions and individual setlist songs for hands-free control.")

            DocHeading(title: "Live mapping")
            DocBulletList(items: [
                "Open **Controls → Key Mapping** or **MIDI Mapping** on macOS",
                "On iPad, use the mapping button in the live toolbar",
                "Tap a control (Stop, Play, Fade, Loop, or a song row), then press a key or MIDI note",
                "Press **Escape** to cancel mapping on macOS",
            ])

            DocHeading(title: "Managing mappings")
            DocParagraph("View and edit all bindings in **Settings → Mapping**. Mapped actions work the same as tapping the on-screen controls.")
        }
    }
}

private struct RemoteSessionsDocContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            DocParagraph("Control playback from another device on the same Wi‑Fi network. The Mac typically hosts audio; an iPad can join as a remote controller.")

            DocHeading(title: "Hosting")
            DocBulletList(items: [
                "Open **Settings → Remote** and enable **Allow Remote Control**",
                "Share the 4-digit password with the connecting device",
                "Keep cues.live open on the setlist screen while hosting",
            ])

            DocHeading(title: "Joining")
            DocBulletList(items: [
                "On the remote device, open **Settings → Remote**",
                "Select the host from the discovered devices list",
                "Enter the password shown on the host Mac",
            ])
        }
    }
}

private struct AudioOutputsDocContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            DocParagraph("Route track groups to separate physical outputs for FOH, monitors, or click feeds.")

            DocHeading(title: "Output routing")
            DocBulletList(items: [
                "Open **Settings → Audio** on macOS or **Outputs** on iPad",
                "Assign each track group to an output destination",
                "Changes take effect on the next playback start",
            ])

            DocHeading(title: "Track groups")
            DocParagraph("Groups are edited in **Settings → Groups**. Each group can have its own output, level, and mute state during live performance.")
        }
    }
}

private struct TimecodeDocContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            DocParagraph("Send linear timecode (LTC) alongside audio for syncing external gear, video, or lighting.")

            DocHeading(title: "Setup")
            DocBulletList(items: [
                "Open **Settings → Timecode**",
                "Choose an LTC output destination",
                "Set the frame rate and start timecode offset",
                "LTC is generated during live playback from the current song position",
            ])
        }
    }
}

private struct FileFormatsDocContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            DocDefinitionRow(
                term: ".cueslive",
                detail: "Song project file. Stores arrangement, tempo map, trim points, mix settings, and references to audio files on disk."
            )
            DocDefinitionRow(
                term: ".cueshow",
                detail: "Setlist file. Stores song order, overlap transition settings, and references to .cueslive song projects."
            )

            DocParagraph("Project files store **references** to audio — stems are not copied into the project. Keep media files accessible at their saved paths, or use **Export Setlist Folder** to bundle a show for transfer.")
        }
    }
}

#if os(macOS)
private struct KeyboardShortcutsDocContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            DocHeading(title: "Setlist")
            shortcutsBlock([
                ("New setlist", "⌘N"),
                ("Open setlist", "⌘O"),
                ("Save", "⌘S"),
                ("Save As", "⇧⌘S"),
                ("Export Setlist Folder", "⇧⌘E"),
            ])

            DocHeading(title: "Song editor")
            shortcutsBlock([
                ("Undo / Redo", "⌘Z / ⇧⌘Z"),
                ("Split at Edit Point", "⌘T"),
                ("Join with Next Region", "⌘J"),
                ("Auto Group", "⇧⌘G"),
                ("Add Ableton File", "⇧⌘I"),
            ])

            DocHeading(title: "App")
            shortcutsBlock([
                ("Settings", "⌘,"),
                ("Help", "⌘?"),
            ])
        }
    }

    private func shortcutsBlock(_ rows: [(String, String)]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                DocShortcutRow(title: row.0, shortcut: row.1)
                if index < rows.count - 1 {
                    Divider().background(AppColors.separator)
                }
            }
        }
        .padding(AppSpacing.sm)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
    }
}
#else
private struct KeyboardShortcutsDocContent: View {
    var body: some View { EmptyView() }
}
#endif

private struct AboutDocContent: View {
    private let repoURL = URL(string: "https://github.com/blakeccross/cues-live")!

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            DocParagraph("cues.live — live multitrack stem playback for macOS and iPadOS.")

            LabeledContent("Version") {
                Text(appVersionLabel)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .font(.body)

            DocParagraph("Logo design by Tyler Lamb.")

            DocHeading(title: "Resources")
            DocLinkRow(title: "View on GitHub", url: repoURL)

            #if os(macOS)
            DocParagraph("Check for updates from **cues.live → Check for Updates** or **Settings → General**.")
            #endif
        }
    }

    private var appVersionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}
