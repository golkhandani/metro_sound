/// A book is a folder of practice tracks (e.g. "Ketab-e Aval — Tār").
class Book {
  final String id;
  String title;
  int order;
  String? coverPath; // optional cover image inside app storage

  /// A linked Google Drive folder this book imports audio from (via the Picker,
  /// which grants drive.file access to that folder). Null when not linked.
  String? driveFolderId;
  String? driveFolderName;

  /// The id this book had in the library where it was first created. Travels
  /// inside shared packages so re-imports can be recognised ("append to the
  /// book you already have?") instead of always duplicating.
  String? originId;

  /// The stable share identity: the original id if this book was imported,
  /// else its own id.
  String get shareId => originId ?? id;

  /// Epoch-ms of the last local edit — used by two-way Drive sync to merge
  /// changes with last-write-wins per entity.
  int updatedAt;

  Book({
    required this.id,
    required this.title,
    this.order = 0,
    this.coverPath,
    this.driveFolderId,
    this.driveFolderName,
    this.originId,
    this.updatedAt = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'order': order,
        'coverPath': coverPath,
        'driveFolderId': driveFolderId,
        'driveFolderName': driveFolderName,
        'originId': originId,
        'updatedAt': updatedAt,
      };

  factory Book.fromJson(Map<String, dynamic> j) => Book(
        id: j['id'] as String,
        title: j['title'] as String,
        order: (j['order'] as num?)?.toInt() ?? 0,
        coverPath: j['coverPath'] as String?,
        driveFolderId: j['driveFolderId'] as String?,
        driveFolderName: j['driveFolderName'] as String?,
        originId: j['originId'] as String?,
        updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
      );
}
