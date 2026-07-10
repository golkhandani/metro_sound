import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config/features.dart';
import 'services/audio_controller.dart';
import 'services/drive_sync.dart';
import 'services/library_store.dart';
import 'services/metronome.dart';
import 'services/package_service.dart';
import 'services/settings.dart';
import 'services/tuner.dart';
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

  runApp(MetroSoundApp(
    library: library,
    metronome: metronome,
    drive: drive,
    settings: settings,
    packages: packages,
  ));
}

class MetroSoundApp extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: library),
        ChangeNotifierProvider.value(value: metronome),
        ChangeNotifierProvider.value(value: drive),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: packages),
        ChangeNotifierProvider(create: (_) => AudioController()),
        ChangeNotifierProvider(create: (_) => Tuner()),
      ],
      child: MaterialApp(
        title: 'Metro Sound',
        debugShowCheckedModeBanner: false,
        theme: studioTheme(),
        themeMode: ThemeMode.dark,
        navigatorKey: appNavigatorKey,
        // Float the package-job chip above every route.
        builder: (context, child) => Stack(
          textDirection: TextDirection.ltr,
          children: [
            ?child,
            const PackageJobOverlay(),
          ],
        ),
        home: const RootShell(),
      ),
    );
  }
}
