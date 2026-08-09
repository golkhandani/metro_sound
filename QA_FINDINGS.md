# Metro Sound — Automated QA Sweep: Findings

Method: every page was driven on the **iPhone 17 Pro Max simulator (iOS 26.5)**
by a Flutter `integration_test` harness (see `QA_TEST_PLAN.md`), seeded with
`--dart-define=QASEED=1`. Each control was exercised and a screenshot captured
after each state change (artifacts in `qa_artifacts/`). Screens covered: Library,
Book, track/book menus, Player, Photo viewer, Metronome, Tuner, Settings
(light + dark), Advanced, Record, Pro paywall, package export sheet, onboarding.

## Verdict

The app is **polished and functionally solid**. No crashes, broken controls, or
data bugs were found in the app itself. Verified correct: done-toggle updates the
progress bar (57%→43%), track reorder re-sequences, theme switch is instant,
speed/BPM/time-signature/segmented controls all respond, destructive actions
confirm before acting. Findings below are mostly minor UI/UX polish plus a few
items that need on-device verification (mic-dependent features can't run in the
simulator).

## Findings

| # | Sev | Area | Page | Issue |
|---|-----|------|------|-------|
| 1 | Low | UI consistency | Player, Metronome | Time-sig **button** reads `4/4` (no spaces) but the **picker menu** listed `4 / 4` (spaces). **✅ Fixed** — menu now uses `4/4`. |
| 2 | Low | UI consistency | Book track rows | Photo count used an emoji `📷` instead of a Material icon. **✅ Fixed** — replaced with `Icons.photo_outlined`. |
| 3 | Low–Med | UX clarity | Track menu | `Share track` vs `Share audio file` — labels didn't convey the difference. **✅ Fixed** — added menu subtitles ("Audio, tempo & photos — opens in Metro Sound" / "Just the audio — for any app"). |
| 4 | — | Layout | Player | ~~SYNC OFFSET row occluded by transport bar~~ **Not a bug** — the transport bar is a `Column` sibling below the body, not an overlay; the earlier screenshot was just mid-scroll. |
| 5 | Med | Functional (verify on device) | Tuner | In the simulator the tuner shows `Mic off` (no simulator mic); real pitch detection still needs **on-device** verification. **✅ Improved** — the off-state now reads `Mic off · tap to start` and is tappable to retry without leaving the tab. (Genuine permission/capture failures already showed a clear red message.) |
| 6 | Low | UI consistency | Metronome | The time signature appears twice (app-bar subtitle **and** the picker button). |
| 7 | Low | UX | Library | A fully-completed book (e.g. `6/6`) had no distinct visual state. **✅ Fixed** — completed books now show a check-circle in the progress badge. |
| 8 | Low | Consistency | Metronome vs Player | The same "start metronome" action is a large amber circle on the Metronome tab but a small `Click` pill in the Player's metronome card. |

### Detail & fix ideas

1. **Time-sig formatting** — pick one format. The menu's `N / N` is more legible;
   apply it to the button too (or vice-versa). Files: player_screen / metronome_screen time-sig button vs `showStudioMenu` presets. *(This also confirms the picker works — the menu lists 2/4…9/8.)*
2. **Emoji photo badge** — replace `📷` with `Icon(Icons.photo_outlined)` sized to
   match the BPM/meta row.
3. **Share labels** — e.g. `Share track (with settings & photos)` and
   `Export audio only`, or add one-line subtitles in the menu.
4. **Sync row occlusion** — add bottom padding to the Player `ListView` equal to
   the transport bar height so the last row isn't hidden.
5. **Tuner mic** — verify on device that *Continue* → `Listening…` and the needle
   responds. The mic method channel was previously known-unregistered; confirm the
   fallback path actually starts capture on-device. Consider a visible hint if
   capture fails.
6. **Duplicate time sig** — optional; the subtitle is informative, the button is
   the control. Fine to keep, noted for awareness.
7. **Completed book state** — a subtle check badge or accent when `done == total`.
8. **Start-control consistency** — acceptable (different contexts); noted.

## What's working well (positives)

- **Destructive confirmations** are excellent: *Delete "track"?* and *Erase all
  data?* have clear copy, red confirm buttons, and Cancel — the erase dialog even
  notes Pro isn't affected and to force-quit after.
- **Light and dark themes** both render cleanly with good contrast; the amber
  accent adapts (deeper gold on light, brighter on dark). Theme switch is instant.
- **Pro paywall and gates** are clear and consistent across every entry point
  (new book, import, recorder, settings).
- **Package export** works: "Ready to share" sheet (whole library, 5 books,
  91.7 MB) with a global "Ready — tap to share" chip; clear Share-libraries copy.
- **Recorder** full flow works end-to-end (Pro-unlocked via a QA flag): settings
  sheet (count-in / click / quality), record → pause/resume → stop, then the
  review/trim screen (teal handles, Selection 00:05 of 00:05), Preview, and the
  "Name this recording" save prompt. Waveform is flat because the simulator has no
  audio input — verify the waveform renders real audio on device.
- **Photo viewer** works: counter (1/2), add/delete icons, swipe between photos,
  delete confirm.
- **Dev/test tools** (Settings → Testing, Advanced) are correctly gated to test
  builds and will not appear in the App Store build.

## Not covered in the simulator (verify manually / on device)

- **Tuner pitch detection** and the **Recorder's captured audio/waveform** — both
  need a real microphone (the simulator has no input, so the tuner shows "Mic off"
  and recordings are silent). The *UI flows* for both were fully exercised.
- **Native surfaces**: iOS share sheet, file pickers (audio import, book cover,
  add photo), and the mic-permission prompt — driven by the OS, not capturable by
  the Flutter test.
- **Coach-marks** overlay — appears on a timing that the automated run couldn't
  reliably capture; verify manually via Settings → Replay tutorial.

## Harness notes

The sweep is repeatable: `test_driver/integration_test.dart` +
`integration_test/qa_*.dart`, run with
`flutter drive --driver=… --target=integration_test/qa_<area>.dart -d <sim> --dart-define=QASEED=1`
(add `--dart-define=QAPRO=true` for the Record screen). If screenshots come back
uniformly black after many consecutive runs, reboot the simulator
(`xcrun simctl shutdown/boot`) — that is a simulator rendering-surface quirk, not
an app fault.
