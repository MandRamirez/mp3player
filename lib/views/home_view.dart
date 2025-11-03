import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart' as ja;

import '../providers/playlist_provider.dart';
import '../widgets/track_tile.dart';
import '../widgets/player_controls.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PlaylistProvider>();
    });
  }

  Future<void> reloadTracks() async {
    await context.read<PlaylistProvider>().reloadTracks();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlaylistProvider>();

    // Mantido por compatibilidade, mas hoje a ordem é dada pelo próprio `tracks`
    List<int> getDisplayIndices() {
      if (!provider.shuffleEnabled || provider.shuffledIndices == null) {
        return List.generate(provider.tracks.length, (i) => i);
      }
      return provider.shuffledIndices!;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Playlist MP3'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _refreshIndicatorKey.currentState?.show();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: switch (provider.status) {
              PlaylistStatus.loading =>
                const Center(child: CircularProgressIndicator()),

              PlaylistStatus.error =>
                RefreshIndicator(
                  key: _refreshIndicatorKey,
                  onRefresh: reloadTracks,
                  child: ListView(
                    children: [
                      Container(
                        height: MediaQuery.of(context).size.height - 200,
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: 64,
                              color: Colors.red,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              provider.error ?? 'Erro',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 16),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: reloadTracks,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Tentar novamente'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              PlaylistStatus.ready =>
                RefreshIndicator(
                  key: _refreshIndicatorKey,
                  onRefresh: reloadTracks,
                  child: provider.tracks.isEmpty
                      ? ListView(
                          children: [
                            Container(
                              height:
                                  MediaQuery.of(context).size.height - 200,
                              alignment: Alignment.center,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.music_note,
                                    size: 64,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withOpacity(0.5),
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'Nenhuma música disponível',
                                    style: TextStyle(fontSize: 16),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 8),
                          itemCount: provider.tracks.length,
                          itemBuilder: (context, i) {
                            final displayIndices = getDisplayIndices();
                            final trackIndex = displayIndices[i];
                            final track = provider.tracks[trackIndex];

                            final isPlaying =
                                provider.currentIndex == trackIndex;
                            final isCurrent = isPlaying;

                            // --- ESTADO DE DOWNLOAD ---
                            final progress =
                                provider.downloadProgressFor(track.id);
                            final downloaded =
                                provider.isDownloaded(track.id);
                            final hasError =
                                provider.hasDownloadError(track.id);

                            // Buffer da faixa atual (streaming progressivo)
                            final isBuffering = isCurrent &&
                                provider.processing ==
                                    ja.ProcessingState.buffering;

                            // Monta o label de estado mostrado no item
                            String stateLabel;
                            if (hasError) {
                              stateLabel = 'Erro no download';
                            } else if (isCurrent && isBuffering) {
                              stateLabel = 'Aguardando buffer...';
                            } else if (isCurrent && provider.isPlaying) {
                              stateLabel = 'Reproduzindo';
                            } else if (isCurrent &&
                                !provider.isPlaying &&
                                downloaded) {
                              stateLabel = 'Pausado';
                            } else if (progress > 0 && progress < 1) {
                              stateLabel =
                                  'Baixando ${(progress * 100).toStringAsFixed(0)}%';
                            } else if (downloaded) {
                              stateLabel = 'Baixado';
                            } else {
                              stateLabel = '';
                            }

                            return TrackTile(
                              track: track,
                              isPlaying: isPlaying,
                              stateLabel: stateLabel,
                              downloadProgress: progress,
                              onPlay: () => provider.play(trackIndex),
                            );
                          },
                        ),
                ),

              _ => const SizedBox.shrink(),
            },
          ),
          const PlayerControls(),
        ],
      ),
    );
  }
}
