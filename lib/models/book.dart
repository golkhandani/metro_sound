/// A book is a folder of practice tracks (e.g. "Ketab-e Aval — Tār").
class Book {
  final String id;
  String title;
  int order;
  String? coverPath; // optional cover image inside app storage

  Book({
    required this.id,
    required this.title,
    this.order = 0,
    this.coverPath,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'order': order,
        'coverPath': coverPath,
      };

  factory Book.fromJson(Map<String, dynamic> j) => Book(
        id: j['id'] as String,
        title: j['title'] as String,
        order: (j['order'] as num?)?.toInt() ?? 0,
        coverPath: j['coverPath'] as String?,
      );
}
