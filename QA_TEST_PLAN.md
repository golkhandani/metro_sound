# Metro Sound — Automated QA Sweep Plan

Purpose: drive every page of the app on the iOS Simulator, exercise every
interactive function, capture a screenshot of each state, then analyze the
screenshots for UI/UX problems, functional/test defects, and general QA issues.
Runs as an autonomous loop — one page area after another, no manual gating.

---

## How the loop works (methodology)

Driver: Flutter `integration_test` + `flutter drive` on the booted simulator
(`iPhone 17 Pro Max`, iOS 26.5). Widgets are found by visible text / icon /
type (no pixel-coordinate clicking), so runs are deterministic. After each
meaningful action the test captures a screenshot via
`IntegrationTestWidgetsFlutterBinding.takeScreenshot(name)`; the driver's
`onScreenshot` callback writes the PNG to `qa_artifacts/`.

Content is seeded with `--dart-define=QASEED=1` (a QA-only path in
`lib/dev/screenshot_director.dart`) so the library has books, tracks, photos,
BPM/time-sig and done-state to exercise real behavior. QASEED does **not**
auto-navigate and does **not** hide the dev Testing tools (unlike `SHOT=`).

### Per-iteration steps (one "loop" = one page area)
1. Navigate to the page.
2. Screenshot the initial/resting state (`NN-<page>-initial.png`).
3. Exercise every interactive function on that page (see checklists below),
   screenshotting after each state change (`NN-<page>-<action>.png`).
4. Return to a clean state and move to the next page.
5. After the run, read every screenshot for that area and record findings.

### What native pieces are out of scope for capture
Flutter-surface screenshots cannot capture OS-level surfaces: the iOS **share
sheet**, **file picker**, and the **mic permission** dialog. These are noted as
"native — verify manually" where a function depends on them. Everything drawn by
the app itself is captured.

---

## Finding taxonomy (what to look for in each screenshot)

- **UI** — spacing/alignment, inconsistent icon sizes, truncation/overflow,
  contrast/legibility (light + dark), hit-target size, inconsistent labels,
  theme bugs (light-mode regressions).
- **UX** — confusing flows, missing feedback (no toast/loading), destructive
  actions without confirm, discoverability, empty/loading state quality.
- **Functional / Test** — control does nothing, wrong value, state not
  persisted, crash, incorrect enable/disable, sync/timing bugs.
- **QA / polish** — copy/typos, placeholder/dev content leaking, missing
  a11y labels, redundant controls.

Each finding: `severity (high/med/low) · category · page · what · repro · fix idea`.

---

## Pages & functions to exercise

Bottom nav (order): **Library · Metronome · Tuner · Settings**. Detail screens
(Book, Player, Photo Viewer, Record, Advanced) push over the shell.

### 1. Onboarding (`onboarding_screen.dart`)
Reached on first launch / Settings → Replay tutorial.
- Swipe through 4 pages; verify dots update.
- `SKIP` (hidden on last page).
- Primary button: `Next` (pages 1–3) → `Get started` (page 4).

### 2. Library / Books (`books_screen.dart`) — Tab 0
- App bar: **Import shared library** (Pro-gated at cap), **New book** (Pro-gated at cap, free = 1 book).
- Empty state: "No books yet" + **New Book**.
- Book tile: tap → Book; long-press / `⋯` → context menu.
- Context menu: **Rename**, **Add/Change cover**, **Share book** (0-track toast), **Remove cover**, **Delete** (confirm).
- Pro sheet appears on create/import at cap.

### 3. Book (`book_screen.dart`)
- App bar: **Play all**, **Record** (Pro-gated), **Share book** (0-track toast), **Import audio**.
- Empty state: **Import Audio** + **Record**.
- Progress bar; **ReorderableListView**.
- Track row: tap → Player; long-press/`⋯` → menu; **done checkbox**; **drag handle** reorder.
- Track menu: **Rename**, **Mark done/not done**, **Share track**, **Share audio file**, **Delete** (confirm).

### 4. Player (`player_screen.dart`)
- Speed segmented: **1× / 1.5× / 2× / 3×**.
- Metronome card: BPM ± / slider (20–300) / **Tap** / time-sig menu (13 presets) / **Click** toggle / **Lock click to music** / **Visual metronome** / **Sync offset** (± / slider / label).
- Mixer: music fader (mute + slider), metronome fader (mute + slider).
- Photos card: **View**, thumbnails tap, **Add photo** (native picker).
- Done switch: **Mark track as completed**.
- Transport: waveform seek (tap/drag), **Restart**, **skip prev/next**, **Play/Pause**.

### 5. Photo Viewer (`photo_viewer_screen.dart`)
- **Add photo** (native), **Delete photo** (confirm), swipe pages, pinch/pan zoom, empty state.

### 6. Record (`record_screen.dart`) — Pro-gated, mic permission
- Settings sheet: tempo ±, **Count-in**, **Click while recording**, **Quality** segmented (disabled mid-take).
- Capture: **record**, **pause/resume**, **stop**, **reset**, level meter, count-in.
- Review: trim handles drag, **Preview**, **Re-record**, **Save** (name prompt).
- Error view when mic denied: **Try again**.

### 7. Metronome (`metronome_screen.dart`) — Tab 1
- **VISUAL** switch, pendulum, beat dots, BPM ± / slider, **Tap**, time-sig menu, **start/stop**, volume fader (mute + slider).

### 8. Tuner (`tuner_screen.dart`) — Tab 2, mic permission
- Mic priming dialog (**Continue**) first entry.
- Note naming segmented (**C D E / Do Re Mi**), accidental segmented (**♭ / ♯ / ♭♯**), **Quarter-tones** switch, gauge, mic state / error.

### 9. Settings (`settings_screen.dart`) — Tab 3
- Testing section (test-build only): **Storage & data cleanup**, **Reset purchase** → Advanced.
- Pro card: **Unlock Pro**, **Restore purchase** (or "Pro unlocked").
- Appearance: **System / Light / Dark** (re-test key screens in light).
- Metronome toggles: **Lock click**, **Visual metronome**.
- Share libraries: **Share my library** (no-books toast), **Import shared library** (Pro-gated).
- Drive Sync (feature-flag off by default — note if hidden).
- Help: **Replay tutorial**.
- About: version string (check `1.0.0`).

### 10. Advanced (`advanced_screen.dart`) — test-build only
- **Clear cache** (confirm + toast), **Erase all data** (confirm + result dialog), **Reset purchase (local)** (confirm + toast).

### 11. Pro paywall sheet (`pro_sheet.dart`)
- Reason copy, 4 benefits, **Unlock Pro — $2.99 once**, **Restore purchase**, **Not now**.

### Cross-cutting
- Global export/import chip + **Package progress sheet**.
- **Import preview sheet** (native file pick to open).
- **Coach marks** overlay (tap advances, **Skip**, **Next/Done**).

---

## Artifacts & output
- Screenshots: `qa_artifacts/NN-<page>-<action>.png`.
- Findings report: `QA_FINDINGS.md` — grouped by page, each finding tagged with
  severity/category and a fix idea, plus a summary table at the top.

## Test harness files
- `integration_test/qa_*.dart` — one file per page area (run sequentially).
- `test_driver/integration_test.dart` — driver with `onScreenshot` writer.
- `QASEED` seed path in `lib/dev/screenshot_director.dart`.
