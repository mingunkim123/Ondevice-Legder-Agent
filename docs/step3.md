# Step 3: 온디바이스 에이전트 통합 — 구현 워크플로우

> **목표**: 자연어 입력 → Gemma 온디바이스 해석 → 사용자 확인 UI → API 호출까지의 전체 파이프라인 완성
>
> **전제조건**: Step 2(Flutter 기본 UI — 폼 입력, 조회, 삭제)가 완료된 상태

---

## 현재 완료된 것 (Step 2 산출물)

| 파일 | 상태 |
|------|------|
| `domain/agent/ledger_intent.dart` | 완료 (IntentType enum + LedgerIntent 클래스 + fromJson 팩토리) |
| `core/constants/categories.dart` | 완료 (8개 고정 카테고리) |
| `presentation/home/home_screen.dart` | 완료 (통계 카드 + 지출 목록 + FAB) |
| `data/repositories/transaction_repository.dart` | 완료 (CRUD API 호출) |
| `core/network/dio_client.dart` | 완료 (Dio + JWT 인터셉터) |

---

## 전체 구현 순서 (7일 기준)

```
Phase 1: 기반 유틸리티 (Day 1)
    ↓
Phase 2: 모델 다운로드 서비스 (Day 2)
    ↓
Phase 3: 에이전트 서비스 코어 (Day 3)
    ↓
Phase 4: 상태관리 (Day 4)
    ↓
Phase 5: UI 위젯 (Day 5)
    ↓
Phase 6: HomeScreen 통합 (Day 6)
    ↓
Phase 7: 테스트 및 엣지케이스 보강 (Day 7)
```

---

## Phase 1: 기반 유틸리티 구현 (Day 1)

### 1-1. 한국어 날짜 파서 생성

**파일**: `lib/core/utils/date_utils.dart` (신규)

```dart
DateTime? parseKoreanRelativeDate(String text, DateTime now)
```

- "오늘", "어제", "그저께/그제", "지난주", "엊그제" 등 상대 날짜 키워드 → DateTime 변환
- 매칭 실패 시 `null` 반환 (모델에 위임)
- 단위 테스트 케이스: 최소 8개 (오늘/어제/그저께/지난주/모레/없는 경우 등)

### 1-2. 한국어 금액 파서 생성

**파일**: `lib/core/utils/amount_utils.dart` (신규)

```dart
int? parseKoreanAmount(dynamic rawAmount, String utterance)
```

- 숫자 타입(int/double) → 그대로 int 변환
- 한국어 표현("만이천원", "5천원", "삼만원") → 숫자 변환
- 쉼표 포함 문자열("12,000") → 숫자 변환
- 변환 불가 시 `null` 반환

### 1-3. AppException 정의

**파일**: `lib/core/exceptions/app_exception.dart` (신규)

```dart
class ModelDownloadException extends AppException { ... }
class ModelInferenceException extends AppException { ... }
class ParseException extends AppException { ... }
```

- 에이전트 파이프라인 각 단계별 예외 클래스 정의
- 사용자에게 보여줄 메시지(`userMessage`)와 디버그 정보(`debugInfo`) 분리

### Phase 1 완료 기준
- [ ] `date_utils.dart` 작성 완료 + 단위 테스트 통과
- [ ] `amount_utils.dart` 작성 완료 + 단위 테스트 통과
- [ ] `app_exception.dart` 작성 완료

---

## Phase 2: 모델 다운로드 서비스 (Day 2)

### 2-1. LiteRT-LM 패키지 의존성 추가

**파일**: `pubspec.yaml` (수정)

- `litert_lm` (또는 동등한 Gemma 온디바이스 추론 패키지) 의존성 추가
- 참고: Google AI Edge LiteRT-LM Flutter 플러그인 사용

### 2-2. ModelDownloadService 구현

**파일**: `lib/services/model_download_service.dart` (신규)

