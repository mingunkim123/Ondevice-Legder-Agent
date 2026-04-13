import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_agent/core/utils/amount_utils.dart';

void main() {
  group('AmountUtils.parseKoreanAmount', () {
    test('숫자/Double rawAmount 파싱', () {
      expect(parseKoreanAmount(12000, "아무말"), 12000);
      expect(parseKoreanAmount(15000.0, "아무말"), 15000);
    });

    test('String 쉼표 포함 파싱', () {
      expect(parseKoreanAmount("12,000", "아무말"), 12000);
      expect(parseKoreanAmount("12,000.0", "아무말"), null);
    });

    test('자연어 내의 명확한 한글 금액 추출 ("만이천원")', () {
      expect(parseKoreanAmount(null, "만이천원 썼어"), 12000);
    });

    test('자연어 내의 숫자+한글 혼합 추출 ("5천원")', () {
      expect(parseKoreanAmount(null, "오늘 5천원 커피"), 5000);
    });

    test('자연어 내의 한글 금액단위 ("삼만원")', () {
      expect(parseKoreanAmount(null, "스타벅스 삼만원"), 30000);
    });

    test('자연어 내의 긴 한글 금액 ("십이만오천원")', () {
      expect(parseKoreanAmount(null, "관리비 십이만오천원"), 125000);
    });

    test('자연어 내 숫자만 포함 ("12000 점심")', () {
      expect(parseKoreanAmount(null, "12000 점심"), 12000);
    });

    test('자연어 내 쉼표 포함 숫자 ("12,000 점심")', () {
      expect(parseKoreanAmount(null, "12,000 점심"), 12000);
    });

    test('추출 불가시 null 반환', () {
      expect(parseKoreanAmount(null, "카페 갔어"), null);
    });
  });
}
