# Ondevice Ledger Agent — 실전 구현 가이드

> 자연어로 입력하는 온디바이스 개인 가계부 (Flutter + Gemma + Hono + Turso)

---

## 목차

1. [프로젝트 목표 재정의](#1-프로젝트-목표-재정의)
2. [전체 구현 원칙](#2-전체-구현-원칙)
3. [MVP 범위](#3-mvp-범위)
4. [Step-by-step 구현 계획](#4-step-by-step-구현-계획)
5. [Flutter 앱 구조](#5-flutter-앱-구조)
6. [온디바이스 Gemma / LiteRT-LM 설계](#6-온디바이스-gemma--litert-lm-설계)
7. [Hono + Workers API 설계](#7-hono--workers-api-설계)
8. [Turso DB 설계](#8-turso-db-설계)
9. [Sync / Offline-first 설계](#9-sync--offline-first-설계)
10. [보안과 신뢰 경계](#10-보안과-신뢰-경계)
11. [추천 Repo 구조](#11-추천-repo-구조)
12. [개발 단계별 로드맵](#12-개발-단계별-로드맵)
13. [테스트 전략](#13-테스트-전략)
14. [가장 위험한 포인트](#14-가장-위험한-포인트)
15. [최종 추천](#15-최종-추천)
16. [바로 시작 체크리스트](#바로-시작-체크리스트)

---

## 1. 프로젝트 목표 재정의

### 이 앱이 정확히 무엇인지

자연어로 입력하는 **모바일 개인 가계부**다. 핵심은 두 가지다:

1. **정석 가계부**: 수입/지출 기록, 카테고리 분류, 날짜별/카테고리별 조회, 합계 계산
2. **온디바이스 NL 에이전트**: 사용자가 타이핑한 자연어 문장을 Gemma가 해석해서 구조화된 액션(insert/query/delete)으로 변환

두 기능은 **동등한 입력 방법**이다. 폼으로도 입력할 수 있고, 채팅으로도 입력할 수 있다. 에이전트가 가계부를 대체하는 게 아니라, 입력 레이어를 확장하는 것.

### 일반 가계부 기능과 에이전트 기능의 관계

```
[자연어 입력] → [Gemma on-device 해석] → [구조화된 intent payload]
                                                       ↓
[폼 직접 입력]  ──────────────────────────────→ [동일한 API endpoint]
                                                       ↓
                                              [Hono + Workers + Turso]
```

에이전트는 **프론트엔드의 스마트 파서**다. 서버 입장에서는 어디서 왔든 동일한 검증된 payload만 받는다.

### v1에서 하지 않을 것

| 제외 항목 | 이유 |
|-----------|------|
| 예산 설정 및 초과 알림 | 백엔드 복잡도 급증 |
| 영수증 사진 OCR | 기술 스택 추가, v2 |
| 반복 지출 자동 기록 | cron + edge function 필요, v2 |
| 다중 계좌/지갑 관리 | 스키마 복잡도, v2 |
| 가족/공유 가계부 | auth 복잡도 폭발 |
| 서버사이드 LLM 호출 | 비용, 레이턴시, 오프라인 불가 |
| 멀티턴 대화 컨텍스트 | v1에서는 단발 문장 해석만 |
| 커스텀 카테고리 관리 UI | 고정 카테고리 8개로 시작 |
| 데이터 내보내기(CSV/Excel) | v2 |

---

## 2. 전체 구현 원칙

### 각 기술의 역할

| 기술 | 역할 | 하지 않는 것 |
|------|------|-------------|
| **Flutter** | UI, 로컬 DB(SQLite), 오프라인 큐, Gemma 호출 | 비즈니스 로직 서버 역할 |
| **LiteRT-LM** | Gemma 모델 로딩/추론 런타임 | 네트워크 통신 |
| **Gemma (on-device)** | 자연어 → intent JSON 변환, 카테고리 추론 | 최종 실행 결정, 금액 계산 |
| **Hono + Workers** | REST API, 인증 검증, 입력 유효성 검사, 비즈니스 규칙 | 모델 추론 |
| **Turso** | 정규화된 ledger 데이터의 단일 소스(canonical DB) | 원문 utterance 1차 저장 |
| **Supabase Auth** | JWT 발급, 소셜 로그인, 사용자 관리 | 데이터 저장 |

### 온디바이스 vs 백엔드 책임 분리

**온디바이스(Flutter + Gemma)가 책임지는 것:**
- 자연어 파싱 및 intent 추출
- 위험 액션(삭제/대량 수정) 사용자 확인 UI
- 오프라인 시 임시 로컬 저장
- 낙관적 UI 업데이트 (sync 전에도 보여줌)
- 모델 결과 사용자에게 미리보기 제공 ("이렇게 기록할까요?")

**백엔드(Hono + Workers)가 책임지는 것:**
- JWT 검증 (모든 요청)
- 입력값 범위 검증 (금액, 날짜 등)
- 중복 insert 방지 (idempotency key)
- 소프트 삭제만 허용 (하드 삭제 없음)
- 감사 로그(audit log) 기록
- Turso에 최종 커밋

### 모델이 해도 되는 것 / 하면 안 되는 것

**해도 되는 것:**
- 텍스트에서 날짜, 금액, 메모, 카테고리 추출
- intent 분류 (record_expense / query_summary / delete_record / record_income / ambiguous)
- 카테고리 추론 ("스타벅스" → "식비/카페")
- 상대적 날짜 해석 ("어제", "지난주") → 앱이 현재 날짜 컨텍스트 주입

**절대 하면 안 되는 것:**
- 삭제를 직접 실행 결정 (반드시 사용자 확인 거침)
- 금액 계산/합산 (모델이 아닌 DB aggregate 사용)
- 인증/권한 판단
- "기록된 데이터가 있는지" 직접 조회 (DB 조회는 API가)

---

## 3. MVP 범위

### 반드시 넣을 기능

1. **이메일/소셜 로그인** (Supabase Auth)
2. **지출 기록** (날짜, 금액, 카테고리, 메모)
3. **날짜별 목록 조회** (홈 화면)
4. **월별 합계** (카테고리별)
5. **자연어 지출 기록** ("오늘 점심 12000원")
6. **자연어 조회** ("이번 달 식비 얼마야?")
7. **자연어 삭제** (확인 다이얼로그 필수)
8. **오프라인 입력 → 나중 sync**

### 일부러 뺄 기능

- **수입 기록**: v1에서는 지출만. 수입 추가하면 카테고리 체계가 2배로 복잡해짐.
- **카테고리 커스텀**: 고정 카테고리 8개로 시작. 사용자 정의는 v2.
- **통계/차트**: 숫자 텍스트로만 먼저. 차트 라이브러리는 나중에.
- **푸시 알림**: 백엔드 복잡도 급증. v2.
- **다크모드**: v1에서는 시스템 기본만.

### 왜 그렇게 잘라야 하는지

Flutter + LiteRT-LM 통합 자체가 이미 미지수다. 모델이 한국어 날짜/금액을 얼마나 잘 파싱하는지 검증도 안 됐다. **기술 불확실성이 가장 높은 부분(온디바이스 추론)에 먼저 집중**해야 한다. 기능을 많이 넣을수록 이 핵심 검증이 늦어진다.

---

## 4. Step-by-step 구현 계획

### Step 0: 기술 스택 검증 (기간: 3일)

**목표**: "이 스택이 실제로 작동하는가"를 최소한의 코드로 증명

**해야 할 일:**
- [ ] Flutter 프로젝트 생성, LiteRT-LM Flutter 패키지 연동
- [ ] Gemma 3 1B (int4 양자화) 모델 파일 다운로드 및 기기 로드 테스트
- [ ] 간단한 한국어 프롬프트 → JSON 출력 확인 ("오늘 점심 12000원" → `{"amount": 12000, "category": "식비"}`)
- [ ] Cloudflare Workers + Hono "Hello World" 배포
- [ ] Turso DB 생성, 테이블 1개 만들어서 Workers에서 연결
- [ ] Supabase 프로젝트 생성, Flutter에서 이메일 로그인 연동

**산출물:**
- Flutter 앱에서 Gemma가 실제로 응답하는 화면 (스크린샷)
- Workers에서 Turso로 insert/select 동작 확인 (curl 테스트)
- Supabase 로그인 → JWT 받기 성공

**완료 기준:**
- 기기(실기기 또는 에뮬레이터)에서 Gemma가 한국어 입력에 JSON을 뱉는다
- Workers API가 Turso에 데이터를 쓰고 읽는다
- JWT를 Workers 헤더로 보내서 검증이 통과한다

**흔한 실수:**
- Gemma 모델 파일을 Flutter assets에 번들하려는 시도 → 앱 용량 수백 MB 폭발. 대신 첫 실행 시 다운로드하는 방식 설계
- Workers에서 Turso 연결 시 환경변수 설정 빠뜨림 (`wrangler secret put`)
- LiteRT-LM API가 아직 불안정할 수 있음 → pub.dev 버전 고정, changelog 확인 필수

---

### Step 1: 백엔드 기본 API (기간: 4일)

**목표**: Hono API와 Turso 스키마 완성, 폼 입력으로 CRUD 가능한 상태

**해야 할 일:**
- [ ] Turso 테이블 스키마 확정 (Section 8 참고)
- [ ] Hono route 구조 잡기 (Section 7 참고)
- [ ] `POST /transactions` — 지출 기록
- [ ] `GET /transactions` — 목록 조회 (날짜 범위 필터)
- [ ] `GET /transactions/summary` — 월별 카테고리 합계
- [ ] `DELETE /transactions/:id` — 소프트 삭제
- [ ] 모든 route에 Supabase JWT 미들웨어 적용
- [ ] idempotency key 처리 로직 구현

**산출물:**
- 완성된 Workers 코드 (`/api` 폴더)
- Turso migration SQL 파일
- `curl` 또는 Hoppscotch로 전 endpoint 테스트한 결과

**완료 기준:**
- 인증 없는 요청 → 401
- 중복 idempotency key → 200 (동일 응답, 재처리 없음)
- 소프트 삭제 후 조회 → 목록에서 안 보임
- audit_logs 테이블에 모든 write 작업 기록됨

**흔한 실수:**
- `DELETE`를 하드 삭제로 구현 → 나중에 "실수로 지웠어요" 대응 불가
- idempotency key를 클라이언트에서 안 보내는 경우 서버가 그냥 처리 → 반드시 필수 헤더로 강제

---

### Step 2: Flutter 기본 가계부 UI (기간: 5일)

**목표**: 폼으로 지출 기록/조회/삭제가 되는 앱

**해야 할 일:**
- [ ] Flutter 앱 폴더 구조 잡기 (Section 5 참고)
- [ ] Supabase Auth 로그인 화면
- [ ] 홈 화면: 이번 달 총 지출 + 날짜별 거래 목록
- [ ] 지출 추가 폼 화면 (날짜, 금액, 카테고리 선택, 메모)
- [ ] 로컬 SQLite (`drift` 패키지) 세팅
- [ ] API 연동 (Dio + Riverpod)
- [ ] 삭제 스와이프 + 확인 다이얼로그

**산출물:**
- 로그인 → 홈 → 추가 → 삭제 플로우가 동작하는 앱 빌드

**완료 기준:**
- 오프라인 상태에서 앱 열어도 기존 데이터 보임 (로컬 캐시)
- 온라인 상태에서 추가한 데이터가 새로고침 없이 목록에 반영됨
- 삭제 시 확인 없이는 삭제 안 됨

**흔한 실수:**
- 상태관리를 나중에 "나중에 Riverpod으로 바꿀게" 하다가 `setState` 스파게티 → 처음부터 Riverpod
- 로컬 SQLite 없이 API만 바라보는 구조 → 오프라인 때 빈 화면

---

### Step 3: 온디바이스 에이전트 통합 (기간: 7일)

**목표**: 자연어 입력창에서 Gemma가 해석하고, 사용자 확인 후 API 호출

**해야 할 일:**
- [ ] 모델 다운로드 관리 서비스 구현 (첫 실행 시 다운로드 + 진행률 표시)
- [ ] `LedgerAgentService` 구현: 프롬프트 템플릿 + 모델 호출 + JSON 파싱
- [ ] intent schema 정의 (Section 6 참고)
- [ ] 확인 바텀시트 구현 ("이렇게 기록할까요?" 미리보기)
- [ ] 모호한 입력 처리 ("이거 식비야 교통비야?" 재질문 UI)
- [ ] 홈 화면 하단 자연어 입력 텍스트필드 추가

**산출물:**
- "오늘 점심 12000원 썼어" 입력 → 확인 시트 → 확인 → 기록 완료 플로우 동작

**완료 기준:**
- 금액, 날짜, 카테고리 추출 성공률 수동 테스트 20개 중 17개 이상
- 삭제 intent가 확인 없이는 절대 실행 안 됨
- 모델 응답이 파싱 불가한 경우 폼 입력으로 fallback 제공
- 오프라인 시에도 모델 추론 동작 (네트워크 불필요)

**흔한 실수:**
- 모델 출력을 그대로 eval하거나 직접 API로 전송 → 반드시 Flutter 앱에서 파싱 후 사용자에게 보여주고 확인 받기
- 프롬프트에 현재 날짜를 안 넣음 → "어제"가 뭔지 모델이 모름
- 모델 응답 파싱을 try/catch 없이 → 앱 크래시

---

### Step 4: 오프라인 Sync (기간: 4일)

**목표**: 오프라인에서 입력한 데이터가 온라인 복구 시 자동 sync

**해야 할 일:**
- [ ] 로컬 SQLite에 `sync_queue` 테이블 추가
- [ ] 네트워크 상태 감지 (connectivity_plus)
- [ ] 온라인 복구 시 큐 순서대로 API 호출
- [ ] idempotency key를 client에서 생성 (UUIDv7 추천)
- [ ] sync 실패 시 retry 로직 (exponential backoff, max 3회)
- [ ] sync 충돌 규칙 정의 (Section 9 참고)

**산출물:**
- 오프라인으로 3개 입력 → 온라인 전환 → 서버에 3개 모두 sync된 화면

**완료 기준:**
- 같은 idempotency key로 2번 sync → 서버에 1개만 기록
- sync 도중 앱 강제 종료 → 재시작 후 남은 큐 계속 처리
- sync 상태가 UI에 표시됨 (아이콘 또는 배지)

**흔한 실수:**
- sync 큐를 in-memory에만 둠 → 앱 재시작 시 유실
- 서버 응답 없이 로컬만 삭제 → 서버에는 데이터 남아있음

---

### Step 5: 프로덕션 하드닝 (기간: 3일)

**목표**: 실제 사용 가능한 수준의 안정성 확보

**해야 할 일:**
- [ ] Workers rate limiting (Cloudflare Rate Limiting 룰 적용)
- [ ] 에러 트래킹 (Sentry Flutter + Workers)
- [ ] 모델 다운로드 실패/재시도 UX
- [ ] 앱 시작 시 로컬 DB 마이그레이션 처리
- [ ] Turso 백업 설정 확인
- [ ] 릴리즈 빌드 테스트 (debug 모드와 다름)

---

## 5. Flutter 앱 구조

### 폴더 구조

```
lib/
├── main.dart
├── app.dart                    # MaterialApp, router 설정
├── core/
│   ├── constants/
│   │   ├── categories.dart     # 고정 카테고리 8개
│   │   └── api_endpoints.dart
│   ├── errors/
│   │   └── app_exception.dart
│   ├── network/
│   │   ├── dio_client.dart     # Dio 인스턴스, 인터셉터
│   │   └── connectivity.dart
│   └── utils/
│       ├── date_utils.dart     # 한국어 날짜 파싱 유틸
│       └── uuid.dart           # UUIDv7 생성
├── data/
│   ├── local/
│   │   ├── database.dart       # Drift DB 정의
│   │   ├── tables/
│   │   │   ├── transactions_table.dart
│   │   │   └── sync_queue_table.dart
│   │   └── dao/
│   │       ├── transactions_dao.dart
│   │       └── sync_queue_dao.dart
│   ├── remote/
│   │   ├── transaction_api.dart
│   │   └── auth_api.dart
│   └── repositories/
│       ├── transaction_repository.dart   # 로컬+리모트 조율
│       └── auth_repository.dart
├── domain/
│   ├── models/
│   │   ├── transaction.dart
│   │   └── category.dart
│   └── agent/
│       ├── ledger_intent.dart      # intent schema
│       └── ledger_agent_service.dart  # Gemma 호출
├── presentation/
│   ├── auth/
│   │   ├── login_screen.dart
│   │   └── login_provider.dart
│   ├── home/
│   │   ├── home_screen.dart
│   │   ├── home_provider.dart
│   │   └── widgets/
│   │       ├── transaction_list_tile.dart
│   │       ├── monthly_summary_card.dart
│   │       └── natural_language_input_bar.dart
│   ├── transaction/
│   │   ├── add_transaction_screen.dart
│   │   ├── add_transaction_provider.dart
│   │   └── widgets/
│   │       └── category_selector.dart
│   └── agent/
│       ├── agent_confirm_sheet.dart    # 확인 바텀시트
│       └── agent_ambiguous_sheet.dart  # 재질문 UI
└── services/
    ├── model_download_service.dart  # Gemma 모델 다운로드 관리
    └── sync_service.dart            # 오프라인 큐 sync
```

### 화면 구성

```
로그인 화면
└── 홈 화면 (메인)
    ├── 상단: 이번 달 총지출 + 월 선택
    ├── 중간: 날짜별 거래 목록 (스와이프 삭제)
    └── 하단: 자연어 입력바 (고정)
         └── [에이전트 확인 바텀시트]
              └── [모호한 경우 재질문 바텀시트]
지출 추가 화면 (폼, 자연어 입력 fallback 또는 직접 입력)
```

### 상태관리 추천

**Riverpod 2.x** (flutter_riverpod + riverpod_annotation)

이유: Drift DAO와 궁합이 좋음, 비동기 스트림 처리 편리, DI 내장, 테스트 쉬움. Bloc은 이 규모에서 보일러플레이트가 과하다.

```dart
// 이번 달 거래 목록 (Drift 스트림 → Riverpod)
@riverpod
Stream<List<Transaction>> monthlyTransactions(Ref ref, DateTime month) {
  final dao = ref.watch(transactionsDaoProvider);
  return dao.watchByMonth(month);
}

// 에이전트 상태
@riverpod
class AgentNotifier extends _$AgentNotifier {
  // idle / processing / confirm / ambiguous / error
}
```

### 로컬 저장소 / 오프라인 전략

| 패키지 | 용도 |
|--------|------|
| **drift** (sqlite3) | 트랜잭션 데이터, sync 큐 |
| **flutter_secure_storage** | JWT 토큰 |
| **shared_preferences** | 앱 설정, 마지막 sync 시각 |
| **파일시스템** | 다운로드된 Gemma 모델 파일 (`getApplicationSupportDirectory`) |

오프라인 전략: **로컬 우선 (local-first)**

1. 모든 write는 로컬 SQLite에 먼저
2. 네트워크 있으면 즉시 API 호출
3. 네트워크 없으면 sync_queue에 적재
4. connectivity_plus로 온라인 전환 감지 → 자동 sync

### 자연어 입력 UX 제안

홈 화면 하단에 **영구 고정 입력바** (Messenger 스타일):

```
[오늘 점심 12000원 썼어        ] [▶]
```

전송 후 → 확인 바텀시트 슬라이드업:

```
┌─────────────────────────────┐
│  이렇게 기록할까요?           │
│  📅 2024년 4월 8일 (오늘)    │
│  💰 12,000원                 │
│  🏷️ 식비                    │
│  📝 점심                     │
│                              │
│  [수정하기]      [확인 ✓]    │
└─────────────────────────────┘
```

삭제 intent인 경우 바텀시트 배경색을 주황색으로 경고.

---

## 6. 온디바이스 Gemma / LiteRT-LM 설계

### 모델의 정확한 역할 정의

Gemma는 **구조화된 정보 추출기**다. 챗봇이 아니다.

- **입력**: 사용자의 자연어 문장 + 컨텍스트 (오늘 날짜, 고정 카테고리 목록)
- **출력**: 정해진 JSON 스키마
- **역할**: 변환기(transformer). 결정자(decision maker) 아님.

모델에게 추론/실행/결정을 맡기지 않는다. 파싱만 시킨다.

### Intent / Action Schema

```dart
// lib/domain/agent/ledger_intent.dart

enum IntentType {
  recordExpense,
  recordIncome,
  queryBalance,
  deleteLast,
  deleteByDate,
  ambiguous,
  unsupported,
}

class LedgerIntent {
  final IntentType type;
  final double? amount;           // null if ambiguous
  final DateTime? date;           // null if ambiguous
  final String? categoryId;       // 고정 카테고리 ID
  final String? memo;
  final String? rawText;          // 원문 보존
  final double confidence;        // 0.0 ~ 1.0 (rule-based 계산)
  final String? ambiguityReason;  // 모호한 경우 이유
}
```

고정 카테고리 (8개):

```dart
// lib/core/constants/categories.dart
const kCategories = [
  Category(id: 'food',        label: '식비',      emoji: '🍽️'),
  Category(id: 'cafe',        label: '카페',      emoji: '☕'),
  Category(id: 'transport',   label: '교통비',    emoji: '🚌'),
  Category(id: 'shopping',    label: '쇼핑',      emoji: '🛍️'),
  Category(id: 'health',      label: '의료/건강', emoji: '💊'),
  Category(id: 'culture',     label: '문화/여가', emoji: '🎬'),
  Category(id: 'utility',     label: '생활비',    emoji: '🏠'),
  Category(id: 'etc',         label: '기타',      emoji: '📌'),
];
```

### 프롬프트 템플릿

```dart
String buildPrompt(String userInput, DateTime now) {
  return '''You are a Korean personal finance assistant. Extract structured data from the user's message.

Today is: ${DateFormat('yyyy-MM-dd (EEEE)', 'ko').format(now)}

Categories: food(식비), cafe(카페), transport(교통비), shopping(쇼핑), health(의료/건강), culture(문화/여가), utility(생활비), etc(기타)

User message: "$userInput"

Respond ONLY with a valid JSON object. No explanation. No markdown.

JSON schema:
{
  "intent": "record_expense|record_income|query_balance|delete_last|delete_by_date|ambiguous|unsupported",
  "amount": <number or null>,
  "date": "<YYYY-MM-DD or null>",
  "category_id": "<category id or null>",
  "memo": "<short memo or null>",
  "ambiguity_reason": "<string or null>"
}

Examples:
- "오늘 점심 12000원" → {"intent":"record_expense","amount":12000,"date":"2024-04-08","category_id":"food","memo":"점심","ambiguity_reason":null}
- "어제 스타벅스 5800원" → {"intent":"record_expense","amount":5800,"date":"2024-04-07","category_id":"cafe","memo":"스타벅스","ambiguity_reason":null}
- "지난주 식비 얼마나 썼어?" → {"intent":"query_balance","amount":null,"date":null,"category_id":"food","memo":null,"ambiguity_reason":null}
- "오늘 기록 삭제해줘" → {"intent":"delete_last","amount":null,"date":"2024-04-08","category_id":null,"memo":null,"ambiguity_reason":null}
''';
}
```

> **중요**: Few-shot 예시에 날짜를 실제로 계산해서 주입한다. 모델이 "어제"가 어제 날짜로 이미 변환된 예시를 보면 훨씬 잘 따라한다.

### 한국어 날짜/금액 파싱 대응

모델만 믿지 말고 **Flutter 앱에서 rule-based 전처리**를 먼저:

```dart
// lib/core/utils/date_utils.dart
DateTime? parseKoreanRelativeDate(String text, DateTime now) {
  if (text.contains('오늘')) return now;
  if (text.contains('어제')) return now.subtract(Duration(days: 1));
  if (text.contains('그저께') || text.contains('그제'))
    return now.subtract(Duration(days: 2));
  if (text.contains('지난주'))
    return now.subtract(Duration(days: now.weekday + 7));
  return null; // 못 찾으면 모델에 맡김
}

// lib/core/utils/amount_utils.dart
int? parseKoreanAmount(dynamic raw, String utterance) {
  if (raw is int) return raw;
  if (raw is double) return raw.round();
  // "만이천원" → 12000 등 한국어 숫자 변환
  final korMap = {'만': 10000, '천': 1000, '백': 100, '십': 10};
  // ... rule-based 변환 로직
}
```

### Risky Action 확인 플로우

```
사용자 입력: "오늘 기록 삭제해줘"
        ↓
모델 해석: intent = delete_by_date
        ↓
Flutter 앱: isRiskyAction(intent) == true 확인
        ↓
삭제 확인 바텀시트 (배경 오렌지색):
  "⚠️ 오늘(4월 8일) 기록 N건을 삭제할까요?
   삭제된 데이터는 복구하기 어렵습니다."
  [취소]  [삭제]
        ↓
사용자 확인 후에만 → API DELETE 호출
```

```dart
bool isRiskyIntent(IntentType type) {
  return type == IntentType.deleteLast ||
         type == IntentType.deleteByDate;
}
```

### Ambiguity 처리 방식

| 상황 | 처리 방법 |
|------|-----------|
| 카테고리만 모호 | 카테고리 선택 칩 UI 표시 |
| intent 자체가 모호 | 폼 입력 화면으로 fallback (파싱된 값 미리 채움) |
| 모델 출력 파싱 실패 | "이해하지 못했어요. 직접 입력해 주세요" → 폼 화면 |

confidence는 rule-based로 계산:
- amount 있으면 +0.4, date 있으면 +0.3, category 있으면 +0.3
- confidence < 0.7이면 확인 시트에서 강조 경고 표시

### 파싱 실패 방어 코드

```dart
ParsedAction? parseModelOutput(String rawOutput) {
  // 1차: JSON 블록 추출
  final jsonRegex = RegExp(r'\{[\s\S]*\}');
  final match = jsonRegex.firstMatch(rawOutput);
  if (match == null) return _fallbackAmountExtract(rawOutput);

  try {
    final map = jsonDecode(match.group(0)!);
    return ParsedAction.fromJson(map);
  } catch (e) {
    return _fallbackAmountExtract(rawOutput);
  }
}

ParsedAction? _fallbackAmountExtract(String text) {
  final amountRegex = RegExp(r'(\d[\d,]*)원');
  final match = amountRegex.firstMatch(text);
  if (match != null) {
    return ParsedAction(
      intent: LedgerIntent.unclear,
      amount: int.tryParse(match.group(1)!.replaceAll(',', '')),
      confidence: 0.3,
      ambiguousFields: ['category', 'date'],
    );
  }
  return null;
}
```

---

## 7. Hono + Workers API 설계

### Route 구조

```
apps/api/
├── src/
│   ├── index.ts              # Hono 앱 진입점
│   ├── middleware/
│   │   ├── auth.ts           # Supabase JWT 검증
│   │   └── idempotency.ts    # idempotency key 처리
│   ├── routes/
│   │   ├── transactions.ts
│   │   └── summary.ts
│   ├── db/
│   │   ├── client.ts         # Turso 클라이언트
│   │   └── queries.ts
│   └── validators/
│       └── transaction.ts    # Zod 스키마
├── migrations/
│   ├── 001_initial.sql
│   └── 002_audit_log.sql
└── wrangler.toml
```

### Endpoint 목록

| Method | Path | 설명 |
|--------|------|------|
| `POST` | `/api/transactions` | 지출 기록 |
| `GET` | `/api/transactions` | 목록 조회 (`?month=2024-04`) |
| `GET` | `/api/transactions/summary` | 월별 카테고리 합계 |
| `DELETE` | `/api/transactions/:id` | 소프트 삭제 |
| `GET` | `/api/health` | 헬스체크 (인증 불필요) |

### Request/Response 예시

**POST /api/transactions**

```json
// Headers:
// Authorization: Bearer <jwt>
// Idempotency-Key: 01906e2a-7d3b-7000-8000-abcdef123456

// Request body:
{
  "id": "01906e2a-7d3b-7000-8000-abcdef123456",
  "amount": 12000,
  "date": "2024-04-08",
  "category_id": "food",
  "memo": "점심",
  "raw_utterance": "오늘 점심 12000원 썼어",
  "source": "agent"
}

// Response 201:
{
  "id": "01906e2a-7d3b-7000-8000-abcdef123456",
  "created_at": "2024-04-08T12:34:56Z"
}

// Response 200 (중복 idempotency key):
{
  "id": "01906e2a-7d3b-7000-8000-abcdef123456",
  "created_at": "2024-04-08T12:34:56Z",
  "duplicate": true
}
```

**GET /api/transactions/summary?month=2024-04**

```json
{
  "month": "2024-04",
  "total": 156000,
  "by_category": [
    { "category_id": "food", "amount": 89000, "count": 12 },
    { "category_id": "cafe", "amount": 34000, "count": 6 }
  ]
}
```

### Validation 전략

```typescript
// src/validators/transaction.ts
import { z } from 'zod';

const VALID_CATEGORIES = [
  'food', 'cafe', 'transport', 'shopping',
  'health', 'culture', 'utility', 'etc'
] as const;

export const createTransactionSchema = z.object({
  id: z.string().uuid(),
  amount: z.number().positive().max(100_000_000), // 최대 1억
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  category_id: z.enum(VALID_CATEGORIES),
  memo: z.string().max(200).optional(),
  raw_utterance: z.string().max(500).optional(),
  source: z.enum(['form', 'agent']),
});
```

### Idempotency 전략

```typescript
// src/middleware/idempotency.ts
export const idempotencyMiddleware = async (c: Context, next: Next) => {
  const key = c.req.header('Idempotency-Key');
  if (!key) return c.json({ error: 'Idempotency-Key header required' }, 400);

  const body = await c.req.json();
  if (body.id !== key) {
    return c.json({ error: 'Idempotency-Key must match transaction id' }, 400);
  }
  await next();
};
```

Turso에서 `ON CONFLICT(id) DO NOTHING`으로 중복 insert 원천 방지.

### Auth Verification 전략

```typescript
// src/middleware/auth.ts
export const authMiddleware = async (c: Context, next: Next) => {
  const authHeader = c.req.header('Authorization');
  if (!authHeader?.startsWith('Bearer ')) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  const token = authHeader.slice(7);
  // Workers에서는 jose 라이브러리로 Supabase JWT 검증
  const { payload } = await jwtVerify(token, supabaseJwtSecret);

  c.set('userId', payload.sub as string);
  await next();
};
```

모든 DB 쿼리에서 `WHERE user_id = ?`로 row-level 격리.

---

## 8. Turso DB 설계

### 테이블 스키마

```sql
-- migrations/001_initial.sql

CREATE TABLE IF NOT EXISTS transactions (
  id            TEXT    PRIMARY KEY,           -- UUIDv7 (client-generated)
  user_id       TEXT    NOT NULL,              -- Supabase auth.users.id
  amount        INTEGER NOT NULL,              -- 원 단위 정수 (소수점 없음)
  date          TEXT    NOT NULL,              -- YYYY-MM-DD
  category_id   TEXT    NOT NULL,
  memo          TEXT,
  raw_utterance TEXT,                          -- 원문 자연어 (보존용)
  source        TEXT    NOT NULL DEFAULT 'form', -- 'form' | 'agent'
  deleted_at    TEXT,                          -- soft delete: ISO8601 or NULL
  created_at    TEXT    NOT NULL DEFAULT (datetime('now')),
  updated_at    TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_transactions_user_date
  ON transactions(user_id, date)
  WHERE deleted_at IS NULL;

CREATE INDEX idx_transactions_user_category
  ON transactions(user_id, category_id, date)
  WHERE deleted_at IS NULL;

-- 감사 로그
CREATE TABLE IF NOT EXISTS audit_logs (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id    TEXT    NOT NULL,
  action     TEXT    NOT NULL,    -- 'insert' | 'soft_delete'
  record_id  TEXT    NOT NULL,
  payload    TEXT,                -- JSON snapshot
  created_at TEXT    NOT NULL DEFAULT (datetime('now'))
);
```

### 설계 결정 사항

**금액은 정수로 저장**: 이 앱은 KRW만 다룬다. REAL/FLOAT 사용 금지. 부동소수점 버그를 원천 차단.

**Soft Delete 전략**:
```sql
-- 삭제
UPDATE transactions
SET deleted_at = datetime('now'), updated_at = datetime('now')
WHERE id = ? AND user_id = ?;

-- 조회 (삭제된 거 제외)
SELECT * FROM transactions
WHERE user_id = ? AND date LIKE '2024-04%' AND deleted_at IS NULL
ORDER BY date DESC, created_at DESC;
```

하드 삭제 endpoint는 만들지 않는다. 운영 중 실수 복구, 분쟁 대응을 위해 audit_logs와 함께 영구 보존.

**중복 방지**:
```sql
INSERT INTO transactions (id, user_id, amount, date, category_id, memo, raw_utterance, source)
VALUES (?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO NOTHING;
```

**원문 Utterance 보존**: `raw_utterance` 컬럼에 사용자의 원본 문장 저장. 이유:
1. 모델 파싱 틀렸을 때 디버깅
2. 나중에 더 좋은 모델로 재파싱 가능
3. 사용자 분쟁 대응

---

## 9. Sync / Offline-first 설계

### 로컬 SQLite sync_queue 테이블

```sql
CREATE TABLE sync_queue (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  operation        TEXT    NOT NULL,              -- 'insert' | 'delete'
  record_id        TEXT    NOT NULL,              -- transaction id
  payload          TEXT    NOT NULL,              -- JSON
  idempotency_key  TEXT    NOT NULL,
  status           TEXT    NOT NULL DEFAULT 'pending', -- 'pending' | 'failed'
  retry_count      INTEGER NOT NULL DEFAULT 0,
  created_at       TEXT    NOT NULL DEFAULT (datetime('now'))
);
```

### 오프라인 처리 흐름

```
사용자 입력 (오프라인)
        ↓
1. 로컬 SQLite transactions 테이블에 즉시 insert (낙관적 저장)
2. sync_queue에 operation 적재
3. UI에 "오프라인 저장됨" 표시 (작은 아이콘)
```

### Sync 서비스

```dart
// lib/services/sync_service.dart
class SyncService {
  Future<void> processQueue() async {
    final pending = await _syncQueueDao.getPending(limit: 10);

    for (final item in pending) {
      try {
        await _processSingleItem(item);
        await _syncQueueDao.delete(item.id);
      } catch (e) {
        if (item.retryCount >= 3) {
          await _syncQueueDao.markFailed(item.id);
          // 사용자에게 "동기화 실패" 알림
        } else {
          await _syncQueueDao.incrementRetry(item.id);
        }
      }
    }
  }
}
```

### Client-generated ID

**UUIDv7 사용** (시간 정렬 가능). 이유:
- 서버 응답 없이도 로컬에서 ID 확정 가능
- sync 시 중복 방지 기준이 됨
- Turso에서 정렬 인덱스로도 활용 가능

```dart
// lib/core/utils/uuid.dart
import 'package:uuid/uuid.dart';
String generateId() => Uuid().v7();
```

### Conflict Handling 규칙

**v1 단순 규칙: 서버 데이터가 항상 우선 (server-wins)**

| 시나리오 | 처리 |
|----------|------|
| 로컬 insert + 서버에 없음 | 서버에 insert (정상) |
| 로컬 insert + 서버에 이미 있음 | `ON CONFLICT DO NOTHING` → 무시 |
| 로컬 delete + 서버에 없음 | 이미 삭제된 것으로 간주, 정상 종료 |

### Retry 정책

```dart
Duration getRetryDelay(int retryCount) {
  return Duration(seconds: [5, 30, 120][retryCount.clamp(0, 2)]);
}
```

max 3회 재시도. 실패 시 사용자에게 배너 표시. 자동 삭제 금지.

---

## 10. 보안과 신뢰 경계

### 기기에 남는 데이터

| 데이터 | 저장 위치 | 암호화 여부 |
|--------|-----------|------------|
| JWT 토큰 | flutter_secure_storage | OS Keychain (암호화됨) |
| 거래 데이터 | SQLite (Drift) | 기본 암호화 없음 (v2에서 SQLCipher 검토) |
| Gemma 모델 파일 | 파일시스템 | 없음 |
| sync 큐 | SQLite | 없음 |

### 서버로 가는 데이터

- JWT (Bearer 토큰)
- 거래 데이터 (금액, 날짜, 카테고리, 메모)
- `raw_utterance` (원문 자연어) ← Privacy Policy 명시 필요

### 예상 실수/오작동 및 대응

| 오작동 | 대응 |
|--------|------|
| 모델이 금액을 다르게 파싱 ("12,000원" → 12) | 확인 시트에서 사용자 확인 필수 |
| 모델이 날짜를 틀리게 파싱 | 확인 시트에서 날짜 명시, 수정 가능 |
| 모델이 삭제 intent를 record로 분류 | 확인 시트에서 취소 가능 |
| sync 중 앱 강제 종료 | 큐를 SQLite에 저장, 재시작 후 이어서 처리 |
| 동일 데이터 이중 insert | idempotency key + `ON CONFLICT DO NOTHING` |

### 모델 Hallucination 피해 최소화 3원칙

1. **확인 필수**: 모든 write 액션은 사용자 확인 후 실행
2. **소프트 삭제만**: 하드 삭제 없음, 복구 가능
3. **서버 재검증**: 서버가 독립적으로 Zod 검증, 모델 출력을 신뢰하지 않음

---

## 11. 추천 Repo 구조

**Monorepo 추천** (solo builder에게 최적)

```
ondevice-ledger-agent/
├── apps/
│   ├── mobile/               # Flutter 앱
│   │   ├── lib/
│   │   ├── test/
│   │   ├── pubspec.yaml
│   │   └── android/ ios/
│   └── api/                  # Hono + Workers
│       ├── src/
│       ├── test/
│       ├── package.json
│       └── wrangler.toml
├── migrations/               # Turso SQL 파일
│   ├── 001_initial.sql
│   └── 002_audit_log.sql
├── docs/
│   ├── api.md
│   └── agent-prompts.md      # 프롬프트 버전 관리
├── scripts/
│   ├── setup.sh
│   └── migrate.sh
├── .github/
│   └── workflows/
│       ├── api-deploy.yml    # Workers 자동 배포
│       └── flutter-test.yml  # Flutter 테스트
└── README.md
```

> `packages/shared-types`는 v1에서 만들지 않는다. Flutter ↔ TypeScript 타입 자동 공유는 오버엔지니어링. JSON 스키마를 `docs/api.md`로만 관리.

---

## 12. 개발 단계별 로드맵

### Phase 0: 기술 검증 (Week 1)

**목표**: 스택이 실제로 동작하는지 확인. 코드를 버려도 됨.

**구체적 목표**:
- Flutter에서 Gemma 3 1B (int4)로 "오늘 커피 4500원" → JSON 출력 확인
- Workers에서 Turso로 transaction insert/select 동작
- Supabase JWT → Workers 검증 통과

**주요 리스크**:
- LiteRT-LM Flutter 패키지 Android/iOS 안정성 불확실
- Gemma의 한국어 JSON 출력 품질 불확실
- Workers ↔ Turso 연결 latency

**종료 기준**: 위 3가지 실제 동작 스크린샷/curl 결과 확보

---

### Phase 1: 기본 가계부 (Week 2-3)

**목표**: 폼으로 CRUD 가능한 앱

**리스크**: 로컬 ↔ 서버 상태 불일치 버그

**종료 기준**: 폼으로 10개 기록, 삭제 2개, 재시작 후 데이터 유지

---

### Phase 2: 온디바이스 자연어 입력 (Week 3-4)

**목표**: 자연어 입력 → 확인 → 저장 플로우

**주요 리스크**:
- 모델 추론 속도가 모바일에서 3초 이상 걸릴 수 있음
- Gemma 한국어 파싱 정확도가 기대 이하일 수 있음

**종료 기준**: 수동 테스트 20문장 중 17개 정확 파싱

---

### Phase 3: Sync 안정화 (Week 5)

**목표**: 오프라인 입력 → 온라인 복구 → 정확한 sync

**리스크**: 이중 sync 버그, 큐 유실

**종료 기준**: 오프라인 5개 입력 → 온라인 전환 → 서버에 정확히 5개 (중복 없음)

---

### Phase 4: 프로덕션 하드닝 (Week 6)

**목표**: 실 사용 가능한 안정성

**주요 리스크**: Gemma 모델 파일 앱스토어 배포 정책 (용량, 런타임 다운로드 규정)

**종료 기준**: 1주일 실 사용 후 크래시 제로

---

## 13. 테스트 전략

### Unit Test

```dart
// test/agent/ledger_agent_service_test.dart
void main() {
  group('LedgerAgentService - JSON parsing', () {
    test('valid JSON output parses correctly', () {
      const jsonStr = '{"intent":"record_expense","amount":12000,"date":"2024-04-08","category_id":"food","memo":"점심","ambiguity_reason":null}';
      final intent = LedgerIntent.fromJson(jsonDecode(jsonStr));
      expect(intent.type, IntentType.recordExpense);
      expect(intent.amount, 12000.0);
    });

    test('malformed JSON returns unsupported intent', () {
      const broken = 'Sorry, I cannot help with that.';
      final intent = LedgerAgentService.parseModelOutput(broken);
      expect(intent?.type, IntentType.unsupported);
    });
  });
}
```

### Sync Test

```dart
// test/sync/sync_service_test.dart
test('offline insert syncs after network recovery', () async {
  // 1. 네트워크 off 시뮬레이션
  // 2. 거래 3개 로컬 저장
  // 3. 네트워크 on 전환
  // 4. sync 실행
  // 5. Mock API가 3번 호출됐는지 확인
  // 6. sync_queue가 비었는지 확인
});

test('duplicate sync does not create duplicates', () async {
  // 동일 idempotency key로 2번 sync
  // 서버에서 1번만 insert됐는지 확인
});
```

### Risky Action Test

```dart
test('delete intent requires user confirmation', () async {
  final intent = LedgerIntent(type: IntentType.deleteLast, ...);
  expect(isRiskyIntent(intent.type), true);
  // confirmationSheet가 표시됐는지 위젯 테스트
});

test('delete does not execute without confirmation', () async {
  // 확인 다이얼로그에서 취소 탭
  // API DELETE 호출이 없어야 함
  verifyNever(mockApi.deleteTransaction(any));
});
```

### Parsing Edge Case Test

```dart
// test/agent/parsing_edge_cases_test.dart
final testCases = [
  ('오늘 점심 12000원',  12000, 'food'),
  ('어제 스타벅스 5800원', 5800, 'cafe'),
  ('지하철 1400원',      1400, 'transport'),
  ('만이천원 점심',      12000, 'food'),    // 한글 금액
  ('12,000원 식비',     12000, 'food'),    // 쉼표 포함
  ('커피 오천원',        5000, 'cafe'),
];
```

### Offline/Online 전환 테스트

```dart
test('app shows cached data when offline', () async {
  // 온라인에서 데이터 3개 로드
  // 네트워크 off
  // 앱 재시작
  // 3개 데이터가 여전히 보여야 함 (로컬 캐시)
});
```

---

## 14. 가장 위험한 포인트

### 1. Flutter + LiteRT-LM 통합 난이도 ★★★★★

LiteRT-LM Flutter 패키지는 아직 성숙하지 않다. Android와 iOS 동시 지원, 특히 iOS의 GPU delegate 설정이 까다롭다.

**대응**: Phase 0에서 실기기로 반드시 먼저 검증. 모델 로딩을 앱 시작과 분리해서 백그라운드 preload 처리. 로딩 완료 전에는 폼 입력 경로를 먼저 노출.

---

### 2. 한국어 자연어 처리 난점 ★★★★☆

Gemma 3 1B int4는 한국어 이해 능력이 제한적이다. "만이천원", "지난주 화요일", "밥값", "편의점" 같은 표현에서 hallucination이 나올 수 있다.

**대응**:
- 금액과 날짜는 rule-based 전처리를 먼저 적용하고 그 결과를 프롬프트에 주입
- 더 큰 모델(Gemma 3 4B)과 비교 실험
- Few-shot 예시를 풍부하게

---

### 3. 중복 Insert 버그 ★★★★☆

네트워크 타임아웃 후 재시도, sync 중 앱 재시작 등 다양한 경로로 중복이 생긴다. 금액 데이터의 중복은 사용자 신뢰를 크게 훼손한다.

**대응**: UUIDv7 client-side ID + `ON CONFLICT DO NOTHING` + sync_queue 처리와 삭제가 트랜잭션으로 묶여야 함.

---

### 4. 삭제/수정 안전성 ★★★★☆

자연어 삭제 명령이 너무 쉽게 실행되면 데이터 손실. "오늘 기록 다 지워줘"가 실수로 입력될 경우가 있다.

**대응**: 소프트 삭제 강제, 삭제 전 확인 필수(건너뛸 수 없음).

---

### 5. 너무 빨리 과한 설계를 하는 문제 ★★★★★

Gemma가 한국어를 제대로 파싱하는지 확인도 안 하고 sync 아키텍처, 멀티턴 대화, 카테고리 ML 분류기를 만들기 시작하는 것. **가장 큰 리스크다.**

**대응**: Phase 0 결과가 나오기 전까지 코드를 최소화. 모델이 실제로 작동한다는 증거를 먼저 얻는다.

---

## 15. 최종 추천

### 내가 가장 먼저 만들어야 할 것

**Flutter 앱에서 Gemma가 "오늘 점심 12000원"을 `{"intent":"record_expense","amount":12000,...}`으로 파싱하는 것.**

이게 동작한다는 증명이 없으면 다른 모든 것은 의미가 없다. 3일 안에 이것부터.

### 절대 초반에 하지 말아야 할 것

- 멀티턴 대화 컨텍스트 관리
- 서버사이드 Gemma API 호출 설계
- 카테고리 ML 자동 분류 모델 학습
- 통계 차트 UI (FL Chart 등 설치)
- 반복 지출 자동 기록
- 소셜 공유 기능
- 영수증 OCR

### 2주 MVP 플랜

| 일자 | 작업 |
|------|------|
| Day 1-2 | Phase 0 — LiteRT-LM + Gemma 한국어 JSON 출력 검증 |
| Day 3 | Phase 0 — Workers + Turso + Supabase JWT 연동 확인 |
| Day 4-5 | Phase 1 — Turso 스키마 + Hono API 완성 |
| Day 6-7 | Phase 1 — Flutter 기본 UI (로그인 + 목록 + 폼) |
| Day 8-9 | Phase 2 — LedgerAgentService + 프롬프트 튜닝 |
| Day 10 | Phase 2 — 확인 바텀시트 UI |
| Day 11 | Phase 2 — 삭제 확인 플로우 |
| Day 12 | Phase 3 — 기본 sync_queue |
| Day 13 | 버그 수정 + 엣지케이스 처리 |
| Day 14 | 실 사용 테스트 + Sentry 설치 |

**2주 MVP 종료 기준**: 자연어로 지출 입력, 조회, 삭제가 되고, 오프라인에서도 입력 가능하며, 온라인 전환 시 sync된다.

### 6주 현실 플랜

| 주차 | 작업 |
|------|------|
| Week 1 | Phase 0 + Phase 1 (기술 검증 + 기본 API) |
| Week 2 | Phase 1 완성 + Phase 2 시작 (Flutter UI + 에이전트 시작) |
| Week 3 | Phase 2 완성 (에이전트 통합 + 확인 플로우) |
| Week 4 | Phase 3 (sync 안정화) |
| Week 5 | 엣지케이스 수정 + 파싱 품질 개선 (프롬프트 튜닝) |
| Week 6 | Phase 4 (프로덕션 하드닝 + 배포) |

6주 후: App Store / Play Store 제출 가능한 수준.

---

## 바로 시작 체크리스트

다음 10개를 순서대로 실행하라:

- [ ] **1.** `apps/mobile/` Flutter 프로젝트 생성 — `flutter create --org com.yourname --project-name ledger_agent apps/mobile`
- [ ] **2.** LiteRT-LM Flutter 패키지 `pubspec.yaml`에 추가 후 실기기에서 첫 실행 확인
- [ ] **3.** Gemma 3 1B int4 모델 파일 다운로드 (Google AI Edge 또는 Hugging Face)
- [ ] **4.** Flutter에서 Gemma 호출 최소 구현 — "오늘 점심 12000원" 입력 → JSON 문자열 출력 확인 (`print()`로)
- [ ] **5.** `apps/api/` Hono 프로젝트 생성 — `npm create hono@latest apps/api` → Cloudflare Workers 템플릿 선택
- [ ] **6.** Turso DB 생성 + `001_initial.sql` 실행 — `turso db create ledger-db && turso db shell ledger-db < migrations/001_initial.sql`
- [ ] **7.** Workers에서 Turso `POST /api/transactions` 구현 — Zod 검증 + insert + `ON CONFLICT DO NOTHING` + Supabase JWT 미들웨어
- [ ] **8.** `wrangler deploy`로 Workers 배포 후 `curl`로 전 endpoint 테스트
- [ ] **9.** Flutter에 Supabase Auth 연동 — `supabase_flutter` 패키지, 이메일 로그인, JWT 저장
- [ ] **10.** Flutter에서 Workers API `POST /api/transactions` 호출 성공 확인 — 로그인 → JWT → API → Turso 저장 end-to-end 동작

> 이 10개가 완료되면 전체 기술 스택이 검증된 것이다. 그때부터 기능을 쌓아라.