```dart
class ModelDownloadService {
  Future<String> getModelPath()          // 모델 파일 경로 반환
  Future<bool> isModelReady()            // 다운로드 완료 여부
  Stream<double> downloadModel()         // 다운로드 진행률 스트림 (0.0~1.0)
  Future<void> deleteModel()             // 모델 삭제 (재다운로드용)
}
```

핵심 로직:
1. 앱 첫 실행 시 모델 파일이 로컬에 있는지 확인 (`path_provider` 활용)
2. 없으면 다운로드 시작 → `Stream<double>`로 진행률 노출
3. 다운로드 완료 후 파일 경로를 캐시
4. 다운로드 실패 시 `ModelDownloadException` throw + 재시도 가능

### 2-3. 모델 다운로드 UI

**파일**: `lib/presentation/agent/model_download_indicator.dart` (신규)

- 다운로드 진행률 표시 위젯 (LinearProgressIndicator + 퍼센트 텍스트)
- 다운로드 완료 시 자동으로 숨김
- 다운로드 실패 시 "재시도" 버튼 표시

### Phase 2 완료 기준
- [ ] `ModelDownloadService` 구현 완료
- [ ] 앱 실행 시 모델 존재 여부 확인 동작
- [ ] 다운로드 진행률이 UI에 정상 표시
- [ ] 다운로드 실패 → 재시도 버튼 → 재다운로드 동작

---

## Phase 3: 에이전트 서비스 코어 (Day 3)

### 3-1. 프롬프트 빌더 구현

**파일**: `lib/services/ledger_agent_service.dart` (신규) — 프롬프트 부분

```dart
String buildPrompt(String userInput, DateTime now)
```

- 현재 날짜를 "2024-04-08 (월요일)" 형식으로 주입
- 8개 고정 카테고리 목록 주입 (`kCategories` 참조)
- Few-shot 예시에 실제 날짜 계산해서 주입 (핵심: "어제" → 실제 어제 날짜)
- JSON 스키마 명시

### 3-2. 모델 추론 호출 구현

**파일**: `lib/services/ledger_agent_service.dart` (계속)

```dart
Future<String> runInference(String prompt)
```

- `ModelDownloadService.getModelPath()`로 모델 경로 획득
- LiteRT-LM 세션 생성 → 프롬프트 전달 → 추론 실행
- 추론 실패 시 `ModelInferenceException` throw
- 타임아웃 설정 (예: 10초)

### 3-3. JSON 파싱 + LedgerIntent 변환

**파일**: `lib/services/ledger_agent_service.dart` (계속)

```dart
LedgerIntent parseModelOutput(String rawOutput, String userInput, DateTime now)
```

핵심 로직:
1. `RegExp(r'\{[\s\S]*\}')` 로 JSON 블록 추출
2. `jsonDecode` → `LedgerIntent.fromJson`
3. **Rule-based 보정** 적용:
   - 날짜가 null이면 `parseKoreanRelativeDate`로 재시도
   - 금액이 null이면 `parseKoreanAmount`로 utterance에서 재추출
   - 카테고리 ID가 유효한 8개에 포함되는지 검증
4. **confidence 계산**: amount 있으면 +0.4, date 있으면 +0.3, category 있으면 +0.3
5. 파싱 완전 실패 시 `_fallbackAmountExtract()`로 금액만이라도 추출 시도

### 3-4. 통합 파이프라인 메서드

```dart
Future<LedgerIntent> processUserInput(String text, DateTime now)
```

전체 흐름: `buildPrompt` → `runInference` → `parseModelOutput` → `LedgerIntent` 반환

### Phase 3 완료 기준
- [ ] 프롬프트에 현재 날짜와 카테고리가 정상 주입됨
- [ ] 모델 추론이 에뮬레이터/실기기에서 동작
- [ ] JSON 파싱 → LedgerIntent 변환 성공
- [ ] rule-based 보정 로직 동작 (날짜/금액 fallback)
- [ ] 파싱 완전 실패 시 ParseException throw (앱 크래시 없음)

