/// Google OAuth credentials for Drive sync.
///
/// These are injected at build time from a gitignored `env.json` via
/// `--dart-define-from-file=env.json` (see env.example.json and
/// GOOGLE_DRIVE_SETUP.md). Nothing secret lives in source control.
///
/// If they're empty (no env file passed), the Settings screen shows a
/// "not configured" message instead of the sign-in button.
const String googleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');
const String googleClientSecret =
    String.fromEnvironment('GOOGLE_CLIENT_SECRET');

bool get googleConfigured =>
    googleClientId.isNotEmpty && googleClientSecret.isNotEmpty;
