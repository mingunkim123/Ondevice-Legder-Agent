import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:ledger_agent/core/exceptions/app_exception.dart';

class ModelDownloadService {
  final String _modelFileName = "gemma_model.bin"; // 임의의 모델 파일명

  Future<String> getModelPath() async {
    final docsDir = await getApplicationDocumentsDirectory();
    return '${docsDir.path}/$_modelFileName';
  }

  Future<bool> isModelReady() async {
    final path = await getModelPath();
    final file = File(path);
    return await file.exists();
  }

  Stream<double> downloadModel() async* {
    yield 0.0;
    try {
      // 지정된 다운로드 URL이 없으므로, 현재는 3초에 걸쳐 진행률만 스트리밍하도록 Mocking 합니다.
      for (int i = 1; i <= 10; i++) {
        await Future.delayed(const Duration(milliseconds: 300));
        yield i / 10.0;
      }

      // 다운로드 완료 후 모델 생성 모사
      final path = await getModelPath();
      final file = File(path);
      await file.writeAsString("mock_model_content_for_testing");

      yield 1.0;
    } catch (e) {
      throw ModelDownloadException(
        "모델 다운로드 중 오류가 발생했습니다.",
        debugInfo: e.toString(),
      );
    }
  }

  Future<void> deleteModel() async {
    final path = await getModelPath();
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
