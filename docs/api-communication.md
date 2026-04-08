# API 데이터 명세

프론트엔드(Flutter)와 백엔드(Cloudflare Workers) 사이에서 주고받는 데이터 필드, 타입, 용도를 정리합니다.

---

## 통신 대상

Flutter 앱은 두 곳과 직접 통신합니다.

```
Flutter App
  ├─ Supabase         (인증 전용, Supabase SDK로 직접 통신)
  └─ Cloudflare Workers API  (거래 데이터 CRUD, DIO로 HTTP REST)
```

### Supabase — 인증 전용

Flutter SDK(`supabase_flutter`)를 통해 직접 호출합니다. 백엔드 API를 거치지 않습니다.

| 용도 | 호출 | 파일 |
|------|------|------|
| OTP 이메일 발송 | `auth.signInWithOtp(email)` | `login_screen.dart` |
| 로그인 상태 감지 | `auth.onAuthStateChange` | `main.dart` |
| JWT 꺼내기 | `auth.currentSession.accessToken` | `dio_client.dart` |

### Cloudflare Workers — 데이터 CRUD

DIO HTTP 클라이언트로 호출합니다. 모든 요청에 위에서 꺼낸 JWT를 `Authorization: Bearer` 헤더로 첨부합니다.

백엔드는 Supabase DB에 직접 접근하지 않습니다. `SUPABASE_JWT_SECRET`으로 토큰 서명만 검증하고, 실제 데이터는 Turso DB(libSQL)에서 읽고 씁니다.

---

## 공통 규칙

- 모든 요청에 `Authorization: Bearer <JWT>` 헤더 필요 (`GET /api/health` 제외)
- 요청/응답 본문은 모두 JSON
- 금액(`amount`)은 원화 정수 — 부동소수점 쓰지 않음
- 날짜(`date`)는 `YYYY-MM-DD` 문자열
- ID는 클라이언트가 UUID v4로 생성해서 전송

---

## POST /api/transactions — 거래 생성

### 요청 헤더

| 헤더 | 타입 | 필수 | 용도 |
|------|------|------|------|
| `Authorization` | `Bearer <JWT>` | 필수 | 사용자 인증, user_id 추출 |
| `Idempotency-Key` | `string (UUID)` | 필수 | 네트워크 재시도 시 중복 생성 방지. body의 `id`와 동일한 값이어야 함 |

### 요청 Body

| 필드 | 타입 | 필수 | 용도 |
|------|------|------|------|
| `id` | `string (UUID v4)` | 필수 | 클라이언트가 생성한 거래 고유 ID. 서버에서 별도 생성하지 않음 |
| `amount` | `number` (양의 정수, 최대 100,000,000) | 필수 | 지출 금액 (원) |
| `date` | `string` (`YYYY-MM-DD`) | 필수 | 지출 발생 날짜 |
| `category_id` | `string` (enum) | 필수 | 지출 카테고리. 아래 enum 참고 |
| `memo` | `string` (최대 200자) | 선택 | 사용자가 직접 입력한 메모 |
| `raw_utterance` | `string` (최대 500자) | 선택 | 에이전트 모드에서 사용자가 말한 원문 자연어 |
| `source` | `"form" \| "agent"` | 필수 | 거래가 어떤 경로로 입력됐는지 — 폼 직접 입력 또는 AI 에이전트 |

**`category_id` 허용 값**

