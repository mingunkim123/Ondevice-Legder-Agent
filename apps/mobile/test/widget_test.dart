// Flutter 위젯 테스트
//
// 현재 MyApp은 Supabase.initialize() 이후에만 동작하므로
// 테스트 환경에서 직접 pumpWidget(MyApp())을 호출하면 크래시한다.
//
// 통합 테스트 추가 시 아래 순서로 진행:
//   1. Supabase mock 패키지 설치 (mocktail 또는 mockito)
//   2. MockSupabaseClient 주입
//   3. ProviderScope + overrides로 Repository mock 교체
//
// TODO: 추후 단위 테스트 작성
//   - TransactionRepository 파싱 테스트
//   - amount 유효성 검증 테스트
//   - 날짜 포맷 생성 테스트

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('placeholder - 실제 테스트는 TODO 참고', () {
    expect(1 + 1, equals(2));
  });
}
