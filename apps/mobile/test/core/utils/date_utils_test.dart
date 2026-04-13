import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_agent/core/utils/date_utils.dart';

void main() {
  group('DateUtils.parseKoreanRelativeDate', () {
    final now = DateTime(2024, 4, 8); // 2024-04-08 (월요일)

    test('"오늘" 파싱 검증', () {
      final res = parseKoreanRelativeDate("오늘 점심 먹었어", now);
      expect(res, DateTime(2024, 4, 8));
    });

    test('"어제" 파싱 검증', () {
      final res = parseKoreanRelativeDate("어제 커피", now);
      expect(res, DateTime(2024, 4, 7));
    });

    test('"그저께" 파싱 검증', () {
      final res = parseKoreanRelativeDate("그저께 병원", now);
      expect(res, DateTime(2024, 4, 6));
    });

    test('"그제" 파싱 검증', () {
      final res = parseKoreanRelativeDate("그제 택시비", now);
      expect(res, DateTime(2024, 4, 6));
    });

    test('"엊그제" 파싱 검증', () {
      final res = parseKoreanRelativeDate("엊그제 배달", now);
      expect(res, DateTime(2024, 4, 6));
    });

    test('"내일" 파싱 검증', () {
      final res = parseKoreanRelativeDate("내일 결제", now);
      expect(res, DateTime(2024, 4, 9));
    });

    test('"모레" 파싱 검증', () {
      final res = parseKoreanRelativeDate("모레 여행", now);
      expect(res, DateTime(2024, 4, 10));
    });

    test('"지난주" 파싱 검증', () {
      final res = parseKoreanRelativeDate("지난주 쇼핑", now);
      expect(res, DateTime(2024, 4, 1));
    });

    test('날짜 키워드 없음', () {
      final res = parseKoreanRelativeDate("커피 한 잔", now);
      expect(res, isNull);
    });
  });
}
