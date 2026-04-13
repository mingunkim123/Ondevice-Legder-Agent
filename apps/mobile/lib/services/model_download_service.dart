// 파일 위치: lib/services/model_download_service.dart
import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ledger_agent/core/constants/model_config.dart';
import 'package:ledger_agent/core/exceptions/app_exception.dart';

class ModelDownloadService {
  final Dio _dio = Dio();

  /// flutter_gemma가 사용하는 모델 경로
  /// (flutter_gemma 내부: getApplicationDocumentsDirectory() + '/model.bin')
  Future<String> getModelPath() async {
    final docsDir = await getApplicationDocumentsDirectory();
    return '${docsDir.path}/$kModelFileName';
  }

  /// 모델 파일이 유효하게 존재하는지 확인 (100MB 이상이어야 정상 파일)
  Future<bool> isModelReady() async {
    final path = await getModelPath();
    final file = File(path);
    if (!await file.exists()) return false;
    final stat = await file.stat();
    return stat.size > 100 * 1024 * 1024;
  }

  /// 기기 내 파일을 앱 내부 저장소로 복사한다.
  /// 진행률(0.0 ~ 1.0)을 Stream으로 내보낸다.
  Stream<double> importFromFile(String sourcePath) async* {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw ModelDownloadException('선택한 파일을 찾을 수 없습니다.');
    }

    final sourceSize = await source.length();
    if (sourceSize < 100 * 1024 * 1024) {
      throw ModelDownloadException(
        '파일 크기가 너무 작습니다. 올바른 모델 파일인지 확인해주세요.',
      );
    }

    final destPath = await getModelPath();
    final dest = File(destPath);

    // 이미 있으면 삭제하고 새로 복사
    if (await dest.exists()) await dest.delete();

    yield 0.0;

    try {
      final sink = dest.openWrite();
      int copied = 0;

      await for (final chunk in source.openRead()) {
        sink.add(chunk);
        copied += chunk.length;
        yield copied / sourceSize;
      }

      await sink.flush();
      await sink.close();
    } catch (e) {
      // 실패 시 불완전 파일 삭제
      if (await dest.exists()) await dest.delete();
      throw ModelDownloadException(
        '파일 복사 중 오류가 발생했습니다.',
        debugInfo: e.toString(),
      );
    }

    yield 1.0;
  }

  /// HuggingFace에서 모델을 다운로드한다.
  /// 진행률(0.0 ~ 1.0)을 Stream으로 내보낸다.
  Stream<double> downloadModelWithProgress() {
    late final StreamController<double> controller;

    controller = StreamController<double>(
      onListen: () async {
        final savePath = await getModelPath();

        if (kHuggingFaceToken == 'hf_YOUR_TOKEN_HERE') {
          controller.addError(ModelDownloadException(
            'HuggingFace 토큰이 설정되지 않았습니다.',
            debugInfo: 'lib/core/constants/model_config.dart의 kHuggingFaceToken을 설정해주세요.',
          ));
          await controller.close();
          return;
        }

        controller.add(0.0);

        try {
          await _dio.download(
            kModelDownloadUrl,
            savePath,
            options: Options(
              headers: {'Authorization': 'Bearer $kHuggingFaceToken'},
              receiveTimeout: const Duration(minutes: 30),
            ),
            onReceiveProgress: (received, total) {
              if (total > 0 && !controller.isClosed) {
                controller.add(received / total);
              }
            },
            deleteOnError: true,
          );
          if (!controller.isClosed) controller.add(1.0);
        } on DioException catch (e) {
          final file = File(savePath);
          if (await file.exists()) await file.delete();

          if (!controller.isClosed) {
            if (e.response?.statusCode == 401) {
              controller.addError(ModelDownloadException(
                'HuggingFace 인증 실패: 토큰 또는 이용 약관 동의를 확인해주세요.',
                debugInfo: e.message,
              ));
            } else {
              controller.addError(ModelDownloadException(
                '모델 다운로드 중 오류가 발생했습니다.',
                debugInfo: e.message,
              ));
            }
          }
        } finally {
          if (!controller.isClosed) await controller.close();
        }
      },
    );

    return controller.stream;
  }

  Future<void> deleteModel() async {
    final path = await getModelPath();
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
