/// Feature flags, settable at build time via --dart-define / env.json.
///
/// Google Drive sync is fully built but hidden for the initial release — it
/// may ship later as a regular or paid feature. Enable it in a dev build by
/// adding `"FEATURE_DRIVE_SYNC": true` to env.json.
const bool driveSyncEnabled = bool.fromEnvironment(
  'FEATURE_DRIVE_SYNC',
  defaultValue: false,
);

/// iCloud sync (iOS/macOS): mirrors the whole library to the user's private
/// iCloud Drive container so it converges across their devices — no backend on
/// our side. Built behind a flag; enable in a dev build with
/// `"FEATURE_ICLOUD_SYNC": true` in env.json (needs the iCloud capability +
/// container provisioned, and a real device signed into iCloud to test).
const bool icloudSyncEnabled = bool.fromEnvironment(
  'FEATURE_ICLOUD_SYNC',
  defaultValue: false,
);
