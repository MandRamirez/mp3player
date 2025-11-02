import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:audio_session/audio_session.dart';
import 'package:audio_service/audio_service.dart' show MediaItem;
import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';

import '../models/track.dart';

enum PlaylistStatus { idle, loading, ready, error }

enum RepeatMode { off, one, all }

// --- sanitização do JSON remoto ---
String _sanitizeToJsonArray(String raw) {
  var s = raw
      .replaceAll('\uFEFF', '')
      .replaceAll('\r', '')
      .replaceAll(RegExp(r'[\u0000-\u001F]'), ' ')
      .replaceAll('\u00A0', ' ');

  final i0 = s.indexOf('[');
  final i1 = s.lastIndexOf(']');
  if (i0 >= 0 && i1 > i0) s = s.substring(i0 + 1, i1);

  s = s.replaceAll(RegExp(r'}\s*{'), '},{');
  s = s.replaceAll(RegExp(r'[ \t]+'), ' ');
  s = s.replaceAllMapped(
    RegExp(r'"duration"\s*:\s*"\s*([0-9]{1,2})\D+([0-9]{1,2})\s*"'),
    (m) =>
        '"duration":"${m.group(1)!.padLeft(2, '0')}:${m.group(2)!.padLeft(2, '0')}"',
  );

  return '[\n$s\n]';
}

class PlaylistProvider extends ChangeNotifier {
  final ja.AudioPlayer _player = ja.AudioPlayer();

  List<Track> tracks = [];
  PlaylistStatus status = PlaylistStatus.idle;
  String? error;

  bool shuffleEnabled = false;
  RepeatMode repeatMode = RepeatMode.off;

  int? currentIndex;
  Duration position = Duration.zero;
  Duration bufferedPosition = Duration.zero;
  Duration? duration;

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _bufSub;
  StreamSubscription<ja.ProcessingState>? _procSub;
  StreamSubscription<ja.SequenceState?>? _seqSub;

  bool _sessionReady = false;

  static const _campusLat = -30.900700;
  static const _campusLon = -55.539900;
  static const _listJson =
      'https://www.rafaelamorim.com.br/mobile2/musicas/list.json';

