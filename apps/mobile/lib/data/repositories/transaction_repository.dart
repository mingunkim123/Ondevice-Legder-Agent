import 'package:dio/dio.dart';
import '../../core/network/dio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

final transactionRepositoryProvider = Provider(
  (ref) => TransactionRepository(),
);

class TransactionRepository {
  final Dio _dio = DioClient().dio;
  final Uuid _uuid = const Uuid();

  Future<Map<String, dynamic>> fetchSummary(String month) async {
    try {
      final response = await _dio.get(
        '/api/transactions/summary',
        queryParameters: {'month': month},
      );
      return response.data;
    } catch (e) {
      throw Exception('통계 오류: $e');
    }
  }

  Future<List<dynamic>> fetchTransactions(String month) async {
    try {
      final response = await _dio.get(
        '/api/transactions',
        queryParameters: {'month': month},
      );
      return response.data['data'] ?? [];
    } catch (e) {
      throw Exception('조회 오류: $e');
    }
  }

  Future<void> addTransaction({
    required int amount, // int: 서버(Turso INTEGER) 및 로컬 DB(Drift IntColumn) 타입과 일치
    required String memo,
  }) async {
    final now = DateTime.now();
    final dateStr =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final id = _uuid.v4();

    // TODO: 오프라인 시 Drift sync_queue에 적재 후 나중에 전송 (Step 4)
    // 현재는 직접 API 호출 방식으로 구현
    try {
      await _dio.post(
        '/api/transactions',
        data: {
          'id': id,
          'amount': amount, // int 그대로 전송 → 서버 Zod number() 통과
          'date': dateStr,
          'category_id': 'food', // TODO: 카테고리 선택 UI 추가 후 파라미터로 받기
          'memo': memo,
          'source': 'form',
        },
        options: Options(headers: {'Idempotency-Key': id}),
      );
    } catch (e) {
      throw Exception('추가 통신 오류: $e');
    }
  }

  Future<void> deleteTransaction(String id) async {
    try {
      // 삭제 라우트에 Delete 요청 빵야!
      await _dio.delete('/api/transactions/$id');
    } catch (e) {
      throw Exception('삭제 통신 오류: $e');
    }
  }
}
