import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/audio_controller.dart';
import 'services/drive_sync.dart';
import 'services/library_store.dart';
import 'services/metronome.dart';
import 'services/settings.dart';
import 'services/tuner.dart';
import 'screens/root_shell.dart';
import 'ui/studio.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final library = LibraryStore();
  final metronome = Metronome();
  final drive = DriveSyncService();
  final settings = AppSettings();
  await Future.wait(
      [library.init(), metronome.init(), drive.init(), settings.init()]);

  runApp(MetroSoundApp(
    library: library,
    metronome: metronome,
    drive: drive,
    settings: settings,
  ));
}

class MetroSoundApp extends StatelessWidget {
  final LibraryStore library;
  final Metronome metronome;
  final DriveSyncService drive;
  final AppSettings settings;
  const MetroSoundApp({
    super.key,
    required this.library,
    required this.metronome,
    required this.drive,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: library),
        ChangeNotifierProvider.value(value: metronome),
        ChangeNotifierProvider.value(value: drive),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider(create: (_) => AudioController()),
        ChangeNotifierProvider(create: (_) => Tuner()),
      ],
      child: MaterialApp(
        title: 'Metro Sound',
        debugShowCheckedModeBanner: false,
        theme: studioTheme(),
        themeMode: ThemeMode.dark,
        home: const RootShell(),
      ),
    );
  }
}
