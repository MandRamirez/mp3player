import 'package:flutter/material.dart';

import '../models/track.dart';
import '../l10n/app_strings.dart';

class TrackTile extends StatelessWidget {
  final Track track;
  final bool isPlaying;
  final String stateLabel;
  final double downloadProgress; // 0..1
  final VoidCallback onPlay;

  const TrackTile({
    super.key,
    required this.track,
    required this.onPlay,
    this.isPlaying = false,
    this.stateLabel = '',
    this.downloadProgress = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final primaryColor = theme.colorScheme.primary;
    final progressColor = theme.colorScheme.secondary;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Semantics(
        button: true,
        label: isPlaying
            ? AppStrings.pauseTrackLabel(track.title, track.author)
            : AppStrings.playTrackLabel(track.title, track.author),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPlay,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                title: Text(
                  track.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.author,
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (stateLabel.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          stateLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: primaryColor,
                          ),
                        ),
                      ),
                  ],
                ),
                leading: Icon(
                  isPlaying
                      ? Icons.equalizer_rounded
                      : Icons.music_note_rounded,
                  color: isPlaying ? primaryColor : null,
                  size: 28,
                ),
                trailing: IconButton(
                  tooltip:
                      isPlaying ? AppStrings.pauseLabel : AppStrings.playLabel,
                  icon: Icon(
                    isPlaying
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_fill_rounded,
                    color: isPlaying ? primaryColor : null,
                    size: 36,
                  ),
                  onPressed: onPlay,
                ),
              ),
              if (downloadProgress > 0 && downloadProgress < 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: downloadProgress,
                      minHeight: 6,
                      color: progressColor,
                      backgroundColor: progressColor.withOpacity(0.15),
                    ),
                  ),
                ),
              const Divider(height: 0),
            ],
          ),
        ),
      ),
    );
  }
}
