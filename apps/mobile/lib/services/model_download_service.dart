// 파일 위치: lib/services/model_download_service.dart
import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ledger_agent/core/constants/model_config.dart';
import 'package:ledger_agent/core/exceptions/app_exception.dart';

class ModelDownloadService {
  final Dio _dio = Dio();

  /// 기기 내부 저장소의 모델 파일 경로를 반환한다.
  Future<String> getModelPath() async {
    final docsDir = await getApplicationDocumentsDirectory();
    return '${docsDir.path}/$kModelFileName';
  }

  /// 모델 파일이 이미 다운로드되어 있는지 확인한다.
  Future<bool> isModelReady() async {
    final path = await getModelPath();
    final file = File(path);
    if (!await file.exists()) return false;
    // 크기가 너무 작으면 손상된 파일로 간주 (정상 모델은 100MB 이상)
    final stat = await file.stat();
    return stat.size > 100 * 1024 * 1024;
  }

  /// 모델을 HuggingFace에서 다운로드한다.
  /// 진행률(0.0 ~ 1.0)을 Stream으로 내보낸다.
  Stream<double> downloadModel() async* {
    final savePath = await getModelPath();

    if (kHuggingFaceToken == 'hf_YOUR_TOKEN_HERE') {
      throw ModelDownloadException(
        'HuggingFace 토큰이 설정되지 않았습니다.',
        debugInfo: 'lib/core/constants/model_config.dart의 kHuggingFaceToken을 설정해주세요.',
      );
    }

    yield 0.0;

    try {
      await _dio.download(
        kModelDownloadUrl,
        savePath,
        options: Options(
          headers: {'Authorization': 'Bearer $kHuggingFaceToken'},
          receiveTimeout: const Duration(minutes: 30),
        ),
        onReceiveProgress: (received, total) {
          // total이 -1이면 서버가 Content-Length를 안 보낸 것
          if (total > 0) {
            // onReceiveProgress는 동기 콜백이라 yield 직접 호출 불가
            // → StreamController로 우회하지 않고 별도 스트림으로 분리
          }
        },
        deleteOnError: true, // 실패 시 불완전 파일 삭제
      );
    } on DioException catch (e) {
      // 실패 시 불완전 파일 정리
      final file = File(savePath);
      if (await file.exists()) await file.delete();

      if (e.response?.statusCode == 401) {
        throw ModelDownloadException(
          'HuggingFace 인증 실패: 토큰을 확인하거나 Gemma 이용 약관 동의 여부를 확인해주세요.',
          debugInfo: e.message,
        );
      }
      throw ModelDownloadException(
        '모델 다운로드 중 오류가 발생했습니다.',
        debugInfo: e.message,
      );
    }

    yield 1.0;
  }

  /// 진행률 스트림을 실시간으로 받는 버전 (StreamController 사용)
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
          if (!controller.isClosed) {
            controller.add(1.0);
          }
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

  /// 다운로드된 모델 파일을 삭제한다. (재다운로드 시 사용)
  Future<void> deleteModel() async {
    final path = await getModelPath();
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
