# cues.live

Live multitrack stem playback for worship and stage teams, built with SwiftUI for macOS and iPadOS. Import stems, arrange sections, add a click track and Smart Guide section call-outs, and run a setlist from one screen.

Requires macOS 14+ or iOS/iPadOS 17+.

## Features

**Songs & editing**
- Import stems (`.wav`, `.aiff`, `.mp3`, `.m4a`), a folder of stems, or an Ableton Live set
- Timeline editor with non-destructive trims, gaps and clip regions, plus undo/redo
- Arrangement sections with tempo and time-signature maps, and a section-loop mode
- Generated click tracks and Smart Guide, a live voice that calls sections one measure early and on every loop pass
- MIDI lanes that send cues to external devices
- Track groups with colors and per-group mix

**Setlists & live playback**
- Ordered setlists with overlap transitions between songs
- Live waveform view, group mixer, mute/solo, and section jumping with gain ramping
- Per-group output routing across multi-channel audio interfaces, with recovery when a device drops out
- SMPTE LTC timecode output
- Key and MIDI mapping for any live control
- Remote sessions: control playback from another device on the same network (for example, an iPad controlling a Mac)

**Files**
- `.cueslive` song project files (arrangement, tempo, media references; audio stays on disk)
- `.cueshow` setlist files

An in-app guide (Help → cues.live Help) covers each of these in more detail.

## Getting started

Clone the repo, then open the project and run the **CuesLive** scheme on **My Mac** or an iPad destination:

```bash
open CuesLive.xcodeproj
```

Typical workflow:

1. **Songs** → New Song → import stems
2. Open the song to trim tracks, arrange sections, and set tempo, key and groups
3. **Setlists** → New Setlist → add songs in order
4. **Play Setlist** for live playback

Sample stems for manual testing are in `TestStems/`.

## Source layout

```
CuesLive/
├── DesignSystem/     Colors, spacing, typography, shared components
├── Models/           SwiftData models and project-file documents
├── Resources/        Click samples, spoken section guides, document icons
├── Services/
│   ├── Playback/     Audio engine, transport, coordinator, buffers, overlaps
│   ├── Output/       Device discovery and per-group output routing
│   ├── GuideTracks/  Click track generation and scheduling, bundled section-name voice samples
│   ├── Timecode/     LTC generation and timecode settings
│   ├── MIDI/         MIDI input, output and cue scheduling
│   ├── Input/        Key and MIDI mapping
│   ├── Editing/      Arrangement, trims, regions, ripple edits, undo
│   ├── Project/      Project/setlist files, imports, media resolution
│   └── RemoteSession/ Host/client remote control over the network
├── ViewModels/
└── Views/
    ├── Songs/        Library, song detail, and the editor (Songs/Edit)
    ├── Timeline/     Timeline lanes, rulers, waveform and layout
    ├── Setlists/     Live playback, mixer, overlap editor
    ├── Settings/
    ├── Shared/       Transport strip, mix controls, mapping UI
    └── Docs/         In-app help
CuesLiveTests/        Unit tests
Scripts/              DMG packaging
```

## Architecture

- SwiftData indexes the song/setlist library and stores app settings
- Song data lives in `.cueslive` project files; setlists reference them via `.cueshow` files
- `AVAudioEngine` drives synced multitrack playback; `PlaybackCoordinator` owns setlist-level state
- Audio files are referenced on disk, not copied into the app bundle (use media consolidation to collect them)

## Releasing (macOS)

Pushing a `v*` tag runs `.github/workflows/release-macos.yml`, which builds a Developer ID–signed, notarized app, packages a DMG, and publishes a Sparkle appcast. Required secrets are listed at the top of the workflow file.
