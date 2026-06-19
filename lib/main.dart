import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/audio_controller.dart';
import 'services/drive_sync.dart';
import 'services/library_store.dart';
import 'services/metronome.dart';
import 'screens/books_screen.dart';
import 'ui/studio.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final library = LibraryStore();
  final metronome = Metronome();
  final drive = DriveSyncService();
  await Future.wait([library.init(), metronome.init(), drive.init()]);

  runApp(MetroSoundApp(
    library: library,
    metronome: metronome,
    drive: drive,
  ));
}

class MetroSoundApp extends StatelessWidget {
  final LibraryStore library;
  final Metronome metronome;
  final DriveSyncService drive;
  const MetroSoundApp({
    super.key,
    required this.library,
    required this.metronome,
    required this.drive,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: library),
        ChangeNotifierProvider.value(value: metronome),
        ChangeNotifierProvider.value(value: drive),
        ChangeNotifierProvider(create: (_) => AudioController()),
      ],
      child: MaterialApp(
        title: 'Metro Sound',
        debugShowCheckedModeBanner: false,
        theme: studioTheme(),
        themeMode: ThemeMode.dark,
        home: const BooksScreen(),
      ),
    );
  }
}
