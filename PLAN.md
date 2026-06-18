# Metro Sound — Project Plan

A cross-platform practice companion for instrument learning books. Built first
for the **Ketab-e Aval (Tār, Book One)** mp3 set, but designed to hold any book.

Three core features:
1. **Music player** — load practice tracks the user imports from their device.
2. **Metronome** — an independent click that runs *over* the playing track, with
   independent mute and volume so either the music or the click can be louder.
3. **Practice photos** — attach photo(s) of the printed exercise to each track, so
   the user can glance at the sheet/notation while listening.

---

## 1. Decisions (locked)

| Area | Decision | Why |
|------|----------|-----|
| Framework | **Flutter** (Dart) | One codebase → iOS, macOS, Android (+ Windows/Linux/web for free). Mature audio + file libraries. |
| Audio source | **Import from device** | User picks files/a folder; app copies them into app storage. Supports any book, not just this one. No giant app binary. |
| Metronome | **Independent click** | Ticks at a user-set BPM, started/stopped manually. No audio analysis. Simplest reliable behavior. |
| Mixing | Two independent volume sliders + mute toggles | Lets either music or metronome be louder, as requested. |
| Storage | Local-first, on-device | No account/login needed for v1. Files + a small local DB. |

---

## 2. Target platforms

- **Phase 1: macOS desktop first** — fastest to build and test on this machine,
  easy file import, big screen for laying out the player + metronome visual.
- **Phase 2:** iOS + Android (the phone-in-your-practice-room case), same codebase.
- Windows/Linux/web are reachable later but not a goal.

---

## 3. Data model

A **Book** contains ordered **Tracks**. Each Track has audio, optional photos,
and saved metronome settings.

```
Book
  id            (uuid)
  title         e.g. "Ketab-e Aval — Tār"
  instrument    e.g. "Tar"
  createdAt

Track
  id            (uuid)
  bookId        (fk)
  order         int        // sort order within the book
  title         e.g. "Tar 01"  (parsed from filename, editable)
  audioPath     local file path inside app storage
  durationMs    cached after first load
  // saved metronome preset for this track:
  bpm           int        (default 80)
  timeSig       e.g. "4/4" (default 4/4)
  metronomeOn   bool

Photo
  id            (uuid)
  trackId       (fk)
  imagePath     local file path inside app storage
  order         int        // a track can have multiple pages
  caption       optional
```

Stored with a lightweight local DB (`drift` or `sqflite`). Imported audio and
photos are **copied** into the app's documents directory so they survive even if
the original Downloads files are deleted.

### Filename parsing
Files are named like `01-Tar_01.mp3`, `22-Tar_22.mp3`. On import we parse the
leading number for `order` and use the rest as a default `title` ("Tar 01"),
which the user can rename.

---

## 4. Screens / UX

### A. Library (home)
- List of books → tap a book → list of its tracks.
- Each track row: number, title, duration, 🎵 if audio present, 🖼 if photos present.
- "+" to **import audio** (multi-select files, or a whole folder) into a book.
- Create / rename / delete books.

### B. Player (the main screen)
The heart of the app. While a track plays:

- **Transport:** play/pause, seek bar with current/total time, previous/next track,
  optional loop-track and loop-A/B (great for drilling a phrase).
- **Speed:** playback-rate control (0.5×–1.5×) so hard passages can be slowed —
  pitch-preserved if the audio backend supports it.
- **Metronome panel:**
  - BPM number + tap-tempo button + −/+ and a dial/slider.
  - Time signature selector (2/4, 3/4, 4/4, 6/8…) with an accented downbeat.
  - Start/stop. Runs independently alongside the track.
- **Mixer (the requested control):**
  - **Music** row: mute toggle + volume slider.
  - **Metronome** row: mute toggle + volume slider.
  - So either source can be silenced or made louder than the other.
- **Metronome visual (new):**
  - A small animated metronome that swings/pulses on every beat, in sync with
    the click, with the downbeat accented (e.g. brighter flash or color).
  - User can **enable/disable the visual** independently (global default in
    Settings + a quick toggle on the player). Useful when sound is muted, or
    distracting when you want to focus on the page — hence the toggle.
  - Visual styles to consider: (a) a classic swinging-pendulum metronome shape,
    (b) a simple pulsing dot/ring beat indicator. Plan supports both; start with
    one and add the other as a style option.