| 값 | 의미 |
|----|------|
| `food` | 식사 |
| `cafe` | 카페 |
| `transport` | 교통 |
| `shopping` | 쇼핑 |
| `health` | 건강 |
| `culture` | 문화 |
| `utility` | 공과금 |
| `etc` | 기타 |

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "amount": 5000,
  "date": "2024-04-08",
  "category_id": "food",
  "memo": "점심 식사",
  "raw_utterance": "오늘 점심 오천원 썼어",
  "source": "agent"
}
```

### 응답 Body

**성공 — 새로 생성됨 (HTTP 201)**

| 필드 | 타입 | 용도 |
|------|------|------|
| `id` | `string (UUID)` | 생성된 거래 ID (요청의 `id`와 동일) |
| `message` | `string` | 처리 결과 설명 |

```json
{ "id": "550e8400-...", "message": "Transaction created" }
```

**성공 — 중복 요청 (HTTP 200)**

| 필드 | 타입 | 용도 |
|------|------|------|
| `id` | `string (UUID)` | 이미 존재하는 거래 ID |
| `duplicate` | `boolean` | 중복 요청임을 알림. 클라이언트는 이 경우도 성공으로 처리 |

```json
{ "id": "550e8400-...", "duplicate": true }
```

**오류 (HTTP 400 / 500)**

| 필드 | 타입 | 용도 |
|------|------|------|
| `error` | `string` | 오류 메시지 |
| `details` | `object` (선택) | Zod 검증 실패 시 필드별 상세 오류 |

```json
{ "error": "Validation failed", "details": { "amount": "Expected number, received string" } }
```

---

## GET /api/transactions — 거래 목록 조회

### 요청 Query Parameter

| 파라미터 | 타입 | 필수 | 용도 |
|---------|------|------|------|
| `month` | `string` (`YYYY-MM`) | 선택 | 조회할 월. 생략 시 전체 기간 반환 |

### 응답 Body

| 필드 | 타입 | 용도 |
|------|------|------|
| `data` | `Transaction[]` | 거래 배열 |

**Transaction 객체**

| 필드 | 타입 | 용도 |
|------|------|------|
| `id` | `string (UUID)` | 거래 고유 ID |
| `user_id` | `string` | Supabase 사용자 ID — 본인 데이터만 반환됨 |
| `amount` | `number` | 지출 금액 (원) |
| `date` | `string` (`YYYY-MM-DD`) | 지출 날짜 |
| `category_id` | `string` | 카테고리 |
| `memo` | `string \| null` | 메모 |
| `raw_utterance` | `string \| null` | 에이전트 입력 원문 |
| `source` | `"form" \| "agent"` | 입력 경로 |
| `deleted_at` | `string \| null` | 삭제 시각 (ISO8601). null이면 유효한 거래 |
| `created_at` | `string` (ISO8601) | 생성 시각 |
| `updated_at` | `string` (ISO8601) | 마지막 수정 시각 |

> `deleted_at`이 non-null인 행은 소프트 삭제된 것으로, 백엔드가 필터링하여 응답에서 제외합니다.

```json
{
  "data": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "user_id": "auth-user-uuid",
      "amount": 5000,
      "date": "2024-04-08",
      "category_id": "food",
      "memo": "점심 식사",
      "raw_utterance": null,
      "source": "form",
      "deleted_at": null,
      "created_at": "2024-04-08T12:00:00",
      "updated_at": "2024-04-08T12:00:00"
    }
  ]
}
```

---

## GET /api/transactions/summary — 월별 요약 조회

### 요청 Query Parameter

| 파라미터 | 타입 | 필수 | 용도 |
|---------|------|------|------|
| `month` | `string` (`YYYY-MM`) | 필수 | 요약할 월 |

### 응답 Body

| 필드 | 타입 | 용도 |
|------|------|------|
| `month` | `string` (`YYYY-MM`) | 요청한 월 |
| `total` | `number` | 해당 월 전체 지출 합계 (원) |
| `by_category` | `CategorySummary[]` | 카테고리별 집계 |

**CategorySummary 객체**

| 필드 | 타입 | 용도 |
|------|------|------|
| `category_id` | `string` | 카테고리 |
| `amount` | `number` | 해당 카테고리 지출 합계 (원) |
| `count` | `number` | 해당 카테고리 거래 건수 |

```json
{
  "month": "2024-04",
  "total": 150000,
  "by_category": [
    { "category_id": "food", "amount": 80000, "count": 8 },
    { "category_id": "transport", "amount": 70000, "count": 5 }
  ]
}
```

---

## DELETE /api/transactions/:id — 거래 삭제

### 요청 URL Parameter

| 파라미터 | 타입 | 용도 |
|---------|------|------|
| `id` | `string (UUID)` | 삭제할 거래 ID |

응답 Body 없이 상태 코드로만 결과를 전달합니다.

**성공 (HTTP 200)**
```json
{ "message": "Transaction deleted" }
```

**해당 ID 없음 (HTTP 404)**
```json
{ "error": "Transaction not found" }
```

---

## GET /api/health — 헬스체크

인증 불필요. 서버 동작 확인용.

**응답 (HTTP 200)**

| 필드 | 타입 | 용도 |
|------|------|------|
| `status` | `"ok"` | 서버 정상 동작 여부 |
| `timestamp` | `string` (ISO8601) | 서버 현재 시각 |

```json
{ "status": "ok", "timestamp": "2024-04-08T00:00:00.000Z" }
```

---

## 오류 응답 공통 구조

| HTTP 상태 | 원인 | `error` 값 예시 |
|----------|------|-----------------|
| `400` | Zod 검증 실패, `Idempotency-Key` 누락/불일치 | `"Validation failed"` |
| `401` | JWT 없음 또는 만료 | `"Unauthorized"` |
| `404` | 해당 ID의 거래 없음 | `"Transaction not found"` |
| `500` | DB 오류 등 서버 내부 오류 | `"Internal server error"` |

---

## 필드 타입 대응 — 백엔드 ↔ 프론트엔드 ↔ DB

| 필드 | 백엔드 (TypeScript) | 프론트엔드 (Dart) | DB (SQLite) |
|------|---------------------|-------------------|-------------|
| `id` | `string` (UUID) | `String` | `TEXT` PK |
| `amount` | `number` | `int` | `INTEGER` |
| `date` | `string` | `String` | `TEXT` |
| `category_id` | `string` (enum) | `String` | `TEXT` |
| `memo` | `string \| undefined` | `String?` | `TEXT NULL` |
| `raw_utterance` | `string \| undefined` | `String?` | `TEXT NULL` |
| `source` | `"form" \| "agent"` | `String` | `TEXT` |
| `deleted_at` | `string \| null` | `DateTime?` | `TEXT NULL` |
| `created_at` | `string` (ISO8601) | `DateTime` | `TEXT` |
| `updated_at` | `string` (ISO8601) | `DateTime` | `TEXT` |
