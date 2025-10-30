import 'package:flutter/material.dart';
import '../models/track.dart';

class TrackTile extends StatelessWidget {
  final Track track;
  final VoidCallback onPlay;
  const TrackTile({super.key, required this.track, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.music_note),
      title: Text(track.title),
      subtitle: Text(track.author),
      trailing: IconButton(icon: const Icon(Icons.play_arrow), onPressed: onPlay),
    );
  }
}
