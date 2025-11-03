import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart' as ja;
import '../providers/playlist_provider.dart';

class PlayerControls extends StatelessWidget {
  const PlayerControls({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlaylistProvider>();
    final hasTrack = provider.currentIndex != null;
    final isPlaying = provider.isPlaying; // Use the provider's isPlaying getter

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
            // Progress bar
            if (hasTrack && provider.duration != null)
              Column(
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
                      value: provider.positionPercent,
                      onChanged: (value) {
                        // Seek to position
                        final newPosition = provider.duration! * value;
                        provider.seek(newPosition);
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(provider.position),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          _formatDuration(provider.duration!),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            
            // Now playing info
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
            
            // Control buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Shuffle button
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
                
                // Previous button
                IconButton(
                  icon: const Icon(Icons.skip_previous),
                  iconSize: 32,
                  onPressed: hasTrack ? provider.seekToPrevious : null,
                ),
                const SizedBox(width: 8),
                
                // Play/Pause button
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  child: IconButton(
                    icon: Icon(
                      isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                    iconSize: 36,
                    onPressed: () {
                      if (hasTrack) {
                        if (isPlaying) {
                          provider.pause();
                        } else {
                          provider.resume();
                        }
                      } else if (provider.tracks.isNotEmpty) {
                        provider.play(0);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                
                // Next button
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  iconSize: 32,
                  onPressed: hasTrack ? provider.seekToNext : null,
                ),
                const SizedBox(width: 8),
                
                // Repeat button
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
                
                // Stop button
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