# Google Drive sync — one-time setup

The app needs its own Google OAuth credentials to access *your* Drive. You
create these once in the Google Cloud Console (free). Takes ~10 minutes.

## 1. Create a project
1. Go to <https://console.cloud.google.com/>.
2. Top bar → project dropdown → **New Project** → name it e.g. `Metro Sound` → **Create**.
3. Make sure that project is selected.

## 2. Enable the Drive API
1. Left menu → **APIs & Services → Library**.
2. Search **Google Drive API** → open it → **Enable**.

## 3. Configure the OAuth consent screen
1. **APIs & Services → OAuth consent screen**.
2. User type: **External** → **Create**.
3. Fill in **App name** (`Metro Sound`), your **email** for support and developer
   contact. Leave the rest blank → **Save and Continue**.
4. **Scopes**: click **Add or remove scopes**, search for
   `.../auth/drive.file` (label: *"See, edit, create, and delete only the
   specific Google Drive files you use with this app"*), check it → **Update** →
   **Save and Continue**.
5. **Test users**: click **Add users**, add your own Google email → **Save and
   Continue**. (While the app is in "testing", only listed test users can sign
   in — that's fine for personal use.)

## 4. Create the OAuth client
1. **APIs & Services → Credentials → Create Credentials → OAuth client ID**.
2. Application type: **Desktop app**.
3. Name it `Metro Sound Desktop` → **Create**.
4. Copy the **Client ID** and **Client secret** shown in the dialog.

> For a desktop ("installed") app, Google does not treat the client secret as
> confidential — it's expected to ship inside the app. That's why we store it in
> the config file below.

## 5. Put them in env.json (gitignored)
Copy the example file and fill in your values:

```bash
cp env.example.json env.json
```

```json
{
  "GOOGLE_CLIENT_ID": "1234567890-abcdef.apps.googleusercontent.com",
  "GOOGLE_CLIENT_SECRET": "GOCSPX-xxxxxxxxxxxxxxxx"
}
```

`env.json` is gitignored, so credentials never reach the repo. Build/run with:

```bash
flutter run    -d macos --dart-define-from-file=env.json
flutter build  macos     --dart-define-from-file=env.json
```

In **Settings → Google Drive sync** you'll now see a **Connect** button:
- **Connect** opens your browser, you approve access, and you're signed in.
- **Back up to Drive** uploads everything to a **Metro Sound** folder in your Drive.
- **Load catalog from Drive** pulls it back (use on a new device).

## Notes
- Scope is `drive.file`: the app can only see/manage the files **it** creates —
  it cannot read the rest of your Drive.
- The "Metro Sound" folder is a normal, visible folder in My Drive.
- Sign-in is remembered between launches (a refresh token is stored locally).
- When you're ready to let other people use it, you'd "Publish" the consent
  screen and go through Google verification — not needed for personal use.
