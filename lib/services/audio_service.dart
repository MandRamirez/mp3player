import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/track.dart';

class AudioService {
  final AudioPlayer _player = AudioPlayer();
  ConcatenatingAudioSource? _playlist;

  Future<void> setPlaylist(List<Track> tracks) async {
    final sources = tracks.map((t) => AudioSource.uri(
      t.url,
      tag: MediaItem(id: t.id, title: t.title, artist: t.author),
    ));
    _playlist = ConcatenatingAudioSource(children: sources.toList());
    await _player.setAudioSource(_playlist!);
  }

  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();
  Future<void> stop() => _player.stop();
  Future<void> seekToIndex(int i) async => _player.seek(Duration.zero, index: i);

  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  void dispose() => _player.dispose();
}
