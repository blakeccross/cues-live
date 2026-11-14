# Cloud sync and subscriptions plan

Status: proposal. Goal: a paid subscription that backs up a user's songs, setlists, folders and
stems to the cloud and makes them available on their other Macs and iPads.

## Decisions

| Area | Choice | Why |
| --- | --- | --- |
| Auth, database, server functions | Supabase (Auth, Postgres, Edge Functions) | Managed Postgres with row-level security; Sign in with Apple support; no servers to run |
| Audio storage | Cloudflare R2 | No egress fees; stems are gigabytes and every device downloads them |
| Direct-download billing | Paddle (merchant of record) | Handles VAT/sales tax; licence and subscription webhooks |
| App Store billing | StoreKit 2 | Required for in-app purchase in the App Store build |
| Client networking | `URLSession` against a small REST API | Avoids a large SDK dependency; background sessions for audio |

Lemon Squeezy is an acceptable substitute for Paddle; only the webhook handler changes.

## Principles

- **Offline first.** Local files stay authoritative on each device. The cloud is a replica, and the
  app must play a setlist with no network.
- **Never stream during a show.** Audio is downloaded before playback; a setlist cannot start live
  with stems that are not local.
- **Never lock a performer out.** A lapsed or unverifiable subscription stops syncing. It does not
  stop playback of local songs.
- **Device settings stay local.** Output routing, timecode, MIDI devices and input mappings describe
  one machine's hardware and are not synced.

## Architecture

```
 Mac / iPad app                         Backend
 ┌──────────────────────┐   HTTPS/JSON   ┌───────────────────────────┐
 │ AccountSession       │ ─────────────▶ │ Supabase Auth             │
 │ EntitlementStore     │ ─────────────▶ │ Edge Functions (API)      │
 │ SyncEngine (actor)   │ ◀────────────▶ │ Postgres (RLS)            │
 │ MediaTransfer        │                │                           │
 │  (background URLSession)              │ Webhooks: Paddle,         │
 └─────────┬────────────┘                │  App Store Server Notif.  │
           │ presigned PUT/GET           └────────────┬──────────────┘
           ▼                                          │ presigns
     ┌──────────────┐ ◀────────────────────────────────┘
     │ Cloudflare R2 │  users/<uid>/media/<sha256>
     └──────────────┘
```

### Server data model

- `entitlements(user_id, source [paddle|app_store], product, status, expires_at, updated_at)`
- `devices(id, user_id, name, platform, last_seen_at)`
- `documents(id uuid, user_id, kind [song|setlist|folder], revision bigint, body jsonb,
  deleted_at, updated_at, updated_by_device, change_seq bigserial)`
- `media_objects(user_id, hash, byte_count, format, r2_key, state [pending|complete], created_at)`
- `document_media(document_id, hash)`: which songs reference which stems, for garbage collection

Every table has row-level security keyed on `auth.uid()`. R2 is never public; clients only receive
presigned URLs with short lifetimes.

### API (Edge Functions)

| Endpoint | Purpose |
| --- | --- |
| `GET /entitlement` | Current subscription state plus a signed, expiring entitlement token |
| `POST /entitlement/app-store` | Verify a StoreKit 2 signed transaction and link it to the account |
| `GET /changes?since=<seq>` | Documents changed after a cursor, including tombstones |
| `PUT /documents/:id` | Upsert with `baseRevision`; `409` with the server copy on conflict |
| `DELETE /documents/:id` | Tombstone |
| `POST /media/upload-intent` | `{hash, byteCount}` → `exists`, or presigned multipart part URLs; enforces quota |
| `POST /media/:hash/complete` | Finish a multipart upload |
| `GET /media/:hash` | Presigned download URL |
| `DELETE /account` | Delete the account and all data (App Store requirement) |
| `POST /webhooks/paddle`, `POST /webhooks/app-store` | Update `entitlements` |

A scheduled function deletes R2 objects no longer referenced by any live document after a grace
period, and purges data for accounts whose subscription lapsed beyond the retention window.

## Client changes

### Document format (no network; ship first)

These changes are needed so a document means the same thing on every device. Each new field gets a
default so existing files decode, plus a migration test (`AGENTS.md`, Availability and Data).

- **`MediaReference`** (`Models/Project/MediaReference.swift`): add `contentHash: String?` (SHA-256
  of the original file) and `byteCount: Int64?`. Today a reference is a path plus a bookmark, which
  only resolves on the machine that made it.
- **`ShowProjectEntry`** (`Models/Project/ShowProjectDocument.swift`): add `songID: UUID?`. Entries
  currently point at songs by `ProjectDocumentReference` path; resolve by id first, path second.
- **Song folders**: `SongFolder` exists only in SwiftData. Sync folders as their own `folder`
  documents and add `folderID: UUID?` to `SongProjectMetadata` so membership travels with the song.
- **Hashing**: compute `contentHash` when stems are imported (`FileStore.linkTracks`,
  `SongFolderImporter`, `AbletonProjectImporter`), streaming with CryptoKit off the main actor. Add a
  one-time backfill for existing libraries that runs in the background and checks cancellation.
- **`MediaReferenceResolver`**: resolution order becomes path → bookmark → local media cache by hash.

### New services

