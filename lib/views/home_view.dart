import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/playlist_provider.dart';
import '../widgets/track_tile.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});
  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PlaylistProvider>();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlaylistProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Playlist MP3 (Easter Egg)')),
      body: switch (provider.status) {
        PlaylistStatus.loading => const Center(child: CircularProgressIndicator()),
        PlaylistStatus.error   => Center(child: Text(provider.error ?? 'Erro')),
        PlaylistStatus.ready   => ListView.builder(
          itemCount: provider.tracks.length,
          itemBuilder: (context, i) => TrackTile(
            track: provider.tracks[i],
            onPlay: () => provider.play(i),
          ),
        ),
        _ => const SizedBox.shrink(),
      },
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.small(onPressed: provider.pause, child: const Icon(Icons.pause)),
          const SizedBox(width: 8),
          FloatingActionButton.small(onPressed: provider.stop, child: const Icon(Icons.stop)),
        ],
      ),
    );
  }
}
