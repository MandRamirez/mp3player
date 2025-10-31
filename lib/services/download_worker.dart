import "dart:io";
import "package:dio/dio.dart";
import "package:hive/hive.dart";
import "package:path_provider/path_provider.dart";
import "package:workmanager/workmanager.dart";

const taskDownload = "download_mp3_task";

/// Registra o callback global do Workmanager
@pragma("vm:entry-point")
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != taskDownload) return Future.value(true);
    try {
      final url = inputData?["url"] as String;
      final id  = inputData?["id"]  as String;

      final dir = await getApplicationDocumentsDirectory();
      final file = File("${dir.path}/$id.mp3");

      final box = await Hive.openBox("downloads");
      int downloaded = file.existsSync() ? file.lengthSync() : 0;

      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(minutes: 5),
        sendTimeout: const Duration(seconds: 10),
        headers: downloaded > 0 ? {"range": "bytes=$downloaded-"} : null,
      ));

      final sink = file.openWrite(mode: FileMode.append);
      final res = await dio.get<ResponseBody>(
        url,
        options: Options(responseType: ResponseType.stream, followRedirects: true),
      );

      final total = (res.headers.map["content-length"]?.first ?? "0");
      final int totalInt = int.tryParse(total) ?? 0;

      int received = 0;
      await for (final chunk in res.data!.stream) {
        received += chunk.length;
        sink.add(chunk);
        box.put("${id}_progress", downloaded + received);
        box.put("${id}_total", totalInt > 0 ? downloaded + totalInt : null);
      }
      await sink.flush();
      await sink.close();

      box.put("${id}_done", true);
      return Future.value(true);
    } catch (_) {
      return Future.value(false);
    }
  });
}
