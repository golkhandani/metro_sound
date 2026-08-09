import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config/features.dart';
import 'services/audio_controller.dart';
import 'services/drive_sync.dart';
import 'services/icloud_sync.dart';
import 'services/library_store.dart';
import 'services/metronome.dart';
import 'services/package_service.dart';
import 'services/pro.dart';
import 'dev/screenshot_director.dart';
import 'services/sample_library.dart';
import 'services/settings.dart';
import 'services/tuner.dart';
import 'screens/onboarding_screen.dart';
import 'screens/root_shell.dart';
import 'ui/studio.dart';
import 'widgets/keep_awake.dart';
import 'widgets/package_job_overlay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final library = LibraryStore();
  final metronome = Metronome();
  final drive = DriveSyncService();
  final icloud = ICloudSyncService();
  final settings = AppSettings();
  final packages = PackageService();
  final pro = Pro();
  await Future.wait([
    library.init(),
    metronome.init(),
    if (driveSyncEnabled) drive.init(),
    if (icloudSyncEnabled) icloud.init(),
    settings.init(),
    packages.init(),
    pro.init(),
  ]);
  // Wire the library into Drive sync so two-way auto-sync can observe edits.
  // (Skipped while the feature is hidden — no Google sign-in work at launch.)
  if (driveSyncEnabled) await drive.attachLibrary(library);
  // iCloud sync observes the same library edits (iOS/macOS, behind a flag).
  if (icloudSyncEnabled) await icloud.attachLibrary(library);
  packages.attachLibrary(library);
  // Dev-only App Store screenshot rig (inert without --dart-define=SHOT).
  await ScreenshotDirector.prepare(library, settings);
  // First install: a small "Getting Started" book so the library isn't empty.
  await SampleLibrary.seedIfNeeded(library, settings);

  runApp(
    MetroSoundApp(
      library: library,
      metronome: metronome,
      drive: drive,
      icloud: icloud,
      settings: settings,
      packages: packages,
      pro: pro,
    ),
  );
}

class MetroSoundApp extends StatefulWidget {
  final LibraryStore library;
  final Metronome metronome;
  final DriveSyncService drive;
  final ICloudSyncService icloud;
  final AppSettings settings;
  final PackageService packages;
  final Pro pro;
  const MetroSoundApp({
    super.key,
    required this.library,
    required this.metronome,
    required this.drive,
    required this.icloud,
    required this.settings,
    required this.packages,
    required this.pro,
  });

  @override
  State<MetroSoundApp> createState() => _MetroSoundAppState();
}

class _MetroSoundAppState extends State<MetroSoundApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    setState(() {}); // re-resolve when 'system' mode follows the OS
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Returning to the app after a while counts as a new practice session
    // (Pro debounces to at most one per half hour).
    widget.pro.maybeCountSession();
    // While we were backgrounded another app may have taken over the audio
    // session (e.g. the user played music elsewhere), leaving our shared
    // playback session deactivated. just_audio recovers on its own, but the
    // metronome's click engine (audioplayers) doesn't — the clicks keep firing
    // silently. Only re-assert when the metronome is actually running, so we
    // never stomp on a record session left by the tuner/recorder. A short delay
    // lets the session finish settling after the interruption ends.
    if (widget.metronome.running) {
      Future.delayed(
        const Duration(milliseconds: 200),
        widget.metronome.restorePlaybackSession,
      );
    }
  }

  Brightness _resolve(String mode) => switch (mode) {
    'light' => Brightness.light,
    'dark' => Brightness.dark,
    _ => WidgetsBinding.instance.platformDispatcher.platformBrightness,
  };

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.library),
        ChangeNotifierProvider.value(value: widget.metronome),
        ChangeNotifierProvider.value(value: widget.drive),
        ChangeNotifierProvider.value(value: widget.icloud),
        ChangeNotifierProvider.value(value: widget.settings),
        ChangeNotifierProvider.value(value: widget.packages),
        ChangeNotifierProvider.value(value: widget.pro),
        ChangeNotifierProvider(create: (_) => AudioController()),
        ChangeNotifierProvider(create: (_) => Tuner()),
      ],
      // Rebuild when the theme preference changes; swap the Studio palette
      // BEFORE the tree builds, and re-key the app so every widget (all of
      // which read Studio.* getters at build time) re-inflates in the new skin.
      child: Builder(
        builder: (context) {
          final mode = context.select<AppSettings, String>((s) => s.themeMode);
          final brightness = _resolve(mode);
          Studio.setBrightness(brightness);
          return KeyedSubtree(
            key: ValueKey(brightness),
            child: MaterialApp(
              title: 'Metro Sound',
              debugShowCheckedModeBanner: false,
              theme: studioTheme(),
              navigatorKey: appNavigatorKey,
              // Keep the screen awake during practice, and float the
              // package-job chip above every route.
              builder: (context, child) => KeepAwake(
                child: Stack(
                  textDirection: TextDirection.ltr,
                  children: [?child, const PackageJobOverlay()],
                ),
              ),
              home: const _Home(),
            ),
          );
        },
      ),
    );
  }
}

/// Gate: first launch shows the onboarding tour; afterwards the tab shell.
/// Reactive, so Settings → Replay tutorial swaps back instantly.
class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    final done = context.select<AppSettings, bool>((s) => s.onboardingDone);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: done ? const RootShell() : const OnboardingScreen(),
    );
  }
}