---

## Phase 4: 상태관리 — AgentProvider (Day 4)

### 4-1. 에이전트 상태 정의

**파일**: `lib/presentation/agent/agent_provider.dart` (신규)

```dart
enum AgentStatus {
  idle,              // 대기 중
  processing,        // 모델 추론 중 (로딩 표시)
  confirmRequired,   // 신뢰도 >= 0.7 → 확인 바텀시트 표시
  ambiguousConfirm,  // 신뢰도 < 0.7 → 모호 확인 시트 표시
  error,             // 추론/파싱 실패 → 수동 폼 fallback
}

class AgentState {
  final AgentStatus status;
  final LedgerIntent? intent;
  final String? errorMessage;
}
```

### 4-2. StateNotifier 구현

```dart
class AgentNotifier extends StateNotifier<AgentState> {
  Future<void> processInput(String text)   // 입력 → 상태 전이
  void confirmIntent()                      // 확인 → 저장
  void rejectIntent()                       // 거부 → idle 복귀
  void updateIntent(LedgerIntent modified)  // 수정 후 재확인
  void reset()                              // 상태 초기화
}
```

상태 전이 흐름:
```
idle → processing → confirmRequired → (확인) → idle (저장 완료)
                  → ambiguousConfirm → (수정 후 확인) → idle
                  → error → (폼 이동) → idle
```

### 4-3. 저장 시 TransactionRepository 연결

- `confirmIntent()` 호출 시 `TransactionRepository.addTransaction()` 실행
- 저장 성공 후 `summaryProvider` + `transactionsProvider` invalidate

### Phase 4 완료 기준
- [ ] 상태 전이가 올바르게 동작 (idle → processing → confirm/ambiguous/error)
- [ ] confirmIntent 시 API 호출 → 목록 갱신
- [ ] rejectIntent 시 idle로 복귀
- [ ] error 상태에서 수동 폼으로 이동 가능

---

## Phase 5: UI 위젯 구현 (Day 5)

### 5-1. 자연어 입력 바

**파일**: `lib/presentation/agent/natural_language_input_bar.dart` (신규)

- 홈 화면 하단 고정 TextField + 전송 버튼
- 전송 시 `AgentNotifier.processInput(text)` 호출
- 추론 중(processing) 상태에서 로딩 인디케이터 표시
- 빈 텍스트 전송 방지

### 5-2. 확인 바텀시트 (신뢰도 >= 0.7)

**파일**: `lib/presentation/agent/agent_confirm_sheet.dart` (신규)

표시 내용:
- "이렇게 기록할까요?" 타이틀
- 파싱 결과 미리보기: 날짜, 금액, 카테고리(이모지 포함), 메모
- [취소] / [저장] 버튼
- 삭제 intent인 경우 배경 오렌지색 + 경고 문구 표시 (`isRiskyIntent` 체크)

동작:
- [저장] → `AgentNotifier.confirmIntent()`
- [취소] → `AgentNotifier.rejectIntent()`

### 5-3. 모호 확인 시트 (신뢰도 < 0.7)

**파일**: `lib/presentation/agent/agent_ambiguous_sheet.dart` (신규)

표시 내용:
- "정보를 확인해주세요" 타이틀
- `ambiguityReason` 표시 (모델이 알려준 모호 이유)
- 카테고리만 모호: 카테고리 선택 칩 UI (8개 중 택 1)
- 금액/날짜 모호: 직접 입력 필드
- [저장] / [직접 입력하기] 버튼

동작:
- 사용자가 모호한 필드를 수정 → `AgentNotifier.updateIntent(modified)`
- [저장] → `AgentNotifier.confirmIntent()`
- [직접 입력하기] → `AddTransactionScreen`으로 이동 (파싱된 값 미리 채움)

### 5-4. 에러 시 폼 fallback

