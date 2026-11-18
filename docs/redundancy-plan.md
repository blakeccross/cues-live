# Show redundancy plan

Status: proposal. Goal: two Macs or iPads run the same show in lockstep. If the primary fails, the
audience hears the backup with no gap, and the backup takes over control. Edits made on one machine
reach the other over the local network, with no internet or account required.

## Decisions

| Area | Choice | Why |
| --- | --- | --- |
| Audio failover | External hardware (iConnectivity PlayAUDIO12/1U, Radial SW4/SW8) watching a pilot tone | Software cannot unmute a machine that has crashed or frozen; the industry standard rig already works this way |
| Machine roles | One primary, one backup; the primary is the only writer | Avoids merge conflicts and split-brain edits |
| Transport | Existing `RemoteSession` stack: Bonjour + `NWConnection` | Discovery, PIN pairing, framing and ping/pong already exist |
| Link | Wired Ethernet (direct cable or show switch) | Wi-Fi/AWDL jitter is too high for timing; Wi-Fi is a fallback for file sync only |
| Media identity | SHA-256 content hash on `MediaReference` | Shared with `cloud-sync-plan.md` phase 3; paths differ between machines |
| Clock alignment | NTP-style offset estimate over ping/pong; starts scheduled at a future host time | Sample-accurate start without shared hardware clock |

## Principles

- **Both machines always play.** The backup is a hot standby, not a cold spare. Failover means
  switching which output is heard, never starting playback late.
- **Network loss never silences anything.** If the link drops, both machines keep playing and show
  "Not mirrored". Only the hardware switcher decides what the audience hears.
- **Local first.** Redundancy works with no internet and no account. Cloud sync, when it ships, is a
  second transport for the same documents, not a requirement.
- **Never sync during a song.** Documents sync at any time but apply on the backup at a song
  boundary (or as a live-edit command, see below). Stems copy only while stopped, or throttled while
  the backup is idle in the setlist.
- **Device settings stay local.** Output routing, MIDI devices, input mappings and timecode settings
  describe one machine's hardware and are not mirrored.

## Architecture

```
  Primary (Mac A)                                    Backup (Mac B)
 ┌──────────────────────────┐   Ethernet, TCP    ┌──────────────────────────┐
 │ PlaybackCoordinator      │                    │ PlaybackCoordinator      │
 │   │ commands             │                    │   ▲ scheduled commands   │
 │   ▼                      │                    │   │                      │
 │ MirrorLeader ────────────┼── command @ T ────▶│ MirrorFollower           │
 │   heartbeat, state hash ─┼── 20 Hz ──────────▶│   drift check, promote   │
 │ PeerDocumentSync ────────┼── changed(id,rev) ▶│ PeerDocumentSync         │
 │   serves docs + media ◀──┼── fetch ───────────┤   pulls, applies         │
 └──────────┬───────────────┘                    └──────────┬───────────────┘
            │ stems + pilot tone (ch N)                     │ stems + pilot tone (ch N)
            ▼                                               ▼
        ┌──────────────────────────────────────────────────────┐
        │ PlayAUDIO12 / Radial SW8: tone on A lost → switch to B │
        └──────────────────────────────┬───────────────────────┘
                                       ▼
                                 Front of house
```

## How edits reach the other machine

Yes, this is entirely local. It is the same push-on-save model as the cloud plan, with the primary
acting as the "server" over the existing local connection.

1. **Save hook.** Every write already goes through `ProjectFileStore.save` (songs and shows),
   `SongProjectBridge.persist`/`persistShow`, and `SongFolderStore`/`SetlistLibraryStore`. After a
   successful write, each posts a `DocumentChange(kind, id, revision, bodyHash)` to a
   `@MainActor` `DocumentChangeLog`. The cloud `SyncQueue` will subscribe to the same log later.
2. **Notify.** `PeerDocumentSync` on the primary sends a small `documentChanged(kind, id, revision,
   bodyHash, mediaHashes)` message to the connected backup. No file contents yet.
3. **Pull.** The backup compares against its own manifest. If the revision is newer, it requests
   `fetchDocument(id)`; the primary replies with the encoded body built by
   `SongProjectBridge.buildDocument` / `buildShowDocument` (not by reading the file, since setlists can
   exist without a show file). For each media hash the backup lacks, it queues `fetchMedia(hash)`.
4. **Apply.** The backup writes through `ProjectFileStore` and imports with
   `SongProjectBridge.applyDocument` / `importShow`, so SwiftData stays an index (`AGENTS.md`, Data).
   If the changed song is currently playing, the apply waits for the song boundary.
