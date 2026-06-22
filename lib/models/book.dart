/// A book is a folder of practice tracks (e.g. "Ketab-e Aval — Tār").
class Book {
  final String id;
  String title;
  int order;
  String? coverPath; // optional cover image inside app storage

  /// Epoch-ms of the last local edit — used by two-way Drive sync to merge
  /// changes with last-write-wins per entity.
  int updatedAt;

  Book({
    required this.id,
    required this.title,
    this.order = 0,
    this.coverPath,
    this.updatedAt = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'order': order,
        'coverPath': coverPath,
        'updatedAt': updatedAt,
      };

  factory Book.fromJson(Map<String, dynamic> j) => Book(
        id: j['id'] as String,
        title: j['title'] as String,
        order: (j['order'] as num?)?.toInt() ?? 0,
        coverPath: j['coverPath'] as String?,
        updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
      );
}
