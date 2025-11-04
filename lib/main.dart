import 'package:flutter/material.dart';
import 'package:playlist_mp3_app/views/home_view.dart';
import 'package:provider/provider.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:workmanager/workmanager.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import 'providers/playlist_provider.dart';
import 'services/download_worker.dart';
import 'l10n/app_strings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Hive para persistência simples (progresso de downloads, flags, etc.)
  final appDir = await getApplicationDocumentsDirectory();
  Hive.init(appDir.path);

  // WorkManager para downloads em segundo plano
  await Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: false,
  );

  runApp(const MyApp());

  // JustAudioBackground precisa da Activity já criada
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      await JustAudioBackground.init(
        androidNotificationChannelId: 'br.edu.ifsul.playlist_mp3_app.playback',
        androidNotificationChannelName: 'Reprodução de Áudio',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        androidShowNotificationBadge: false,
        androidNotificationIcon: 'mipmap/ic_launcher',
      );
    } catch (_) {
      // Em caso de falha aqui, o áudio ainda funciona sem notificação
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
        title: AppStrings.appTitle,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: const HomeView(),
      ),
    );
  }
}
