# MCP server plan

Status: proposal. Goal: Claude, Codex, Cursor and other MCP clients can build setlists, import and
edit songs, and inspect the library in a running copy of cues.live, with every change undoable and
visible in the UI.

## Decisions

| Area | Choice | Why |
| --- | --- | --- |
| Transport | MCP Streamable HTTP, served by the app on `127.0.0.1` | Every major client supports HTTP servers; no helper binary; `network.server` is already entitled in both targets |
| Implementation | Small in-house JSON-RPC over HTTP/1.1 on `NWListener` | Tool calls only need plain JSON responses (SSE optional); avoids a dependency for a few hundred lines |
| Auth | Bearer token generated per install, shown in Settings | Any local process can reach a loopback port |
| Edit path | One shared editing service used by both `EditView` and MCP | Agent edits must follow the same rules, undo stack and persistence as UI edits |
| Concurrency control | Per-document revision; edits carry `baseRevision` | User and agent can edit at the same time without silent overwrites |
| Platforms | macOS first; iPad later behind a LAN toggle | Agents run on desktops; an iPad server must be reachable over the network and needs stricter auth |

## Principles

- **Same path as the UI.** No tool writes SwiftData or project files directly. Writes go through
  `ProjectFileStore` / `SongProjectBridge` and the editing services (`AGENTS.md`, Data).
- **Every change is undoable.** Each tool call is one undo step named after the action, for example
  "Agent: Add 6 sections". Batched edits are one step.
- **Visible.** Agent edits appear live in an open editor and in a short activity log in the toolbar.
- **Musical units.** Tools accept and return bars/beats as well as seconds, because agents reason in
  "chorus at bar 33". Conversion uses `TempoTimeline`.
- **Never during a show.** While a setlist is live, write tools return a `liveLocked` error.
- **Stable ids.** Every song, setlist, entry, section, track and group is addressed by UUID; list tools
  return ids so agents never match by name.

## The prerequisite: extract editing out of `EditView`

Setlist editing is already in a view model (`SetlistViewModel.insertSong`, `moveEntries`,
`setTransition`, …) and library operations are in services (`SetlistLibraryStore`,
`SongLibraryStore`, `SongFolderStore`, `SongFolderImporter`, `ClickSongCreator`). Song editing is
not: sections (`addSection`, `moveSection`, `applySectionRename`, `detectSections`), tempo and meter
(`applyTempoChange`, `retimeLockedTracks`, `moveTimeSignatureMarker`) and clips live in
`EditView+*.swift` extensions holding view `@State`.

Introduce a `@MainActor` `SongEditSession` per song that owns the timeline, tempo map, time
signatures, track edits and the `SongUndoController`, and exposes intent-level methods:

```swift
@MainActor final class SongEditSession {
    let songID: UUID
    private(set) var revision: Int
    func addSection(named: String?, at position: TimelinePosition) throws -> SongSection
    func renameSection(_ id: UUID, to name: String) throws
    func moveSection(_ id: UUID, toIndex: Int) throws
    func setTempo(_ bpm: Double, from: TimelinePosition, lockedTrackIDs: Set<UUID>) throws
    func apply(_ edits: [SongEdit], actionName: String) throws   // one undo step
    ...
}
```

A `SongEditSessionRegistry` hands out one session per open song, so `EditView` and an MCP call
editing the same song share state and the view updates when the agent edits. Songs not open in the
editor get a temporary session that loads the document, applies, persists and closes.

This refactor is worth doing on its own: it moves logic out of views as `AGENTS.md` requires, makes
song editing unit-testable, and shrinks `EditView+Timeline.swift` (562 lines). It is also the edit
hook the redundancy and cloud sync plans need (`DocumentChangeLog`).

## Tools

### Read
| Tool | Returns |
| --- | --- |
| `get_app_state` | Current screen, open song, live setlist and playhead, live lock state |
| `list_songs(query?, folderID?)` | id, name, key, tempo, duration, folder, media health |
| `get_song(id, include?)` | Metadata, sections (seconds + bar/beat), tempo map, meters, tracks, groups, `revision` |
| `list_setlists` / `get_setlist(id)` | Entries (songs and headers), transitions, `revision` |
| `list_folders`, `list_groups` | ids and names |
| `preview_import_folder(path)` | What `SongFolderImporter.previewFolder` would create |

### Setlists
`create_setlist(name, songIDs?)`, `rename_setlist`, `duplicate_setlist`, `delete_setlist`,
`add_songs_to_setlist(setlistID, songIDs, index?)`, `add_header(setlistID, title, index)`,
`move_entries`, `remove_entries`, `set_transition(entryID, transition)`.
All map onto `SetlistViewModel` and `SetlistLibraryStore`.

### Songs
- Create: `import_song_from_folder(path, settings?)`, `create_click_song(name, bpm, meter, bars)`,
  `duplicate_song`, `delete_song`, `move_songs_to_folder`.
- Metadata: `update_song(id, name?, key?, ...)`, `change_key(id, key)` (through `applyKeyChange`).
- Arrangement: `add_section`, `rename_section`, `move_section`, `delete_section`,
  `set_sections(id, sections[])` (replace all), `detect_sections(id)`.
