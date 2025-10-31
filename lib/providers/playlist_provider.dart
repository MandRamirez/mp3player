import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:audio_service/audio_service.dart' show MediaItem;
import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/services.dart' show rootBundle;

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

  int? currentIndex;
  Duration position = Duration.zero;
  Duration bufferedPosition = Duration.zero;
  Duration? duration;

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _bufSub;
  StreamSubscription<ProcessingState>? _procSub;
  StreamSubscription<SequenceState?>? _seqSub;

  bool _sessionReady = false;

  static const _campusLat = -30.900700;
  static const _campusLon = -55.539900; // ajuste se necessário
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
      _sessionReady = true;
    } catch (_) {
      _sessionReady = true;
    }
  }

  void _wirePlayerStreams() {
    _posSub = _player.positionStream.listen((d) { position = d; notifyListeners(); });
    _bufSub = _player.bufferedPositionStream.listen((d) { bufferedPosition = d; notifyListeners(); });
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
      // 1) Baixa como BYTES e decodifica com tolerância a UTF inválido
      final res = await Dio().get<List<int>>(
        _listJson,
        options: Options(
          responseType: ResponseType.bytes,
          sendTimeout: const Duration(milliseconds: 8000),
          receiveTimeout: const Duration(milliseconds: 8000),
        ),
      );

      final body = utf8.decode(res.data!, allowMalformed: true);
      final raw = jsonDecode(body) as List;

      final List<Track> fetched = raw.map<Track>((m) {
        final title = (m['title'] ?? m['titulo'] ?? '').toString();
        final author = (m['author'] ?? m['artista'] ?? '').toString();
        final urlStr = (m['url'] ?? '').toString().trim();
        return Track(
          id: urlStr,                // Track.id é String
          title: title,
          author: author,
          url: Uri.parse(urlStr),    // Track.url é Uri
        );
      }).toList(growable: true);

      // 2) Easter egg (≤ 50m do campus)
      try {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm != LocationPermission.denied &&
            perm != LocationPermission.deniedForever) {
          final pos = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.best);
          final dist = Geolocator.distanceBetween(
              pos.latitude, pos.longitude, _campusLat, _campusLon);
          if (dist <= 50) {
            final eggUrl =
                'https://www.rafaelamorim.com.br/mobile2/musicas/osbilias-nome-da-faixa-faixa-5%20.mp3'; // espaço antes de .mp3
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
      } catch (_) {/* ignora localização */}

      tracks = fetched;
      status = PlaylistStatus.ready;
    } catch (e) {
      // 3) Fallback para asset local se a rede falhar
      try {
        final local = await rootBundle.loadString('assets/musicas_safe.json');
        final raw = jsonDecode(local) as List;
        tracks = raw.map<Track>((m) {
          final title = (m['title'] ?? '').toString();
          final author = (m['author'] ?? '').toString();
          final urlStr = (m['url'] ?? '').toString();
          return Track(
            id: urlStr,
            title: title,
            author: author,
            url: Uri.parse(urlStr),
          );
        }).toList(growable: false);
        status = PlaylistStatus.ready;
      } catch (_) {
        error = 'Falha ao carregar playlist: $e';
        status = PlaylistStatus.error;
      }
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
      final sources = tracks.map((t) {
        final media = MediaItem(
          id: t.url.toString(), // MediaItem.id é String
          title: t.title,
          artist: t.author,
        );
        return AudioSource.uri(t.url, tag: media); // precisa Uri
      }).toList(growable: false);

      final playlist = ConcatenatingAudioSource(children: sources);

      await _player.setAudioSource(
        playlist,
        initialIndex: index,
        preload: true,
      );
      await _applyModes();
      await _player.play();
    } catch (e) {
      error = "Falha ao iniciar reprodução: $e";
      notifyListeners();
    }
  }

  Future<void> pause() async { await _player.pause(); notifyListeners(); }
  Future<void> stop() async { await _player.stop(); notifyListeners(); }

  Future<void> toggleShuffle() async {
    shuffleEnabled = !shuffleEnabled;
    await _player.setShuffleModeEnabled(shuffleEnabled);
    notifyListeners();
  }

  Future<void> setRepeatMode(RepeatMode m) async {
    repeatMode = m;
    switch (m) {
      case RepeatMode.off: await _player.setLoopMode(LoopMode.off); break;
      case RepeatMode.one: await _player.setLoopMode(LoopMode.one); break;
      case RepeatMode.all: await _player.setLoopMode(LoopMode.all); break;
    }
    notifyListeners();
  }

  Future<void> _applyModes() async {
    await _player.setShuffleModeEnabled(shuffleEnabled);
    switch (repeatMode) {
      case RepeatMode.off: await _player.setLoopMode(LoopMode.off); break;
      case RepeatMode.one: await _player.setLoopMode(LoopMode.one); break;
      case RepeatMode.all: await _player.setLoopMode(LoopMode.all); break;
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

  ProcessingState get processing => _player.processingState;

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
