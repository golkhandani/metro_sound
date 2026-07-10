/// Feature flags, settable at build time via --dart-define / env.json.
///
/// Google Drive sync is fully built but hidden for the initial release — it
/// may ship later as a regular or paid feature. Enable it in a dev build by
/// adding `"FEATURE_DRIVE_SYNC": true` to env.json.
const bool driveSyncEnabled =
    bool.fromEnvironment('FEATURE_DRIVE_SYNC', defaultValue: false);