- Tempo and meter: `set_tempo_map(id, changes[])`, `set_time_signatures(id, changes[])`.
- Tracks: `update_track(id, volume?, muted?, groupID?)`, `auto_assign_groups(songID)`.
- Batch: `apply_song_edits(id, baseRevision, edits[])`: an ordered list of the above, applied
  atomically as one undo step. This is the tool agents will use most; single-edit tools are
  conveniences over it.

### Undo
`undo(songID)` / `redo(songID)` for the song's stack, and `list_recent_agent_changes`.

### Resources
`cueslive://song/{id}` and `cueslive://setlist/{id}` expose the same JSON as `get_song` and
`get_setlist`, for clients that attach resources as context.

## Revisions and conflicts

Every song and setlist has a `revision` that increments on each save (shared with the redundancy
plan's `DocumentChangeLog`). Write tools require `baseRevision`; if the user edited since the agent
read, the tool fails with `staleRevision` and the current revision, and the agent re-reads.
`apply_song_edits` validates all edits before applying any.

## File access and the sandbox

The app is sandboxed, so it cannot open an arbitrary path an agent sends. Options, in order:

1. **Granted library folders.** Settings lists folders the user has granted once (security-scoped
   bookmarks). `import_song_from_folder` accepts paths inside them; anything else fails with
   `accessNotGranted` and the folder to grant.
2. **Grant on demand.** For other paths the app shows an open panel pre-pointed at the path; the
   tool call waits until the user approves or cancels (with a timeout).

The App Store build uses the same mechanism; no new entitlements are needed.

## Security and safety

- Listen on loopback only; reject requests whose `Origin` is not absent or local (DNS-rebinding
  protection, required by the MCP spec).
- Bearer token required on every request; "Regenerate" in Settings revokes old configs.
- Permission level in Settings: **Off** (default), **Read only**, **Read and edit**. Delete tools
  additionally require `confirm: true` and are listed separately so clients prompt the user.
- Live lock: all writes are refused while a setlist is live.
- Settings offers "Copy setup command", for example
  `claude mcp add --transport http cueslive http://127.0.0.1:<port>/mcp --header "Authorization: Bearer <token>"`,
  and the equivalent JSON for other clients.

## New code

```
Services/Editing/
  SongEditSession.swift          @MainActor: intent-level song edits, undo, persist, revision
  SongEditSessionRegistry.swift  One session per song, shared by EditView and MCP
  SongEdit.swift                 Codable enum of edit operations (used by batch + tests)
  TimelinePosition.swift         seconds | bar/beat, converted with TempoTimeline
Services/MCP/
  MCPServer.swift                NWListener, HTTP/1.1 parsing, auth, Origin check
  MCPJSONRPC.swift               Request/response/error types, initialize, tools/list, tools/call
  MCPToolRegistry.swift          Tool definitions with JSON Schemas, dispatch
  MCPTools+Library.swift         Read and library tools
  MCPTools+Setlists.swift
  MCPTools+Songs.swift
  MCPSettingsStore.swift         Enabled, permission level, port, token (Keychain)
  MCPActivityLog.swift           @MainActor observable list of recent agent changes
Views/Settings/
  MCPSettingsView.swift
```

The server runs off the main actor; each tool call hops to the main actor for SwiftData and the
edit services (`await`, not `MainActor.run`). Long tools (`detect_sections`, imports) do their heavy
work in detached tasks as the UI does today.

## Phases

1. **Extract song editing.** `SongEditSession`, registry, `SongEdit`, `TimelinePosition`; move
   `EditView+Sections` and `EditView+TempoAndMeter` logic into it; `EditView` becomes a client.
   Tests for every edit and its undo. No user-visible change. *Largest phase.*
2. **Server core.** HTTP, JSON-RPC, initialize/tools list/tools call, token, Origin check, settings
   screen, read tools. Verified with the MCP Inspector and Claude Code.
3. **Setlist and library tools.** Thin wrappers over existing services.
4. **Song editing tools.** Single edits, `apply_song_edits`, revisions, undo tools, activity log,
   live lock.
5. **Import.** Granted folders, grant-on-demand, `import_song_from_folder`, `create_click_song`.
6. **Polish.** Tool descriptions tuned from real agent sessions, MCP prompts (for example "Build a
   setlist from these songs"), iPad LAN mode if wanted.

## Testing

- `SongEditSession` and `SongEdit` get full unit tests (phase 1); they carry most of the risk.
- Tool handlers tested by calling the registry directly with JSON arguments and an in-memory
  `ModelContainer`; one end-to-end test posts JSON-RPC to the listener on an ephemeral port.
- No tests of SwiftUI layout (`AGENTS.md`, Tests).

## Open questions

- **Clip-level editing.** Splitting, trimming, fades and gain are fiddly to express as tool
  arguments. Ship sections/tempo/tracks first and add clips if agents need them?
- **Audio understanding.** Agents cannot hear stems. Exposing `detect_sections` and waveform
  summaries (loudness per bar) would let them place sections sensibly. Worth a tool?
- **Notifications.** Should the server push `notifications/resources/updated` over SSE when the user
  edits, or is polling with revisions enough for the first release?
- **Paid feature?**
