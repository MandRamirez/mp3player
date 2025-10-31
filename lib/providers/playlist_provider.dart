import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../services/download_worker.dart';
import '../models/track.dart';

enum PlaylistStatus { idle, loading, ready, error }
enum RepeatMode { off, one, all }

class PlaylistProvider extends ChangeNotifier {
  final _player = AudioPlayer();

  List<Track> tracks = [];
  PlaylistStatus status = PlaylistStatus.idle;
  String? error;

  bool shuffleEnabled = false;
  RepeatMode repeatMode = RepeatMode.off;

  static const _campusLat = -30.900700;
  static const _campusLon = -55.532710;
  static const _campusRadiusMeters = 50.0;

  PlaylistProvider() {
    _player.playbackEventStream.listen((_) {}, onError: (e, s) {});
    _player.setAudioSource(ConcatenatingAudioSource(children: []));
    loadPlaylist();
  }

  Future<void> _ensureHive() async {
    if (!Hive.isBoxOpen('downloads')) {
      final dir = await getApplicationDocumentsDirectory();
      Hive.init(dir.path);
      await Hive.openBox('downloads');
    }
  }

  Future<void> loadPlaylist() async {
    status = PlaylistStatus.loading;
    notifyListeners();

    try {
      const jsonUrl =
          'https://www.rafaelamorim.com.br/mobile2/musicas/list.json';

      List<Map<String, dynamic>> list;

      try {
        final dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 6),
            receiveTimeout: const Duration(seconds: 6),
            sendTimeout: const Duration(seconds: 6),
          ),
        );

        final res = await dio.get(
          jsonUrl,
          options: Options(responseType: ResponseType.plain),
        );

        final data = res.data;

        // Alguns servidores devolvem HTML em caso de erro (começando com <).
        if (data is String && data.trimLeft().startsWith('<')) {
          final bd = await rootBundle.load('assets/musicas_safe.json');
          final local =
              utf8.decode(bd.buffer.asUint8List(), allowMalformed: true);
          list = (jsonDecode(local) as List).cast<Map<String, dynamic>>();
        } else {
          list = (jsonDecode(data) as List).cast<Map<String, dynamic>>();
        }
      } catch (_) {
        // Fallback total para o JSON embarcado
        final bd = await rootBundle.load('assets/musicas_safe.json');
        final local =
            utf8.decode(bd.buffer.asUint8List(), allowMalformed: true);
        list = (jsonDecode(local) as List).cast<Map<String, dynamic>>();
      }

      tracks = list.map((e) => Track.fromJson(e)).toList();

      // Easter Egg: a 50m do Campus Livramento, adiciona Os Bilias
      if (await _isNearCampus()) {
        tracks.add(
          Track(
            id: 'osbilias-5',
            title: 'Nome da Faixa (Faixa 5)',
            author: 'Os Bilias',
            // URL possui espaço antes do .mp3 → codificado como %20
            url: Uri.parse(
                'https://www.rafaelamorim.com.br/mobile2/musicas/osbilias-nome-da-faixa-faixa-5.%20mp3'),
            duration: const Duration(minutes: 3, seconds: 14),
          ),
        );
      }

      await _buildAudioSource();

      status = PlaylistStatus.ready;
      notifyListeners();
    } catch (e) {
      error = e.toString();
      status = PlaylistStatus.error;
      notifyListeners();
    }
  }

  Future<void> _buildAudioSource() async {
    final sources = <AudioSource>[];

    for (final t in tracks) {
      sources.add(
        AudioSource.uri(
          t.url,
          tag: MediaItem(
            id: t.id,
            title: t.title,
            artist: t.author,
          ),
        ),
      );
    }

    await _player.setAudioSource(
      ConcatenatingAudioSource(children: sources),
    );
  }

  Future<void> play(int index) async {
    await _player.seek(Duration.zero, index: index);
    await _player.play();
  }

  Future<void> pause() async => _player.pause();
  Future<void> stop() async => _player.stop();

  // Shuffle & repeat
  Future<void> toggleShuffle() async {
    shuffleEnabled = !shuffleEnabled;
    await _player.setShuffleModeEnabled(shuffleEnabled);
    notifyListeners();
  }

  Future<void> setRepeatMode(RepeatMode mode) async {
    repeatMode = mode;
    final loop = switch (mode) {
      RepeatMode.off => LoopMode.off,
      RepeatMode.one => LoopMode.one,
      RepeatMode.all => LoopMode.all,
    };
    await _player.setLoopMode(loop);
    notifyListeners();
  }

  // Registrar download em background (um por faixa)
  Future<void> downloadTrack(Track t) async {
    await _ensureHive();
    await Workmanager().registerOneOffTask(
      'dl_${t.id}',
      taskDownload,
      inputData: {'id': t.id, 'url': t.url.toString()},
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
    );
  }

  // Ler progresso salvo pelo worker
  Future<(int? downloaded, int? total, bool done)> getProgress(Track t) async {
    await _ensureHive();
    final box = Hive.box('downloads');
    final d = box.get('${t.id}_progress') as int?;
    final tot = box.get('${t.id}_total') as int?;
    final done = (box.get('${t.id}_done') as bool?) ?? false;
    return (d, tot, done);
  }

  Future<bool> _isNearCampus() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever ||
          perm == LocationPermission.denied) {
        return false;
      }

      final pos = await Geolocator.getCurrentPosition();
      final dist = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        _campusLat,
        _campusLon,
      );
      return dist <= _campusRadiusMeters;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
