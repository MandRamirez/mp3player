import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:audio_session/audio_session.dart';
import 'package:audio_service/audio_service.dart' show MediaItem;
import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:workmanager/workmanager.dart';

import '../models/track.dart';
import '../services/download_worker.dart';
import '../l10n/app_strings.dart';

enum PlaylistStatus { idle, loading, ready, error }

enum RepeatMode { off, one, all }

// Normaliza o conteúdo remoto para um array JSON válido
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
  List<Track> _originalTracks = [];
  PlaylistStatus status = PlaylistStatus.idle;
  String? error;

  bool shuffleEnabled = false;
  RepeatMode repeatMode = RepeatMode.off;
  List<int>? shuffledIndices;

  int? currentIndex;
  Duration position = Duration.zero;
  Duration bufferedPosition = Duration.zero;
  Duration? duration;

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _bufSub;
  StreamSubscription<ja.ProcessingState>? _procSub;
  StreamSubscription<ja.SequenceState?>? _seqSub;
  StreamSubscription<ja.PlayerState>? _playerStateSub;

  bool _sessionReady = false;

  static const _campusLat = -30.900844;
  static const _campusLon = -55.532903;
  static const _listJson =
      'https://www.rafaelamorim.com.br/mobile2/musicas/list.json';

  // Poll de localização para acionar o Easter Egg
  Timer? _positionCheckTimer;
  static const _checkInterval = Duration(seconds: 30);

  // Estado de download por faixa (sincronizado com Hive)
  final Map<String, double> _downloadProgress = {}; // 0..1
  final Map<String, bool> _downloadDone = {};
  final Map<String, bool> _downloadError = {};

  Timer? _downloadPollTimer;
  static const _downloadPollInterval = Duration(seconds: 1);

  PlaylistProvider() {
    _wirePlayerStreams();
    _initAudioSession();
    _loadTracks();
    _startPositionCheckTimer();
    _startDownloadPollTimer();
  }

  // ---------------------------------------------------------------------------
  // TIMERS
  // ---------------------------------------------------------------------------

  void _startPositionCheckTimer() {
    _positionCheckTimer?.cancel();
    _positionCheckTimer = Timer.periodic(_checkInterval, (_) async {
      await _checkPositionAndReload();
    });
  }

  void _startDownloadPollTimer() {
    _downloadPollTimer?.cancel();
    _downloadPollTimer = Timer.periodic(_downloadPollInterval, (_) async {
      await _refreshDownloadStates();
    });
  }

  Future<void> _checkPositionAndReload() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }

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
        final hasEasterEgg = tracks.any((t) => t.title.contains('Easter Egg'));
        if (!hasEasterEgg && status != PlaylistStatus.loading) {
          if (kDebugMode) {
            debugPrint('Dentro da área do campus, recarregando playlist.');
          }
          await reloadTracks();
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Position check error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // ÁUDIO / SESSÃO
  // ---------------------------------------------------------------------------

  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      await _player.setVolume(1.0);
      _sessionReady = true;
    } catch (e, st) {
      if (kDebugMode) debugPrint('AudioSession init error: $e\n$st');
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
    _procSub = _player.processingStateStream.listen((state) {
      if (state == ja.ProcessingState.completed) {
        if (repeatMode == RepeatMode.one) {
          _player.seek(Duration.zero);
          _player.play();
        } else if (repeatMode == RepeatMode.all || _player.hasNext) {
          seekToNext();
        }
      }
      notifyListeners();
    });
    _seqSub = _player.sequenceStateStream.listen((seq) {
      currentIndex = seq?.currentIndex;
      duration = _player.duration;
      notifyListeners();
    });
    _playerStateSub = _player.playerStateStream.listen((_) {
      notifyListeners();
    });
  }

  // ---------------------------------------------------------------------------
  // CARREGAMENTO DE PLAYLIST / EASTER EGG / DOWNLOADS
  // ---------------------------------------------------------------------------

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

      // Easter egg a 50m do campus
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
                'https://www.rafaelamorim.com.br/mobile2/musicas/osbilias-nome-da-faixa-faixa-5.mp3';
            fetched.add(
              Track(
                id: eggUrl,
                title: 'Os Bilias (Easter Egg)',
                author: 'Os Bilias',
                url: Uri.parse(eggUrl),
              ),
            );
            if (kDebugMode) debugPrint('Easter egg adicionado à playlist.');
          }
        }
      } catch (_) {}

      tracks = fetched;
      _originalTracks = List<Track>.from(fetched);
      status = PlaylistStatus.ready;

      await _ensureDownloadsScheduled();

      if (shuffleEnabled) {
        _shuffleTracks();
      }
    } catch (e) {
      error = '${AppStrings.errorPlaylistLoad}: $e';
      status = PlaylistStatus.error;
    } finally {
      notifyListeners();
    }
  }

  Future<void> _ensureDownloadsScheduled() async {
    if (tracks.isEmpty) return;
    try {
      final box = await Hive.openBox('downloads');

      for (final t in tracks) {
        final id = t.id;
        final done =
            (box.get('${id}_done', defaultValue: false) as bool?) ?? false;

        if (done) {
          _downloadDone[id] = true;
          _downloadProgress[id] = 1.0;
          continue;
        }

        box.put('${id}_error', false);
        _downloadError[id] = false;
        _downloadProgress[id] = 0.0;

        final uniqueName = 'download_${id.hashCode}';

        await Workmanager().registerOneOffTask(
          uniqueName,
          taskDownload,
          inputData: {
            'url': t.url.toString(),
            'id': id,
          },
          constraints: Constraints(
            networkType: NetworkType.connected,
          ),
        );
      }

      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Erro ao agendar downloads: $e');
      }
    }
  }

  Future<void> _refreshDownloadStates() async {
    if (tracks.isEmpty) return;
    try {
      final box = await Hive.openBox('downloads');
      bool changed = false;

      for (final t in tracks) {
        final id = t.id;

        final done =
            (box.get('${id}_done', defaultValue: false) as bool?) ?? false;
        final progressBytes = box.get('${id}_progress') as int?;
        final totalBytes = box.get('${id}_total') as int?;
        final errorFlag =
            (box.get('${id}_error', defaultValue: false) as bool?) ?? false;

        double percent = 0.0;
        if (totalBytes != null && totalBytes > 0 && progressBytes != null) {
          percent = (progressBytes / totalBytes).clamp(0.0, 1.0);
        }

        if (_downloadDone[id] != done) {
          _downloadDone[id] = done;
          changed = true;
        }
        if (_downloadError[id] != errorFlag) {
          _downloadError[id] = errorFlag;
          changed = true;
        }
        if (_downloadProgress[id] != percent) {
          _downloadProgress[id] = percent;
          changed = true;
        }
      }

      if (changed) {
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Erro ao atualizar estado de downloads: $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // SHUFFLE / REPEAT
  // ---------------------------------------------------------------------------

  void _generateShuffleIndices() {
    final indices = List.generate(tracks.length, (i) => i);
    final random = Random();

    for (var i = indices.length - 1; i > 0; i--) {
      final j = random.nextInt(i + 1);
      final temp = indices[i];
      indices[i] = indices[j];
      indices[j] = temp;
    }

    shuffledIndices = indices;
  }

  Future<void> setPlaylist(List<Track> list) async {
    tracks = List<Track>.from(list);
    if (shuffleEnabled) {
      _generateShuffleIndices();
    }
    notifyListeners();
  }

  Future<void> toggleShuffle() async {
    shuffleEnabled = !shuffleEnabled;

    if (shuffleEnabled) {
      _originalTracks = List<Track>.from(tracks);
      _shuffleTracks();
    } else {
      tracks = List<Track>.from(_originalTracks);
    }

    await _player.setShuffleModeEnabled(false);
    notifyListeners();
  }

  void _shuffleTracks() {
    final random = Random();
    for (var i = tracks.length - 1; i > 0; i--) {
      final j = random.nextInt(i + 1);
      final temp = tracks[i];
      tracks[i] = tracks[j];
      tracks[j] = temp;
    }
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

  // ---------------------------------------------------------------------------
  // CONTROLE DE REPRODUÇÃO
  // ---------------------------------------------------------------------------

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
      error = '${AppStrings.errorNetwork}: $e';
      notifyListeners();
    } catch (e) {
      error = '${AppStrings.errorPlaybackStart}: $e';
      notifyListeners();
    }
  }

  Future<void> pause() async {
    await _player.pause();
    notifyListeners();
  }

  Future<void> resume() async {
    await _player.play();
    notifyListeners();
  }

  Future<void> stop() async {
    await _player.stop();
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
    notifyListeners();
  }

  Future<void> seekToNext() async {
    if (_player.hasNext) {
      await _player.seekToNext();
    }
  }

  Future<void> seekToPrevious() async {
    if (_player.hasPrevious) {
      await _player.seekToPrevious();
    }
  }

  // ---------------------------------------------------------------------------
  // GETTERS / ESTADO EXPOSTO
  // ---------------------------------------------------------------------------

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

  double downloadProgressFor(String trackId) =>
      _downloadProgress[trackId] ?? 0.0;

  bool isDownloaded(String trackId) => _downloadDone[trackId] ?? false;

  bool hasDownloadError(String trackId) =>
      _downloadError[trackId] ?? false;

  ja.ProcessingState get processing => _player.processingState;
  bool get isPlaying => _player.playing;

  // ---------------------------------------------------------------------------
  // CICLO DE VIDA
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _positionCheckTimer?.cancel();
    _downloadPollTimer?.cancel();
    _posSub?.cancel();
    _bufSub?.cancel();
    _procSub?.cancel();
    _seqSub?.cancel();
    _playerStateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> reloadTracks() async {
    await _loadTracks();
  }
}
