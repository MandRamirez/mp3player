import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart' as ja;
import '../providers/playlist_provider.dart';

class PlayerControls extends StatelessWidget {
  const PlayerControls({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlaylistProvider>();
    final player = provider.getPlayer(); // Get audio player reference
    final hasTrack = provider.currentIndex != null;
    final isPlaying = provider.isPlaying;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // --- Progress bar ---
            if (hasTrack)
              StreamBuilder<Duration>(
                stream: player.positionStream,
                builder: (context, positionSnapshot) {
                  final position = positionSnapshot.data ?? Duration.zero;

                  return StreamBuilder<Duration?>(
                    stream: player.durationStream,
                    builder: (context, durationSnapshot) {
                      final duration = durationSnapshot.data ?? Duration.zero;
                      final value = duration.inMilliseconds == 0
                          ? 0.0
                          : (position.inMilliseconds / duration.inMilliseconds)
                              .clamp(0.0, 1.0);

                      return Column(
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 2,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 14,
                              ),
                            ),
                            child: Slider(
                              value: value,
                              onChanged: (v) {
                                if (duration.inMilliseconds > 0) {
                                  final newPosition =
                                      Duration(milliseconds: (duration.inMilliseconds * v).toInt());
                                  provider.seek(newPosition);
                                }
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _formatDuration(position),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                Text(
                                  _formatDuration(duration),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      );
                    },
                  );
                },
              ),

            // --- Now playing info ---
            if (hasTrack && provider.currentIndex! < provider.tracks.length)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    Text(
                      provider.tracks[provider.currentIndex!].title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      provider.tracks[provider.currentIndex!].author,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

            // --- Control buttons ---
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Shuffle
                IconButton(
                  icon: Icon(
                    Icons.shuffle,
                    color: provider.shuffleEnabled
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  iconSize: 28,
                  onPressed: provider.toggleShuffle,
                  tooltip: 'Shuffle',
                ),
                const SizedBox(width: 8),

                // Previous
                IconButton(
                  icon: const Icon(Icons.skip_previous),
                  iconSize: 32,
                  onPressed: hasTrack ? provider.seekToPrevious : null,
                ),
                const SizedBox(width: 8),

                // Play / Pause
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  child: StreamBuilder<ja.PlayerState>(
                    stream: player.playerStateStream,
                    builder: (context, snapshot) {
                      final playerState = snapshot.data;
                      final playing = playerState?.playing ?? isPlaying;

                      return IconButton(
                        icon: Icon(
                          playing ? Icons.pause : Icons.play_arrow,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                        iconSize: 36,
                        onPressed: () {
                          if (hasTrack) {
                            if (playing) {
                              provider.pause();
                            } else {
                              provider.resume();
                            }
                          } else if (provider.tracks.isNotEmpty) {
                            provider.play(0);
                          }
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),

                // Next
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  iconSize: 32,
                  onPressed: hasTrack ? provider.seekToNext : null,
                ),
                const SizedBox(width: 8),

                // Repeat
                IconButton(
                  icon: Icon(
                    provider.repeatMode == RepeatMode.off
                        ? Icons.repeat
                        : provider.repeatMode == RepeatMode.one
                            ? Icons.repeat_one
                            : Icons.repeat,
                    color: provider.repeatMode != RepeatMode.off
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  iconSize: 28,
                  onPressed: () {
                    final nextMode = switch (provider.repeatMode) {
                      RepeatMode.off => RepeatMode.all,
                      RepeatMode.all => RepeatMode.one,
                      RepeatMode.one => RepeatMode.off,
                    };
                    provider.setRepeatMode(nextMode);
                  },
                  tooltip: 'Repeat',
                ),
                const SizedBox(width: 8),

                // Stop
                IconButton(
                  icon: const Icon(Icons.stop),
                  iconSize: 28,
                  onPressed: hasTrack ? provider.stop : null,
                  tooltip: 'Stop',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}
