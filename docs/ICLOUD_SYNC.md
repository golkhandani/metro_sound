# iCloud Sync — setup & how it works

Two-way sync of the whole library through the user's **private iCloud Drive
container**. No backend on our side — the data lives in the user's own iCloud.
Built behind the `FEATURE_ICLOUD_SYNC` flag (off by default).

## One-time provisioning (must be done in Xcode — account/portal step)

The Dart + plugin side is complete, but iCloud needs an entitlement that Apple
must provision. Do this once:

1. Open `ios/Runner.xcworkspace` in Xcode.
2. Select the **Runner** target → **Signing & Capabilities**.
3. Ensure the team is **Next Horizon Technologies (XV4PS5W8YH)** and
   "Automatically manage signing" is on.
4. Click **+ Capability → iCloud**. Check **iCloud Documents**.
5. Under Containers, add/select
   **`iCloud.ca.nexthorizontechnologies.metrosound.app`**
   (Xcode creates it in the Developer portal and updates the provisioning
   profile).

Xcode will point `CODE_SIGN_ENTITLEMENTS` at `Runner/Runner.entitlements`
(already created with the right container id) and provision the container. Until
this is done, do **not** build with `FEATURE_ICLOUD_SYNC=true` on a signed
target — signing will fail because the profile lacks the iCloud entitlement.

> Note: enabling the capability adds the iCloud entitlement to the app's
> provisioning profile, which then applies to **all** builds of the Runner
> target. Do it when you're ready to test/ship iCloud, and re-cut a normal
> release build afterward so the store build carries the (provisioned)
> entitlement.

## Building with the feature on

```
flutter run --dart-define=FEATURE_ICLOUD_SYNC=true
# or add "FEATURE_ICLOUD_SYNC": true to env.json and --dart-define-from-file=env.json
```

## Testing (needs real devices)

iCloud can't be validated in the simulator/CI. On two devices signed into the
**same iCloud account**:

1. Enable **Settings → iCloud Sync → Sync with iCloud** on device A.
2. Add/edit a book or track on A; wait for status **Synced**.
3. Enable it on device B → the library converges (pull-merge on enable + poll).
4. Edit on B, confirm it flows back to A. Delete on one, confirm the tombstone
   removes it on the other.

## How it works (architecture)

`ICloudSyncService` (`lib/services/icloud_sync.dart`) is a transport twin of
`DriveSyncService`. It reuses the sync engine already in `LibraryStore`:

- **Convergence hash** `catalogSignature()` (loop-stop / "are we in sync?").
- **Merge** `mergeRemote()` — last-write-wins per entity by `updatedAt`, unions
  tombstones (deletes propagate, don't resurrect).
- **Basename-keyed media** — audio/photos/covers are immutable per id, so a file
  that already exists locally is the same content (skip download).

Container layout (relative to the container's Documents):

| Path | Contents |
|------|----------|
| `library.json` | catalog payload = local library.json + `signature` + `writer` (device id) |
| `audio/<basename>` | track audio |
| `photos/<basename>` | sheet photos |
| `covers/<basename>` | book covers |

Cycle: on local edit (3s debounce) and every 30s poll → **pull-merge** (cheap
`contentChangeDate` check, then `signature` check, download only newer media,
`mergeRemote`) → **push** if the local signature is ahead. `writer`/`signature`
+ `lastSeenRemoteSig` stop a device pulling its own push back. Convergence state
is persisted device-locally in `icloud_sync.json` (Application Support).

Transport = the `icloud_storage` plugin (`gather` / `upload` / `download` /
`delete`) against the ubiquity container.
