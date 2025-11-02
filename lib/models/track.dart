import 'dart:convert';

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
    // garante String e remove caracteres quebrados de encoding
    String _s(dynamic v, {String fallback = ''}) {
      final s = (v ?? fallback).toString().trim();
      // tenta “consertar” possíveis bytes Latin1 exibidos como UTF-8
      try {
        final bytes = latin1.encode(s);
        final fixed = utf8.decode(bytes, allowMalformed: true);
        return fixed.trim().isEmpty ? s : fixed.trim();
      } catch (_) {
        return s;
      }
    }

    final urlStr = _s(j['url']);
    return Track(
      id: _s(j['id'], fallback: urlStr),
      title: _s(j['title'], fallback: 'Sem título'),
      author: _s(j['author'], fallback: 'Desconhecido'),
      url: Uri.parse(urlStr),
      duration: _parseDuration(j['duration']),
    );
  }

  static Duration? _parseDuration(dynamic v) {
    // aceita formatos “MM:SS” com espaços/ruído no meio (ex.: "03:1 0")
    final s = (v ?? '').toString();
    final m = RegExp(r'(\d{1,2})\s*:\s*(\d{1,2})').firstMatch(s);
    if (m == null) return null;
    final mm = int.tryParse(m.group(1)!) ?? 0;
    final ss = int.tryParse(m.group(2)!) ?? 0;
    return Duration(minutes: mm, seconds: ss);
  }
}
