class Track {
  final String id;
  final String title;
  final String author;
  final Uri url;
  final Duration? duration;

  const Track({
    required this.id,
    required this.title,
    required this.author,
    required this.url,
    this.duration,
  });

  factory Track.fromJson(Map<String, dynamic> j) {
    return Track(
      id: (j['id'] ?? j['url']).toString(),
      title: (j['title'] ?? 'Sem título').toString(),
      author: (j['author'] ?? 'Desconhecido').toString(),
      url: Uri.parse(j['url'].toString()),
      duration: _parseDuration(j['duration']),
    );
  }

  static Duration? _parseDuration(dynamic v) {
    if (v is String && v.contains(':')) {
      final p = v.split(':');
      return Duration(minutes: int.parse(p[0]), seconds: int.parse(p[1]));
    }
    return null;
  }
}