- `AgentStatus.error` 감지 시 SnackBar로 에러 메시지 표시
- "직접 입력하기" 버튼 → `AddTransactionScreen`으로 이동

### Phase 5 완료 기준
- [ ] 입력 바에서 텍스트 전송 → 로딩 → 바텀시트 표시 흐름 동작
- [ ] 확인 바텀시트에서 파싱 결과가 올바르게 표시됨
- [ ] 삭제 intent 시 경고 UI가 표시됨
- [ ] 모호 시트에서 카테고리 선택 후 저장 동작
- [ ] 파싱 실패 시 수동 폼으로 이동 동작

---

## Phase 6: HomeScreen 통합 (Day 6)

### 6-1. HomeScreen 레이아웃 변경

**파일**: `lib/presentation/home/home_screen.dart` (수정)

변경 사항:
- `Scaffold.body` 하단에 `NaturalLanguageInputBar` 배치
- 기존 FAB(+) 버튼은 유지 (폼 직접 입력 경로)
- `AgentProvider` 상태 구독 → 바텀시트 자동 트리거

```dart
// 변경 후 구조
Scaffold(
  body: Column(
    children: [
      Expanded(child: CustomScrollView(...)),  // 기존 목록
      NaturalLanguageInputBar(),                // 신규 추가
    ],
  ),
  floatingActionButton: ...,  // 기존 유지
)
```

### 6-2. 바텀시트 트리거 연결

- `AgentStatus.confirmRequired` → `showModalBottomSheet(AgentConfirmSheet)`
- `AgentStatus.ambiguousConfirm` → `showModalBottomSheet(AgentAmbiguousSheet)`
- `AgentStatus.error` → SnackBar + 폼 이동 옵션
- 바텀시트 닫힐 때 `AgentNotifier.reset()` 호출

### 6-3. 저장 성공 후 목록 갱신

- `confirmIntent` 성공 시 `summaryProvider` + `transactionsProvider` invalidate
- 성공 SnackBar: "기록되었습니다: [카테고리] [금액]원"

### Phase 6 완료 기준
- [ ] 홈 화면 하단에 자연어 입력 바가 표시됨
- [ ] "오늘 점심 12000원" 입력 → 확인 시트 → 저장 → 목록 갱신 전체 플로우 동작
- [ ] FAB 버튼으로 기존 폼 입력도 여전히 동작
- [ ] 삭제 입력 시 경고 확인 거쳐야만 삭제됨

---

## Phase 7: 테스트 및 엣지케이스 보강 (Day 7)

### 7-1. 수동 테스트 시나리오 (20개)

| # | 입력 | 기대 결과 |
|---|------|-----------|
| 1 | "오늘 점심 12000원 썼어" | record_expense, food, 12000, 오늘 날짜 |
| 2 | "어제 스벅 5800원" | record_expense, cafe, 5800, 어제 날짜 |
| 3 | "택시 32000원" | record_expense, transport, 32000, 오늘(기본) |
| 4 | "그저께 병원 15000원" | record_expense, health, 15000, 그저께 날짜 |
| 5 | "CGV 영화 14000원" | record_expense, culture, 14000, 오늘 |
| 6 | "쿠팡 배송비 3000원" | record_expense, shopping, 3000, 오늘 |
| 7 | "관리비 120000원 냈어" | record_expense, utility, 120000, 오늘 |
| 8 | "5000원 썼어" | record_expense, etc, 5000 (카테고리 모호 가능) |
| 9 | "이번 달 식비 얼마야?" | query_balance, food |
| 10 | "오늘 기록 삭제해줘" | delete_last → 경고 확인 시트 |
| 11 | "어제 카페 삭제" | delete_by_date → 경고 확인 시트 |
| 12 | "커피 한 잔" | ambiguous (금액 없음) |
| 13 | "ㅁㄴㅇㄹ" | unsupported → 폼 fallback |
| 14 | "만이천원 점심" | record_expense, food, 12000 (한국어 금액) |
| 15 | "지난주 쇼핑 5만원" | record_expense, shopping, 50000, 지난주 |
| 16 | "" (빈 입력) | 전송 차단 |
| 17 | "오늘 아이스아메리카노 4500원" | record_expense, cafe, 4500 |
| 18 | "교통카드 충전 5만원" | record_expense, transport, 50000 |
| 19 | "삭제해" | delete_last → 경고 확인 시트 |
| 20 | "안녕하세요" | unsupported → 폼 fallback |