5. **Catch-up.** On every connect and reconnect, both sides exchange a full manifest
   (`[id: (kind, revision, bodyHash)]` plus the set of media hashes). Anything that differs is pulled
   as above. This covers edits made while the machines were apart, so notifications can be lost
   without harm; the manifest is the source of truth, notifications are a shortcut.

Edits on the backup are disabled by default ("Edit on the primary"). An opt-in "forward edits" mode
sends the edit to the primary as a command, the primary saves it, and the change comes back through
the normal path. The primary owns revision numbers, so there are never two writers.

If the machines diverged while apart (both edited offline), the newer revision wins and the other
is kept as "<Song> (backup copy)", matching the cloud plan's conflict copies.

### Media transfer

- Stems are content-addressed: the backup asks for a hash, not a path. A stem already present under
  any path on the backup (matched by hash) is linked, not copied.
- Transfer is a separate `NWConnection` so large files never delay heartbeats or commands. Chunks
  are resumable by byte offset and verified by hash before the reference resolves.
- Received media lives in a local media folder in Application Support; `MediaReferenceResolver`
  gains the lookup order path → bookmark → media folder by hash.

## Lockstep playback

### Clock alignment
- Every heartbeat round-trip refines an estimate of the offset between the two machines'
  `mach_absolute_time` clocks (keep the lowest-RTT samples; reject outliers).
- The leader sends each command with an execution time `T = now + 100 ms` in its own clock. The
  follower converts `T` to its clock and schedules with `AVAudioTime(hostTime:)`. The leader
  schedules itself at the same `T`, so both start together rather than the backup being late.

### Replicated commands
Anything that changes what plays is a command, sent with `T`:

- Transport: play, pause, stop, seek, next/previous song (the existing `RemoteSessionCommand` set).
- Section jumps and loop toggles (`SectionLoopController`).
- Group mix and fades (`GroupMixFadeController`), key and tempo changes.
- Live edits (`PlaybackCoordinator+LiveEdits`), carried as the edit itself so both machines change
  at the same musical moment.

Control input (MIDI pedals, keyboard) is accepted only on the current primary. A MIDI splitter to
both machines is supported: the backup ignores its local input while it is the follower and uses it
only after promotion.

### Drift
Two audio clocks drift a few ppm apart, about 1–6 ms over a five-minute song. The follower compares
its playhead against the leader's reported playhead (sent with each heartbeat with its timestamp):

- Under 2 ms: ignore.
- 2–20 ms: correct with a tiny rate change through `LiveStretcher` over a few seconds.
- Over 20 ms: show "Out of sync", and re-align at the next song start. Never seek audibly mid-song.

### State hash
Each heartbeat carries a hash of (setlist id, song id, playing, loop state, active sections, mix
state). A mismatch for more than one second shows "Out of sync" with the first differing field,
which makes replication bugs visible in rehearsal instead of at a show.

## Failure handling

| Failure | Audio | Control |
| --- | --- | --- |
| Primary app crash or power loss | Pilot tone stops, switcher moves to backup | Heartbeat lost → backup promotes after 300 ms |
| Primary UI frozen, audio running | Primary still heard (correct) | Heartbeats stop → backup promotes; primary demotes itself on recovery when it sees a newer epoch |
| Primary audio interface lost | `OutputRecoveryBackoff` recovers; tone gap triggers switcher | Primary reports `audioDegraded`; backup promotes |
| Network link lost | Both keep playing, nothing switches | Both show "Not mirrored"; neither promotes on network loss alone unless the operator confirms |
| Backup fails | Unaffected | Primary shows "Backup offline" |

- **Epochs.** Each promotion increments a role epoch carried in every message. A machine that sees
  a higher epoch than its own becomes follower. This prevents two primaries after a network flap.
- **Manual override.** A "Take over" button on the backup and a "Hand over" button on the primary,
  plus an optional mappable input, for the operator to force a role change.
- Switching back to the original primary is always manual.

## Pilot tone

A device-local output setting: "Redundancy pilot tone" with a channel picker in output routing.
It is a continuous low-level sine generated in a source node, routed through `StemMixer`,
running whenever the app is open (not only during playback) so the switcher stays armed. The tone
must stop if the render path stalls; generating it in the same engine as the stems guarantees this.

## Readiness check

The backup shows one status: **Ready**, **Syncing**, or **Not ready (reason)**. Ready requires:

