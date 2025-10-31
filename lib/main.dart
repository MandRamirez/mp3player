import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "package:just_audio_background/just_audio_background.dart";
import "package:workmanager/workmanager.dart";

import "providers/playlist_provider.dart";
import "services/download_worker.dart";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa WorkManager
  await Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: false,
  );

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
      providers: [
        ChangeNotifierProvider(create: (_) => PlaylistProvider()),
      ],
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
      body: p.status == PlaylistStatus.loading
          ? const Center(child: CircularProgressIndicator())
          : p.status == PlaylistStatus.error
              ? Center(child: Text(p.error ?? "Erro desconhecido"))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: p.tracks.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final t = p.tracks[i];
                    return ListTile(
                      leading: const Icon(Icons.music_note),
                      title: Text(t.title),
                      subtitle: Text(t.author),
                      trailing: IconButton(
                        icon: const Icon(Icons.play_arrow),
                        onPressed: () => p.play(i),
                      ),
                    );
                  },
                ),
    );
  }
}
