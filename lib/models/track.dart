import 'package:path/path.dart' as p;

/// A single practice track: its audio file plus a saved metronome preset
/// and (later) attached practice photos.
class Track {
  final String id;
  String bookId; // which book/folder this track belongs to
  String title;
  int order;
  String audioPath; // absolute path inside the app's storage (rewritten on Drive load)

  // Per-track metronome preset
  int bpm;
  int beatsPerBar;
  bool metronomeOn;
  int syncOffsetMs; // manual metronome-vs-music alignment
  double speed; // playback speed multiplier for music + metronome (1.0 = normal)

  // Whether the learner has marked this lesson as done.
  bool done;

  // Practice photos (absolute paths inside app storage)
  List<String> photoPaths;

  Track({
    required this.id,
    this.bookId = '',
    required this.title,
    required this.order,
    required this.audioPath,
    this.bpm = 80,
    this.beatsPerBar = 4,
    this.metronomeOn = false,
    this.syncOffsetMs = 0,
    this.speed = 1.0,
    this.done = false,
    List<String>? photoPaths,
  }) : photoPaths = photoPaths ?? [];

  /// Build a sensible default title/order from a filename like
  /// "01-Tar_01.mp3" -> order 1, title "Tar 01".
  static (int order, String title) parseFileName(String filePath) {
    final base = p.basenameWithoutExtension(filePath); // "01-Tar_01"
    int order = 0;
    String title = base;
    final leading = RegExp(r'^\s*(\d+)\s*[-_.\)]\s*(.*)$').firstMatch(base);
    if (leading != null) {
      order = int.tryParse(leading.group(1)!) ?? 0;
      title = leading.group(2)!.trim();
    }
    // Prettify "Tar_01" -> "Tar 01"
    title = title.replaceAll('_', ' ').trim();
    if (title.isEmpty) title = base;
    return (order, title);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'bookId': bookId,
        'title': title,
        'order': order,
        'audioPath': audioPath,
        'bpm': bpm,
        'beatsPerBar': beatsPerBar,
        'metronomeOn': metronomeOn,
        'syncOffsetMs': syncOffsetMs,
        'speed': speed,
        'done': done,
        'photoPaths': photoPaths,
      };

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        id: j['id'] as String,
        bookId: j['bookId'] as String? ?? '',
        title: j['title'] as String,
        order: (j['order'] as num?)?.toInt() ?? 0,
        audioPath: j['audioPath'] as String,
        bpm: (j['bpm'] as num?)?.toInt() ?? 80,
        beatsPerBar: (j['beatsPerBar'] as num?)?.toInt() ?? 4,
        metronomeOn: j['metronomeOn'] as bool? ?? false,
        syncOffsetMs: (j['syncOffsetMs'] as num?)?.toInt() ?? 0,
        speed: (j['speed'] as num?)?.toDouble() ?? 1.0,
        done: j['done'] as bool? ?? false,
        photoPaths:
            (j['photoPaths'] as List?)?.map((e) => e as String).toList() ?? [],
      );
}