  PlaylistProvider() {
    _wirePlayerStreams();
    _initAudioSession();
    _loadTracks();
  }

  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      await _player.setVolume(1.0);
      _sessionReady = true;
    } catch (e, st) {
      if (kDebugMode) debugPrint('⚠️ AudioSession init: $e\n$st');
      _sessionReady = true;
    }
  }

  void _wirePlayerStreams() {
    _posSub = _player.positionStream.listen((d) {
      position = d;
      notifyListeners();
    });
    _bufSub = _player.bufferedPositionStream.listen((d) {
      bufferedPosition = d;
      notifyListeners();
    });
    _procSub = _player.processingStateStream.listen((_) => notifyListeners());
    _seqSub = _player.sequenceStateStream.listen((seq) {
      currentIndex = seq?.currentIndex;
      duration = _player.duration;
      notifyListeners();
    });
  }

  Future<void> _loadTracks() async {
    if (status == PlaylistStatus.loading) return;
    status = PlaylistStatus.loading;
    error = null;
    notifyListeners();

    try {
      final res = await Dio().get<List<int>>(
        _listJson,
        options: Options(
          responseType: ResponseType.bytes,
          sendTimeout: const Duration(milliseconds: 8000),
          receiveTimeout: const Duration(milliseconds: 8000),
          headers: const {
            'User-Agent': 'PlaylistMP3App/1.0 (Flutter)',
            'Accept': 'application/json,*/*;q=0.8',
          },
        ),
      );

      String raw;
      try {
        raw = utf8.decode(res.data ?? const []);
      } catch (_) {
        raw = latin1.decode(res.data ?? const []);
      }

      final body = _sanitizeToJsonArray(raw);
      final rawList = jsonDecode(body) as List;

      final fetched = rawList
          .map<Track>((m) {
            final title = (m['title'] ?? '').toString();
            final author = (m['author'] ?? '').toString();
            final urlStr = (m['url'] ?? '').toString().trim();
            return Track(
              id: urlStr,
              title: title,
              author: author,
              url: Uri.parse(urlStr),
            );
          })
          .toList(growable: true);

      // Easter egg (50 m do campus)
      try {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm != LocationPermission.denied &&
            perm != LocationPermission.deniedForever) {
          final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.best,
          );
          final dist = Geolocator.distanceBetween(
            pos.latitude,
            pos.longitude,
            _campusLat,
            _campusLon,
          );
          if (dist <= 50) {
            const eggUrl =
                'https://www.rafaelamorim.com.br/mobile2/musicas/osbilias-nome-da-faixa-faixa-5%20.mp3';
            fetched.add(
              Track(
                id: eggUrl,
                title: 'Os Bilias (Easter Egg)',
                author: 'Os Bilias',
                url: Uri.parse(eggUrl),
              ),
            );
          }
        }
      } catch (_) {}

      tracks = fetched;
      status = PlaylistStatus.ready;
    } catch (e) {
      error = 'Falha ao carregar playlist: $e';
      status = PlaylistStatus.error;
    } finally {
      notifyListeners();
    }
  }

  Future<void> setPlaylist(List<Track> list) async {
    tracks = List<Track>.from(list);
    notifyListeners();
  }

  Future<void> play(int index) async {
    if (!_sessionReady) await _initAudioSession();
    try {
      final sources = tracks
          .map((t) {
            final media = MediaItem(
              id: t.url.toString(),
              title: t.title,
              artist: t.author,
            );
            return ja.AudioSource.uri(t.url, tag: media);
          })
          .toList(growable: false);

      final playlist = ja.ConcatenatingAudioSource(children: sources);

      await _player.setAudioSource(
        playlist,
        initialIndex: index,
        preload: true,
      );
      await _applyModes();
      await _player.play();
    } on SocketException catch (e) {
      error = 'Sem conexão: $e';
      notifyListeners();
    } catch (e) {
      error = 'Falha ao iniciar reprodução: $e';
      notifyListeners();
    }
  }

  Future<void> pause() async {
    await _player.pause();
    notifyListeners();
  }

  Future<void> stop() async {
    await _player.stop();
    notifyListeners();
  }

  Future<void> toggleShuffle() async {
    shuffleEnabled = !shuffleEnabled;
    await _player.setShuffleModeEnabled(shuffleEnabled);
    notifyListeners();
  }

  Future<void> setRepeatMode(RepeatMode m) async {
    repeatMode = m;
    switch (m) {
      case RepeatMode.off:
        await _player.setLoopMode(ja.LoopMode.off);
        break;
      case RepeatMode.one:
        await _player.setLoopMode(ja.LoopMode.one);
        break;
      case RepeatMode.all:
        await _player.setLoopMode(ja.LoopMode.all);
        break;
    }
    notifyListeners();
  }

  Future<void> _applyModes() async {
    await _player.setShuffleModeEnabled(shuffleEnabled);
    switch (repeatMode) {
      case RepeatMode.off:
        await _player.setLoopMode(ja.LoopMode.off);
        break;
      case RepeatMode.one:
        await _player.setLoopMode(ja.LoopMode.one);
        break;
      case RepeatMode.all:
        await _player.setLoopMode(ja.LoopMode.all);
        break;
    }
  }

  double get bufferPercent {
    final d = duration;
    if (d == null || d.inMilliseconds == 0) return 0;
    final bp = bufferedPosition.inMilliseconds.clamp(0, d.inMilliseconds);
    return bp / d.inMilliseconds;
  }

  double get positionPercent {
    final d = duration;
    if (d == null || d.inMilliseconds == 0) return 0;
    final p = position.inMilliseconds.clamp(0, d.inMilliseconds);
    return p / d.inMilliseconds;
  }

  ja.ProcessingState get processing => _player.processingState;

  @override
  void dispose() {
    _posSub?.cancel();
    _bufSub?.cancel();
    _procSub?.cancel();
    _seqSub?.cancel();
    _player.dispose();
    super.dispose();
  }
}
