import "dart:convert";
import "package:flutter/foundation.dart";
import "package:flutter/services.dart";
import "package:dio/dio.dart";
import "package:geolocator/geolocator.dart";

import "../models/track.dart";
import "../services/audio_service.dart";

enum PlaylistStatus { idle, loading, ready, error }

class PlaylistProvider extends ChangeNotifier {
  final AudioService _audio = AudioService();
  List<Track> tracks = [];
  PlaylistStatus status = PlaylistStatus.idle;
  String? error;

  // Campus Livramento (IFSul) — Easter Egg radius
  static const _campusLat = -30.900700;
  static const _campusLon = -55.532710;
  static const _campusRadiusMeters = 50.0;

  Future<void> loadPlaylist() async {
    try {
      status = PlaylistStatus.loading;
      notifyListeners();

      const jsonUrl = "https://www.rafaelamorim.com.br/mobile2/musicas/list.json";
      List<Map<String, dynamic>> list;

      try {
        final res = await Dio().get(
          jsonUrl,
          options: Options(responseType: ResponseType.plain, sendTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 8)),
        );

        final data = res.data;
        // Sometimes the server returns HTML; fallback to local in that case
        if (data is String && data.trimLeft().startsWith("<")) {
          final bd = await rootBundle.load("assets/musicas_safe.json");
          final localData = utf8.decode(bd.buffer.asUint8List(), allowMalformed: true);
          list = (jsonDecode(localData) as List).cast<Map<String, dynamic>>();
        } else {
          list = (jsonDecode(data) as List).cast<Map<String, dynamic>>();
        }
      } catch (_) {
        // Network or decode failure -> use local fallback
        final bd = await rootBundle.load("assets/musicas_safe.json");
        final localData = utf8.decode(bd.buffer.asUint8List(), allowMalformed: true);
        list = (jsonDecode(localData) as List).cast<Map<String, dynamic>>();
      }

      tracks = list.map((e) => Track.fromJson(e)).toList();

      // ---- Easter Egg -------------------------------------------------------
      if (await _isNearCampus()) {
        tracks.add(
          Track(
            id: "osbilias-5",
            title: "Nome da Faixa (Faixa 5)",
            author: "Os Bilias",
            // NOTE: server path has a space before .mp3 -> keep it URL-encoded
            url: Uri.parse("https://www.rafaelamorim.com.br/mobile2/musicas/osbilias-nome-da-faixa-faixa-5.%20mp3"),
            duration: const Duration(minutes: 3, seconds: 14),
          ),
        );
      }
      // ----------------------------------------------------------------------

      await _audio.setPlaylist(tracks);
      status = PlaylistStatus.ready;
      notifyListeners();
    } catch (e) {
      error = e.toString();
      status = PlaylistStatus.error;
      notifyListeners();
    }
  }

  Future<bool> _isNearCampus() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever || perm == LocationPermission.denied) return false;

      final pos = await Geolocator.getCurrentPosition();
      final dist = Geolocator.distanceBetween(pos.latitude, pos.longitude, _campusLat, _campusLon);
      return dist <= _campusRadiusMeters;
    } catch (_) {
      return false; // fail-safe: no GPS, no Easter Egg
    }
  }

  // Controls
  Future<void> play(int index) async => _audio.seekToIndex(index).then((_) => _audio.play());
  Future<void> pause() async => _audio.pause();
  Future<void> stop() async => _audio.stop();
}
