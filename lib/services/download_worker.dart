import "dart:io";

import "package:dio/dio.dart";
import "package:hive/hive.dart";
import "package:path_provider/path_provider.dart";
import "package:workmanager/workmanager.dart";

const taskDownload = "download_mp3_task";

// Flag simples para garantir que o Hive seja inicializado apenas uma vez
bool _hiveInitialized = false;

/// Callback global do Workmanager
@pragma("vm:entry-point")
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != taskDownload) return Future.value(true);

    final url = inputData?["url"] as String?;
    final id = inputData?["id"] as String?;

    if (url == null || id == null) {
      return Future.value(false);
    }

    try {
      final dir = await getApplicationDocumentsDirectory();

      // Garante que o Hive esteja inicializado neste isolate de background
      if (!_hiveInitialized) {
        Hive.init(dir.path);
        _hiveInitialized = true;
      }

      final file = File("${dir.path}/$id.mp3");
      final box = await Hive.openBox("downloads");

      // Se já existir arquivo parcialmente baixado, continua de onde parou
      int downloaded = file.existsSync() ? file.lengthSync() : 0;

      // Ao iniciar (ou reiniciar) o download, limpa flag de erro
      box.put("${id}_error", false);

      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(minutes: 5),
          sendTimeout: const Duration(seconds: 10),
          headers: downloaded > 0 ? {"range": "bytes=$downloaded-"} : null,
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

        final totalHeader = res.headers.map["content-length"]?.first ?? "0";
        final int totalInt = int.tryParse(totalHeader) ?? 0;

        int received = 0;
        final stream = res.data?.stream;

        if (stream == null) {
          box.put("${id}_error", true);
          return Future.value(false);
        }

        await for (final chunk in stream) {
          received += chunk.length;
          sink.add(chunk);

          // Bytes totais já gravados em disco
          final currentBytes = downloaded + received;

          // Atualiza progresso no Hive (em bytes)
          box.put("${id}_progress", currentBytes);

          // Tamanho total estimado do arquivo (se o servidor informar)
          if (totalInt > 0) {
            box.put("${id}_total", downloaded + totalInt);
          }
        }

        box.put("${id}_done", true);
        return Future.value(true);
      } finally {
        // Garante que o arquivo seja fechado mesmo em caso de erro
        await sink.flush();
        await sink.close();
      }
    } catch (_) {
      // Marca erro no Hive para a UI conseguir mostrar estado "erro"
      final errId = inputData?["id"] as String?;
      if (errId != null) {
        final box = await Hive.openBox("downloads");
        box.put("${errId}_error", true);
      }
      return Future.value(false);
    }
  });
}