**합격 기준**: 20개 중 17개 이상 올바른 파싱 (85%)

### 7-2. 엣지케이스 방어

- [ ] 모델 응답이 빈 문자열 → ParseException → 폼 fallback
- [ ] 모델 응답이 JSON이 아닌 자연어 → regex 추출 실패 → fallback
- [ ] 금액이 음수 → 0으로 보정 또는 모호 처리
- [ ] 날짜가 미래 → 경고 표시 ("미래 날짜입니다. 맞나요?")
- [ ] 모델 추론 타임아웃 (10초 초과) → ModelInferenceException
- [ ] 모델 파일 손상 → 재다운로드 유도

### 7-3. 성능 확인

- [ ] 모델 추론 시간: 3초 이내 (중급 기기 기준)
- [ ] 모델 파일 크기 확인 및 표시
- [ ] 추론 중 UI 프리징 없음 (별도 Isolate 또는 비동기 처리)
- [ ] 오프라인 상태에서 모델 추론 정상 동작

---

## 생성/수정 파일 요약

### 신규 생성 (10개)

| 파일 | 계층 | 역할 |
|------|------|------|
| `lib/core/utils/date_utils.dart` | Foundation | 한국어 상대 날짜 파서 |
| `lib/core/utils/amount_utils.dart` | Foundation | 한국어 금액 파서 |
| `lib/core/exceptions/app_exception.dart` | Foundation | 에이전트 예외 클래스 |
| `lib/services/model_download_service.dart` | Service | 모델 다운로드 관리 |
| `lib/services/ledger_agent_service.dart` | Service | 프롬프트 + 추론 + 파싱 |
| `lib/presentation/agent/agent_provider.dart` | State | 에이전트 상태관리 |
| `lib/presentation/agent/natural_language_input_bar.dart` | UI | 자연어 입력 바 |
| `lib/presentation/agent/agent_confirm_sheet.dart` | UI | 확인 바텀시트 |
| `lib/presentation/agent/agent_ambiguous_sheet.dart` | UI | 모호 확인 시트 |
| `lib/presentation/agent/model_download_indicator.dart` | UI | 다운로드 진행률 |

### 기존 수정 (2개)

| 파일 | 변경 내용 |
|------|-----------|
| `pubspec.yaml` | LiteRT-LM 의존성 추가 |
| `presentation/home/home_screen.dart` | 하단에 자연어 입력 바 추가 + AgentProvider 연결 |

---

## 위험 요소 및 대응

| 위험 | 대응 방안 |
|------|-----------|
| Gemma 1B 한국어 JSON 추출 정확도 부족 | Few-shot 예시 수 늘리기 + rule-based 후처리 보정 |
| LiteRT-LM Flutter 플러그인 미성숙 | 플러그인 문제 시 MethodChannel로 네이티브 직접 연동 |
| 모델 다운로드 실패 (네트워크 불안정) | 재시도 메커니즘 + 부분 다운로드 이어받기 |
| 추론 시간 과다 (저사양 기기) | 로딩 UI 표시 + 타임아웃 후 폼 fallback |
| 모델 출력을 eval/직접 API 전송 | 반드시 Flutter 앱에서 파싱 → 사용자 확인 → 저장 (절대 직행 금지) |
| 프롬프트에 현재 날짜 누락 | `buildPrompt`에서 `DateTime.now()` 필수 주입 — 코드 리뷰 체크 |
