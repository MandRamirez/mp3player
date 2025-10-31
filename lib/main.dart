import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "package:just_audio_background/just_audio_background.dart";
import "package:workmanager/workmanager.dart";

import "providers/playlist_provider.dart";
import "services/download_worker.dart";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa WorkManager
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);

  // Sobe o app primeiro
  runApp(const MyApp());

  // 👉 Inicializa a notificação DEPOIS do primeiro frame (Activity já disponível)
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      await JustAudioBackground.init(
        androidNotificationChannelId: "br.edu.ifsul.playlist_mp3_app.playback",
        androidNotificationChannelName: "Reprodução de Áudio",
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        androidShowNotificationBadge: false,
        androidNotificationIcon: "mipmap/ic_launcher",
      );
    } catch (e) {
      // Log opcional: print("JustAudioBackground.init falhou: $e");
    }
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => PlaylistProvider())],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: "Playlist MP3 App",
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: const HomeView(),
      ),
    );
  }
}

class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlaylistProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text("Playlist MP3 (Easter Egg)")),
      body: switch (p.status) {
        PlaylistStatus.loading => const Center(
          child: CircularProgressIndicator(),
        ),
        PlaylistStatus.error => Center(
          child: Text(p.error ?? "Erro desconhecido"),
        ),
        _ => ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: p.tracks.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            final t = p.tracks[i];
            final isCurrent = p.currentIndex == i;
            return Card(
              child: ListTile(
                leading: const Icon(Icons.music_note),
                title: Text(t.title),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.author),
                    const SizedBox(height: 6),
                    // Barra de BUFFER (cinza claro) e posição (por cima)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Stack(
                        children: [
                          LinearProgressIndicator(
                            value: isCurrent ? p.bufferPercent : 0,
                            minHeight: 6,
                            backgroundColor: Colors.black12,
                          ),
                          LinearProgressIndicator(
                            value: isCurrent ? p.positionPercent : 0,
                            minHeight: 6,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: "Play",
                      icon: const Icon(Icons.play_arrow),
                      onPressed: () => p.play(i),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      },
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: Row(
          children: [
            IconButton(
              tooltip: "Shuffle",
              icon: Selector<PlaylistProvider, bool>(
                selector: (_, pp) => pp.shuffleEnabled,
                builder: (_, on, __) =>
                    Icon(on ? Icons.shuffle_on : Icons.shuffle),
              ),
              onPressed: () => p.toggleShuffle(),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<RepeatMode>(
              tooltip: "Repetição",
              onSelected: (m) => p.setRepeatMode(m),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: RepeatMode.off,
                  child: Text("Sem repetição"),
                ),
                PopupMenuItem(value: RepeatMode.one, child: Text("Repetir 1")),
                PopupMenuItem(
                  value: RepeatMode.all,
                  child: Text("Repetir todas"),
                ),
              ],
              child: Selector<PlaylistProvider, RepeatMode>(
                selector: (_, pp) => pp.repeatMode,
                builder: (_, m, __) =>
                    Icon(m == RepeatMode.one ? Icons.repeat_one : Icons.repeat),
              ),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.pause),
              onPressed: () => context.read<PlaylistProvider>().pause(),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.stop),
              onPressed: () => context.read<PlaylistProvider>().stop(),
            ),
          ],
        ),
      ),
    );
  }
}
