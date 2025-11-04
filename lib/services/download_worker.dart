import 'dart:io';

import 'package:dio/dio.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

const taskDownload = 'download_mp3_task';

// Evita múltiplos Hive.init no mesmo isolate
bool _hiveInitialized = false;

/// Entry point do Workmanager
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != taskDownload) return Future.value(true);

    final url = inputData?['url'] as String?;
    final id = inputData?['id'] as String?;

    if (url == null || id == null) {
      return Future.value(false);
    }

    try {
      final dir = await getApplicationDocumentsDirectory();

      if (!_hiveInitialized) {
        Hive.init(dir.path);
        _hiveInitialized = true;
      }

      final file = File('${dir.path}/$id.mp3');
      final box = await Hive.openBox('downloads');

      final downloaded = file.existsSync() ? file.lengthSync() : 0;

      // Reset de erro a cada (re)início de download
      box.put('${id}_error', false);

      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(minutes: 5),
          sendTimeout: const Duration(seconds: 10),
          headers: downloaded > 0 ? {'range': 'bytes=$downloaded-'} : null,
        ),
      );

      final sink = file.openWrite(mode: FileMode.append);

      try {
        final res = await dio.get<ResponseBody>(
          url,
          options: Options(
            responseType: ResponseType.stream,
            followRedirects: true,
          ),
        );

        final totalHeader = res.headers.map['content-length']?.first ?? '0';
        final totalInt = int.tryParse(totalHeader) ?? 0;

        var received = 0;
        final stream = res.data?.stream;

        if (stream == null) {
          box.put('${id}_error', true);
          return Future.value(false);
        }

        await for (final chunk in stream) {
          received += chunk.length;
          sink.add(chunk);

          final currentBytes = downloaded + received;

          box.put('${id}_progress', currentBytes);

          if (totalInt > 0) {
            box.put('${id}_total', downloaded + totalInt);
          }
        }

        box.put('${id}_done', true);
        return Future.value(true);
      } finally {
        await sink.flush();
        await sink.close();
      }
    } catch (_) {
      final errId = inputData?['id'] as String?;
      if (errId != null) {
        try {
          // Garante init do Hive também neste caminho de erro
          final dir = await getApplicationDocumentsDirectory();
          if (!_hiveInitialized) {
            Hive.init(dir.path);
            _hiveInitialized = true;
          }
          final box = await Hive.openBox('downloads');
          box.put('${errId}_error', true);
        } catch (_) {
          // Se der erro aqui, não há muito o que fazer além de falhar a task
        }
      }
      return Future.value(false);
    }
  });
}