- **Photo button:** if the track has photos, a button/thumbnail flips to the
  photo viewer (see C) without stopping playback.
- Settings here (BPM, time sig, metronome on/off) are **saved per track**.

### C. Photo viewer
- Full-screen, pinch-to-zoom, swipe between pages.
- Add photo (camera or gallery), reorder, delete, caption.
- Audio + metronome keep playing underneath; a mini-transport bar stays visible.

### D. Settings (global)
- Default BPM / time signature for new tracks.
- Metronome click sound choice (a couple of built-in samples).
- **Metronome visual:** enable/disable, and style (swinging pendulum vs pulsing dot).
- Keep-screen-awake while playing toggle.
- Theme (light/dark).

---

## 5. Audio architecture

The key technical point: **two simultaneous, independently-mixed audio streams.**

- **Music stream** — package `just_audio` (gapless, seeking, speed, volume,
  background playback, works on all targets).
- **Metronome stream** — a separate low-latency player so its volume/mute are
  independent of the music. Options:
  - `soundpool` / `audioplayers` firing a short click sample on a timer, **or**
  - a dedicated metronome package (e.g. `metronome`) for steadier timing.
- **Timing:** drive the click from a high-resolution scheduler, not a naive
  `Timer`, to avoid drift. Pre-schedule clicks slightly ahead of the audio clock.
- **Background / lock screen:** `audio_service` so music keeps playing and shows
  lock-screen controls. (Metronome typically pauses when backgrounded — decide
  per-platform.)
- **Routing:** both streams play to the same output (speaker/headphones). Volume
  sliders set each player's gain independently; mute = gain 0.

### Risks to watch
- **Latency / drift** between click and music on some Android devices — mitigate
  with look-ahead scheduling; accept that this is a *reference* click, not a
  sample-accurate sync (consistent with the "independent click" decision).
- **iOS audio session category** must allow mixing + background; configure once.

---

## 6. Storage & files

- On import: copy file → `<appDocs>/audio/<uuid>.mp3`, write a Track row.
- Photos: copy/compress → `<appDocs>/photos/<uuid>.jpg`.
- All paths are app-relative so the app is self-contained and survives source
  deletion. A future "export/backup book" can zip a book's files + metadata.

Relevant packages: `file_picker` (files/folder), `image_picker` (camera/gallery),
`path_provider`, `permission_handler`.

---

## 7. Suggested package set

| Need | Package |
|------|---------|
| Music playback | `just_audio` |
| Background / lock-screen | `audio_service` |
| Metronome click | `metronome` or `soundpool` + click sample |
| Local DB | `drift` (or `sqflite`) |
| File import | `file_picker` |
| Photo capture/pick | `image_picker` |
| Paths | `path_provider` |
| Permissions | `permission_handler` |
| State management | `riverpod` (or `provider`) |

---

## 8. Build phases / milestones

**M1 — Skeleton & import**
- Flutter project, navigation, DB schema.
- Import audio files → create a Book + Tracks, parse filenames.
- Library list working.

**M2 — Player core**
- `just_audio` playback, transport, seek, next/prev, per-track persistence.
- Playback speed + loop.

**M3 — Metronome + mixer + visual**
- Independent click with BPM, tap-tempo, time signature, accent.
- Two-channel mixer: music + metronome mute/volume. **(core requested feature)**
- **Visual metronome** (swinging pendulum / pulsing beat indicator) synced to the
  click, with downbeat accent and an enable/disable toggle. **(requested)**
- Save metronome preset per track.

**M4 — Photos**
- Attach/capture photos per track, multi-page viewer, zoom/swipe.
- Flip between player and photo without stopping audio.

**M5 — Polish & platforms**
- Background/lock-screen audio, keep-awake, theming, settings.
- macOS layout pass. Icons, splash, store metadata.

**M6 — (optional, later)**
- Tap-tempo→auto-align, A/B loop drilling, multi-book management,
  backup/export, cloud sync.

---

## 9. Open questions for later

- Should the metronome auto-stop when the track ends, or keep clicking?
- One photo per track or multiple pages? (plan supports multiple)
- Do you want playback speed in v1, or defer to M6?
- App name / icon.

---

## 10. First concrete step

Scaffold the Flutter app and get **import → list → play one track** working
(M1 + start of M2). Everything else builds on that loop.
