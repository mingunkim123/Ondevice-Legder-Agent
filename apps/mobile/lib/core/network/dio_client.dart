// 파일 위치: lib/core/network/dio_client.dart
import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DioClient {
  static final DioClient _instance = DioClient._internal();
  late final Dio dio;

  factory DioClient() {
    return _instance;
  }

  DioClient._internal() {
    // baseUrl 우선순위:
    //   1. --dart-define=API_BASE_URL=https://... (프로덕션 / 실기기)
    //   2. 기본값: http://10.0.2.2:8787 (Android 에뮬레이터 로컬 서버)
    //
    // 플랫폼별 로컬 테스트 주소:
    //   Android 에뮬레이터 → http://10.0.2.2:8787
    //   iOS 시뮬레이터     → http://localhost:8787
    //   실기기             → http://<컴퓨터_로컬_IP>:8787 (예: 192.168.0.10:8787)
    //   프로덕션 배포 후   → https://ledger-agent-api.<subdomain>.workers.dev
    //
    // 실기기 테스트: flutter run --dart-define=API_BASE_URL=http://192.168.x.x:8787
    const baseUrl = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://10.0.2.2:8787',
    );

    dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ),
    );

    // 가로채기(Interceptor): 요청이 서버로 떠나기 직전에 문서를 열어 비밀번호(토큰)를 도장 찍어줌
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final session = Supabase.instance.client.auth.currentSession;
          if (session?.accessToken != null) {
            options.headers['Authorization'] = 'Bearer ${session!.accessToken}';
          }
          return handler.next(options);
        },
      ),
    );
  }
}