```
Services/Account/
  AccountSession.swift        @MainActor observable: signed-in user, sign in/out, delete account
  AuthClient.swift            Sign in with Apple and email via Supabase Auth REST
  KeychainTokenStore.swift    Access and refresh tokens
  EntitlementStore.swift      Cached signed entitlement, offline grace, StoreKit 2 listener
Services/Sync/
  CloudAPIClient.swift        Typed REST calls, token refresh, retry with backoff
  SyncEngine.swift            actor: pull/push loop, cursor, conflict handling
  SyncQueue.swift             Persisted pending operations (survives relaunch and offline)
  DocumentSyncer.swift        Maps SwiftData/documents ⇄ server bodies
  MediaCache.swift            Content-addressed store in Application Support, eviction, pinning
  MediaTransfer.swift         Background URLSession multipart upload and download, resumable
  MediaEncoder.swift          WAV/AIFF → ALAC before upload; lossy formats pass through
```

Hooks into existing code:

- **Push on save.** Every write already goes through `ProjectFileStore.save` (songs and shows) and
  `SongFolderStore`/`SetlistLibraryStore`. Each enqueues a push after a successful write. Setlists can
  exist without a show file, so `DocumentSyncer` builds bodies with `SongProjectBridge.buildDocument`
  and `buildShowDocument` rather than reading files.
- **Apply on pull.** Incoming songs are written to the app container with `ProjectFileStore` and
  imported through `SongProjectBridge.applyDocument` / `importShow`, so SwiftData stays an index.
- **Playback preflight.** Extend `SongMediaHealth` with a "cloud, not downloaded" state. Starting a
  setlist live with missing local stems offers to download first instead of playing.

Concurrency follows `AGENTS.md`: `SyncEngine` and `MediaCache` are actors, hashing and encoding run
on detached tasks, UI-facing state is `@MainActor`, and nothing touches the render thread.

## Sync behaviour

- **Cursor-based pull.** The client stores the last `change_seq` and pulls on launch, on foreground,
  after each push, and on a timer while open.
- **Optimistic push.** `PUT` carries `baseRevision`. On `409` the client keeps the server version as
  the document and saves the local version as a copy named "<Song> (conflict, <device>)". A merge UI
  is out of scope for the first release.
- **Media ordering.** A song's document is pushed immediately; its stems upload in the background.
  Other devices see the song at once, and stems still uploading show as "Uploading from <device>".
- **Deduplication.** Upload-intent returns `exists` for a hash the user already stored, so
  duplicated songs and re-imports cost nothing.
- **Deletes** are tombstones, kept long enough for offline devices to catch up.
- **iPad storage.** Media lives in Application Support (excluded from backup, never purged by the
  OS mid-show). Songs in the current setlist are pinned; others are evicted least-recently-used
  above a user-set limit. "Make available offline" pins a setlist explicitly.

## Subscriptions and entitlements

- The server is the single source of truth: Paddle webhooks and App Store Server Notifications v2
  both write `entitlements`. A user who buys on one store gets sync on every build.
- The client caches a server-signed entitlement token with an expiry. While offline, sync stays
  enabled until the token expires plus a grace period (proposed 30 days).
- On lapse: sync pauses, local data keeps working, cloud data is retained for a set window
  (proposed 90 days) with a warning email before deletion.
- The App Store build sells only through StoreKit. The direct build opens Paddle checkout in the
  browser, then signs in.

## Phases

Each phase ships on its own and adds tests under `CuesLiveTests/` for the new services.

1. **Backend foundation.** Supabase project (staging and production), R2 bucket, schema, RLS,
   entitlement and webhook functions, account deletion. Paddle products in sandbox.
2. **Accounts and entitlements in the app.** Sign in with Apple and email, Keychain tokens,
   `EntitlementStore` with offline grace, StoreKit 2 in the App Store target, account screen in
   Settings.
3. **Format preparation.** `contentHash`, `songID`, `folderID`, hashing on import, backfill,
   resolver order. Migration and decode tests for old `.cueslive`/`.cueshow`/`.cueset` files. No
   network; safe to ship before sync.
4. **Document sync.** `SyncQueue`, `SyncEngine`, `DocumentSyncer`, conflict copies, tombstones,
   sync status in the UI. Songs and setlists appear on other devices without their audio.
5. **Media sync.** Encoding, multipart upload, downloads, `MediaCache`, pinning and eviction,
   playback preflight, storage usage in Settings.
6. **Hardening.** Large libraries, poor networks, interrupted uploads, sign-out wiping local cloud
   state, quota errors, server-side rate limits, monitoring.
7. **Later.** Shared team setlists, a conflict merge UI, a web dashboard.

## Open questions

- **What the subscription gates.** Only cloud sync, or the whole direct-download app? This decides
  whether the update feed also needs gating.
- **Storage limits.** One quota for everyone (for example 100 GB) or tiered plans.
- **Licensed stems.** Many users run commercially licensed multitracks. Terms of service must make
  users responsible for the rights to what they upload, and a DMCA agent must be registered. Check
  common vendors' licences to see whether cloud copies are allowed for a user's own devices.
- **Upload original or ALAC.** ALAC roughly halves WAV size losslessly but costs encode time on
  import. Uploading originals is simpler.
- **Retention and grace windows.** The 30-day offline and 90-day lapse values above are proposals.
- **Privacy.** A privacy policy and App Store privacy details are needed before release.

## Costs (rough)

R2 storage is about $0.015 per GB-month with free egress, so a user storing 20 GB costs about
$0.30 a month. Supabase's paid tier starts around $25 a month. Paddle takes about 5% plus $0.50 per
transaction, and the App Store takes 15–30%.
