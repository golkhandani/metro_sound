import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config/features.dart';
import 'services/audio_controller.dart';
import 'services/drive_sync.dart';
import 'services/library_store.dart';
import 'services/metronome.dart';
import 'services/package_service.dart';
import 'dev/screenshot_director.dart';
import 'services/sample_library.dart';
import 'services/settings.dart';
import 'services/tuner.dart';
import 'screens/onboarding_screen.dart';
import 'screens/root_shell.dart';
import 'ui/studio.dart';
import 'widgets/package_job_overlay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final library = LibraryStore();
  final metronome = Metronome();
  final drive = DriveSyncService();
  final settings = AppSettings();
  final packages = PackageService();
  await Future.wait([
    library.init(),
    metronome.init(),
    if (driveSyncEnabled) drive.init(),
    settings.init(),
    packages.init(),
  ]);
  // Wire the library into Drive sync so two-way auto-sync can observe edits.
  // (Skipped while the feature is hidden — no Google sign-in work at launch.)
  if (driveSyncEnabled) await drive.attachLibrary(library);
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
      settings: settings,
      packages: packages,
    ),
  );
}

class MetroSoundApp extends StatefulWidget {
  final LibraryStore library;
  final Metronome metronome;
  final DriveSyncService drive;
  final AppSettings settings;
  final PackageService packages;
  const MetroSoundApp({
    super.key,
    required this.library,
    required this.metronome,
    required this.drive,
    required this.settings,
    required this.packages,
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
        ChangeNotifierProvider.value(value: widget.settings),
        ChangeNotifierProvider.value(value: widget.packages),
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
              // Float the package-job chip above every route.
              builder: (context, child) => Stack(
                textDirection: TextDirection.ltr,
                children: [?child, const PackageJobOverlay()],
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