- connected to the primary, roles agreed, clock offset converged;
- manifest identical: every document at the same revision;
- every media hash referenced by the current setlist present locally and decoded;
- same sample rate as the primary and pilot tone enabled on both;
- matching setlist and song loaded.

The primary shows the backup's status in the toolbar so the operator sees it before the show starts.

## New code

```
Services/Redundancy/
  RedundancySession.swift       @MainActor observable: role, epoch, peer status, readiness
  MirrorProtocol.swift          Messages: heartbeat, command@T, documentChanged, manifest, fetch*
  ClockOffsetEstimator.swift    Offset/RTT filtering (pure, unit-tested)
  MirrorLeader.swift            Sends commands with execution time, heartbeats, state hash
  MirrorFollower.swift          Schedules commands, drift correction, promotion
  RoleArbiter.swift             Epochs, promotion/demotion rules (pure, unit-tested)
  PilotToneSource.swift         Render-thread sine; no allocation, no locks
Services/Sync/
  DocumentChangeLog.swift       Save-hook fan-out; shared with cloud sync later
  DocumentManifest.swift        id → revision/hash; diffing (pure, unit-tested)
  PeerDocumentSync.swift        actor: notify, manifest exchange, pull/apply
  PeerMediaTransfer.swift       Hash-addressed, resumable transfer on its own connection
```

`MirrorProtocol` reuses `RemoteSessionFraming` and the Bonjour service, with a new message family and
a protocol version bump. The remote control client and the backup can be connected at the same
time.

Concurrency follows `AGENTS.md`: sync and transfer are actors, hashing runs on detached tasks,
session state is `@MainActor`, and only `PilotToneSource` and the existing players touch the render
thread.

## Phases

Each phase ships on its own with tests under `CuesLiveTests/`.

1. **Pilot tone.** Output setting and source node. Works with PlayAUDIO12/Radial today alongside a
   MIDI splitter, the same as MultiTracks Playback's redundancy mode.
2. **Format preparation.** `contentHash`/`byteCount` on `MediaReference`, hashing on import,
   backfill, resolver order (shared with cloud sync phase 3). Migration tests for old files.
3. **Local document sync.** `DocumentChangeLog`, manifests, notify/pull/apply, catch-up on
   reconnect, hash-addressed media transfer, readiness check. Useful on its own for keeping a
   second machine up to date even without lockstep playback.
4. **Lockstep transport.** Clock offset, commands with execution time, heartbeats, state hash,
   drift correction.
5. **Full command replication.** Sections, loops, mix, key/tempo, live edits; follower ignores local
   input.
6. **Roles and promotion.** Epochs, automatic promotion, manual take-over/hand-over, role UI.
7. **Hardening.** Rehearsal soak tests (hours of looping setlists), link flaps, sleep/wake on iPad,
   mismatched app versions refusing to pair.

## Testing

- Pure units first: `ClockOffsetEstimator` with synthetic jitter, `RoleArbiter` with scripted
  heartbeat loss and epoch races, `DocumentManifest` diffs.
- `PeerDocumentSync` tested with two in-process instances over a loopback connection.
- Lockstep alignment measured with a capture tap on each engine in the same process, in the style of
  the existing `SectionCueEngineTests` (and subject to the same timing caveats).

## Open questions

- **iPad as backup.** iPadOS suspends background apps; the backup must stay in the foreground with
  auto-lock disabled. Is an iPad backup to a Mac primary a supported configuration?
- **Mismatched versions.** Refuse to pair across protocol versions, or allow with a warning?
- **Without a switcher.** Offer a software-only mode where the backup unmutes on heartbeat loss,
  clearly labelled as weaker (it cannot handle a frozen-but-playing primary)?
- **Licensing.** Is redundancy a paid feature, as it is in Playback Premium?
- **More than two machines.** One primary with several backups adds little complexity to sync but
  more to role arbitration. Defer unless requested.

## Prior art

- MultiTracks Playback, Redundancy Mode: same setlist on two devices into a PlayAUDIO12, both driven
  by a MIDI controller.
- iConnectivity PlayAUDIO12 / PlayAUDIO1U: dual-USB interfaces that fail over when a tone channel
  goes silent.
- Radial SW4/SW8: analog auto-switchers driven by a pilot tone.
- ETC Eos, grandMA: tracking backup consoles that mirror show file and live state; the model for
  single-writer document sync and role epochs.
- disguise: "understudy" servers that take over for a failed media server.
