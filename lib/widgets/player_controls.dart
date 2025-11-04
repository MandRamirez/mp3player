import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/playlist_provider.dart';
import '../l10n/app_strings.dart';

class PlayerControls extends StatelessWidget {
  const PlayerControls({super.key});

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlaylistProvider>();
    final theme = Theme.of(context);

    final hasTrack = provider.currentIndex != null &&
        provider.currentIndex! < provider.tracks.length;
    final isPlaying = provider.isPlaying;
    final duration = provider.duration ?? Duration.zero;
    final position = provider.position;

    // repeat icon + tooltip
    IconData repeatIcon;
    String repeatTooltip;
    switch (provider.repeatMode) {
      case RepeatMode.off:
        repeatIcon = Icons.repeat;
        repeatTooltip = AppStrings.repeatOffLabel;
        break;
      case RepeatMode.one:
        repeatIcon = Icons.repeat_one;
        repeatTooltip = AppStrings.repeatOneLabel;
        break;
      case RepeatMode.all:
        repeatIcon = Icons.repeat;
        repeatTooltip = AppStrings.repeatAllLabel;
        break;
    }

    final playPauseIcon =
        isPlaying ? Icons.pause : Icons.play_arrow;
    final playPauseTooltip =
        isPlaying ? AppStrings.pauseLabel : AppStrings.playLabel;

    return Semantics(
      container: true,
      label: AppStrings.playerSectionLabel,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
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
              // Barra de progresso
              if (hasTrack && duration.inMilliseconds > 0)
                Column(
                  children: [
                    Semantics(
                      label: AppStrings.sliderPositionLabel,
                      hint: AppStrings.sliderPositionHint,
                      child: SliderTheme(
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
                            final newPosition = Duration(
                              milliseconds:
                                  (duration.inMilliseconds * value).round(),
                            );
                            provider.seek(newPosition);
                          },
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(position),
                            style: theme.textTheme.bodySmall,
                          ),
                          Text(
                            _formatDuration(duration),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),

              // Faixa atual
              if (hasTrack)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      Text(
                        provider.tracks[provider.currentIndex!].title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        provider.tracks[provider.currentIndex!].author,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.textTheme.bodySmall?.color,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

              // Controles
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Shuffle
                  Semantics(
                    button: true,
                    label: AppStrings.shuffleLabel,
                    child: IconButton(
                      icon: Icon(
                        Icons.shuffle,
                        color: provider.shuffleEnabled
                            ? theme.colorScheme.primary
                            : null,
                      ),
                      iconSize: 28,
                      tooltip: AppStrings.shuffleLabel,
                      onPressed: provider.toggleShuffle,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Previous
                  Semantics(
                    button: true,
                    label: AppStrings.previousLabel,
                    child: IconButton(
                      icon: const Icon(Icons.skip_previous),
                      iconSize: 32,
                      tooltip: AppStrings.previousLabel,
                      onPressed: hasTrack ? provider.seekToPrevious : null,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Play / Pause
                  Semantics(
                    button: true,
                    label: playPauseTooltip,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.primary,
                      ),
                      child: IconButton(
                        icon: Icon(
                          playPauseIcon,
                          color: theme.colorScheme.onPrimary,
                        ),
                        iconSize: 36,
                        tooltip: playPauseTooltip,
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
                  ),
                  const SizedBox(width: 8),

                  // Next
                  Semantics(
                    button: true,
                    label: AppStrings.nextLabel,
                    child: IconButton(
                      icon: const Icon(Icons.skip_next),
                      iconSize: 32,
                      tooltip: AppStrings.nextLabel,
                      onPressed: hasTrack ? provider.seekToNext : null,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Repeat
                  Semantics(
                    button: true,
                    label: repeatTooltip,
                    child: IconButton(
                      icon: Icon(
                        repeatIcon,
                        color: provider.repeatMode == RepeatMode.off
                            ? null
                            : theme.colorScheme.primary,
                      ),
                      iconSize: 28,
                      tooltip: repeatTooltip,
                      onPressed: () {
                        final nextMode = switch (provider.repeatMode) {
                          RepeatMode.off => RepeatMode.all,
                          RepeatMode.all => RepeatMode.one,
                          RepeatMode.one => RepeatMode.off,
                        };
                        provider.setRepeatMode(nextMode);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Stop
                  Semantics(
                    button: true,
                    label: AppStrings.stopLabel,
                    child: IconButton(
                      icon: const Icon(Icons.stop),
                      iconSize: 28,
                      tooltip: AppStrings.stopLabel,
                      onPressed: hasTrack ? provider.stop : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
