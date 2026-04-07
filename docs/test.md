# API 테스트 가이드

> `apps/api/` Hono + Cloudflare Workers 로컬 테스트 절차
>
> 모든 테스트는 **로컬 dev 서버**에서 실행한다.

---

## 사전 준비

### 1. 로컬 서버 실행

```bash
cd apps/api
npm run dev
```

서버가 정상 기동되면 아래와 같이 출력된다:

```
⛅️ wrangler 4.x.x
------------------
⎔ Starting local server...
[wrangler:inf] Ready on http://localhost:8787
```

### 2. JWT 발급

모든 API 테스트에 유효한 JWT가 필요하다. Supabase 대시보드 또는 아래 방법으로 발급한다.

```bash
# Supabase CLI로 직접 발급 (Supabase 프로젝트가 있을 경우)
# 또는 Supabase 대시보드 → Authentication → Users → 해당 유저 → JWT 복사

# 환경변수에 저장해두면 테스트 명령어 재사용이 편하다
export JWT="여기에_실제_JWT_붙여넣기"
```

---

## 테스트 목록

| ID | 분류 | 테스트 내용 | 기대 결과 |
|----|------|------------|-----------|
| T-0 | 환경 | `.dev.vars` 파싱 확인 | DB 연결 성공 |
| T-1 | 기본 | 헬스체크 | 200 + `{"status":"ok"}` |
| T-2 | 인증 | JWT 없이 요청 | 401 |
| T-3 | 인증 | 만료된/잘못된 JWT | 401 |
| T-4 | 검증 | Idempotency-Key 헤더 없이 POST | 400 |
| T-5 | 검증 | 잘못된 데이터로 POST (음수 금액) | 400 |
| T-6 | 검증 | 잘못된 날짜 형식으로 POST | 400 |
| T-7 | 검증 | 없는 카테고리로 POST | 400 |
| T-8 | 핵심 | 정상 거래 추가 | 201 |
| T-9 | 핵심 | 같은 요청 중복 전송 | 200 + `duplicate:true` |
| T-10 | 핵심 | 월별 목록 조회 | 200 + 데이터 포함 |
| T-11 | 핵심 | month 파라미터 없이 조회 | 200 + 전체 데이터 |
| T-12 | 핵심 | 월별 합계 조회 | 200 + total/by_category |
| T-13 | 핵심 | month 없이 summary 조회 | 400 |
| T-14 | 핵심 | 거래 삭제 | 200 |
| T-15 | 보안 | 삭제 후 같은 ID 재삭제 | 404 |
| T-16 | 보안 | 존재하지 않는 ID 삭제 | 404 |
| T-17 | 보안 | 삭제 후 목록에서 안 보이는지 | 200 + 데이터 없음 |
| T-18 | 보안 | 다른 유저 토큰으로 내 데이터 조회 | 200 + 빈 배열 |

---

## T-0: `.dev.vars` 파싱 확인

**목적**: `= "value"` 형식이 Wrangler에서 올바르게 파싱되는지 확인

현재 `.dev.vars`의 형식:
```
TURSO_DATABASE_URL= "libsql://..."
```
`=` 뒤에 공백이 있고 값이 따옴표로 감싸져 있다. 이 형식이 올바르지 않으면 DB 연결이 조용히 실패한다.

```bash
# 서버 실행 후 health 체크 (DB 연결 없이도 통과)
curl -s http://localhost:8787/api/health

# JWT를 붙여서 실제 DB 쿼리가 실행되는 엔드포인트 호출
curl -s "http://localhost:8787/api/transactions?month=2026-04" \
  -H "Authorization: Bearer $JWT"
```

**기대**: `{"data":[...]}` — DB 연결 성공  
**실패 시 증상**: `{"error":"Database error"}` 500 응답  
**실패 원인**: `.dev.vars`의 값에 따옴표나 공백이 포함된 채로 파싱됨  
**해결 방법**: `.dev.vars`를 아래 형식으로 수정
```
TURSO_DATABASE_URL=libsql://ledger-db-mingunkim.aws-ap-northeast-1.turso.io
TURSO_AUTH_TOKEN=eyJhbGci...
SUPABASE_JWT_SECRET=local-test-dummy-key
```

---

## T-1: 헬스체크

```bash
curl -s http://localhost:8787/api/health
```

**기대 응답 (200)**:
```json
{"status": "ok", "timestamp": "2026-04-08T00:00:00.000Z"}
```

**실패 시**: 서버가 기동되지 않은 것. `npm run dev` 출력 로그 확인.

---

## T-2: JWT 없이 요청 → 401

```bash
curl -s -o /dev/null -w "%{http_code}" \
  -X POST http://localhost:8787/api/transactions \
  -H "Content-Type: application/json" \
  -d '{"id":"test"}'
```

**기대**: `401`

**실패 시 (200 또는 400)**: `authMiddleware`가 제대로 등록되지 않은 것.

---

## T-3: 잘못된 JWT → 401

```bash
curl -s http://localhost:8787/api/transactions \
  -H "Authorization: Bearer this.is.not.valid"
```

**기대 응답 (401)**:
```json
{"error": "Invalid token: 만료되거나 잘못된 증명서입니다."}
```

---

## T-4: Idempotency-Key 없이 POST → 400

```bash
curl -s http://localhost:8787/api/transactions \
  -X POST \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d '{"id":"some-id","amount":1000,"date":"2026-04-08","category_id":"food","source":"form"}'
```

**기대 응답 (400)**:
```json
{"error": "Idempotency-Key header is required"}
```

---

## T-5: 잘못된 데이터 — 음수 금액 → 400

```bash
curl -s http://localhost:8787/api/transactions \
  -X POST \
  -H "Authorization: Bearer $JWT" \
  -H "Idempotency-Key: 01906e2a-0000-7000-8000-000000000001" \
  -H "Content-Type: application/json" \
  -d '{
    "id": "01906e2a-0000-7000-8000-000000000001",
    "amount": -100,
    "date": "2026-04-08",
    "category_id": "food",
    "source": "form"
  }'
```

**기대 응답 (400)**:
```json
{"error": "Invalid data", "details": {...}}
```

---

## T-6: 잘못된 날짜 형식 → 400

```bash
curl -s http://localhost:8787/api/transactions \
  -X POST \
  -H "Authorization: Bearer $JWT" \
  -H "Idempotency-Key: 01906e2a-0000-7000-8000-000000000002" \
  -H "Content-Type: application/json" \
  -d '{
    "id": "01906e2a-0000-7000-8000-000000000002",
    "amount": 5000,
    "date": "2026/04/08",
    "category_id": "food",
    "source": "form"
  }'
```

**기대 응답 (400)**: `{"error": "Invalid data", "details": {...}}`

---

## T-7: 존재하지 않는 카테고리 → 400

```bash
curl -s http://localhost:8787/api/transactions \
  -X POST \
  -H "Authorization: Bearer $JWT" \
  -H "Idempotency-Key: 01906e2a-0000-7000-8000-000000000003" \
  -H "Content-Type: application/json" \
  -d '{
    "id": "01906e2a-0000-7000-8000-000000000003",
    "amount": 5000,
    "date": "2026-04-08",
    "category_id": "invalid_category",
    "source": "form"
  }'
```

**기대 응답 (400)**: `{"error": "Invalid data", "details": {...}}`

---

## T-8: 정상 거래 추가 → 201

```bash
curl -s http://localhost:8787/api/transactions \
  -X POST \
  -H "Authorization: Bearer $JWT" \
  -H "Idempotency-Key: 01906e2a-7d3b-7000-8000-abcdef123456" \
  -H "Content-Type: application/json" \
  -d '{
    "id": "01906e2a-7d3b-7000-8000-abcdef123456",
    "amount": 12000,
    "date": "2026-04-08",
    "category_id": "food",
    "memo": "점심",
    "raw_utterance": "오늘 점심 12000원 썼어",
    "source": "agent"
  }'
```

**기대 응답 (201)**:
```json
{"id": "01906e2a-7d3b-7000-8000-abcdef123456", "message": "Transaction created"}
```

**확인사항**: Turso 대시보드 또는 CLI로 실제로 insert됐는지 확인.
```bash
# Turso CLI 설치 후
turso db shell ledger-db "SELECT * FROM transactions WHERE id = '01906e2a-7d3b-7000-8000-abcdef123456';"
turso db shell ledger-db "SELECT * FROM audit_logs ORDER BY id DESC LIMIT 1;"
```

---

## T-9: 중복 요청 → 200 + duplicate:true

**T-8을 그대로 한 번 더 실행** (동일한 id, 동일한 Idempotency-Key):

```bash
curl -s http://localhost:8787/api/transactions \
  -X POST \
  -H "Authorization: Bearer $JWT" \
  -H "Idempotency-Key: 01906e2a-7d3b-7000-8000-abcdef123456" \
  -H "Content-Type: application/json" \
  -d '{
    "id": "01906e2a-7d3b-7000-8000-abcdef123456",
    "amount": 12000,
    "date": "2026-04-08",
    "category_id": "food",
    "memo": "점심",
    "source": "agent"
  }'
```

**기대 응답 (200)**:
```json
{"id": "01906e2a-7d3b-7000-8000-abcdef123456", "duplicate": true}
```

**확인사항**: DB에 동일 id의 레코드가 1개만 존재하는지 확인.
```bash
turso db shell ledger-db "SELECT COUNT(*) FROM transactions WHERE id = '01906e2a-7d3b-7000-8000-abcdef123456';"
# 기대: count = 1
```

---

## T-10: 월별 목록 조회 → 200

```bash
curl -s "http://localhost:8787/api/transactions?month=2026-04" \
  -H "Authorization: Bearer $JWT"
```

**기대 응답 (200)**:
```json
{
  "data": [
    {
      "id": "01906e2a-7d3b-7000-8000-abcdef123456",
      "amount": 12000,
      "date": "2026-04-08",
      "category_id": "food",
      "memo": "점심",
      ...
    }
  ]
}
```

**확인사항**:
- `deleted_at`이 NULL인 것만 나오는지 확인 (소프트 삭제 필터)
- `user_id`가 내 것만 나오는지 확인

---

## T-11: month 파라미터 없이 전체 조회 → 200

```bash
curl -s "http://localhost:8787/api/transactions" \
  -H "Authorization: Bearer $JWT"
```

**기대 응답 (200)**: `{"data": [...]}` — 전체 기간 데이터

---

## T-12: 월별 합계 조회 → 200

```bash
curl -s "http://localhost:8787/api/transactions/summary?month=2026-04" \
  -H "Authorization: Bearer $JWT"
```

**기대 응답 (200)**:
```json
{
  "month": "2026-04",
  "total": 12000,
  "by_category": [
    {"category_id": "food", "amount": 12000, "count": 1}
  ]
}
```

**확인사항**:
- `total`이 숫자 타입인지 확인 (`"12000"` 문자열이 아닌 `12000` 숫자)
- 거래 0건인 달 조회 시 `total: 0`이 반환되는지 확인

```bash
# 데이터 없는 달 조회
curl -s "http://localhost:8787/api/transactions/summary?month=2020-01" \
  -H "Authorization: Bearer $JWT"
# 기대: {"month":"2020-01","total":0,"by_category":[]}
```

---

## T-13: summary에 month 없이 요청 → 400

```bash
curl -s "http://localhost:8787/api/transactions/summary" \
  -H "Authorization: Bearer $JWT"
```

**기대 응답 (400)**:
```json
{"error": "Month parameter is required (ex: 2024-04)"}
```

---

## T-14: 거래 삭제 → 200

```bash
curl -s -X DELETE \
  "http://localhost:8787/api/transactions/01906e2a-7d3b-7000-8000-abcdef123456" \
  -H "Authorization: Bearer $JWT"
```

**기대 응답 (200)**:
```json
{"message": "Transaction deleted"}
```

**확인사항**: DB에서 `deleted_at`이 채워졌는지, 실제로 행이 삭제되지 않았는지 확인.
```bash
turso db shell ledger-db "SELECT id, deleted_at FROM transactions WHERE id = '01906e2a-7d3b-7000-8000-abcdef123456';"
# 기대: deleted_at이 NULL이 아닌 datetime 값
```

---

## T-15: 이미 삭제된 거래 재삭제 → 404

**T-14 직후 같은 ID로 다시 DELETE**:

```bash
curl -s -X DELETE \
  "http://localhost:8787/api/transactions/01906e2a-7d3b-7000-8000-abcdef123456" \
  -H "Authorization: Bearer $JWT"
```

**기대 응답 (404)**:
```json
{"error": "Transaction not found"}
```

**이 테스트가 중요한 이유**: 오프라인 sync 중 네트워크 오류로 DELETE가 두 번 전송될 수 있다. 두 번째 DELETE가 `deleted_at`을 덮어쓰면 삭제 시각 기록이 오염된다. `AND deleted_at IS NULL` 조건이 이를 막는다.

---

## T-16: 존재하지 않는 ID 삭제 → 404

```bash
curl -s -X DELETE \
  "http://localhost:8787/api/transactions/00000000-0000-0000-0000-000000000000" \
  -H "Authorization: Bearer $JWT"
```

**기대 응답 (404)**:
```json
{"error": "Transaction not found"}
```

---

## T-17: 삭제 후 목록에서 제외 확인

T-14 이후 목록 재조회:

```bash
curl -s "http://localhost:8787/api/transactions?month=2026-04" \
  -H "Authorization: Bearer $JWT"
```

**기대**: `data` 배열에서 삭제한 id가 없어야 함

---

## T-18: 다른 유저 데이터 격리 확인

이 테스트는 **두 개의 Supabase 계정**이 필요하다.

```bash
# 유저 A의 JWT로 데이터 추가
curl -s http://localhost:8787/api/transactions \
  -X POST \
  -H "Authorization: Bearer $JWT_USER_A" \
  -H "Idempotency-Key: 01906e2a-7d3b-7000-8000-aaaaaaaaaaaa" \
  -H "Content-Type: application/json" \
  -d '{
    "id": "01906e2a-7d3b-7000-8000-aaaaaaaaaaaa",
    "amount": 99999,
    "date": "2026-04-08",
    "category_id": "etc",
    "source": "form"
  }'

# 유저 B의 JWT로 조회 → 유저 A 데이터가 보이면 안 됨
curl -s "http://localhost:8787/api/transactions?month=2026-04" \
  -H "Authorization: Bearer $JWT_USER_B"
```

**기대**: `data` 배열에 유저 A가 추가한 id(`aaaaaaaaaaaa`)가 없어야 함

---

## 오류 상황별 트러블슈팅

| 증상 | 원인 | 해결 |
|------|------|------|
| 모든 요청이 500 반환 | `.dev.vars` 파싱 실패로 DB URL에 따옴표/공백 포함 | `.dev.vars` 형식 수정 (따옴표, 공백 제거) |
| JWT 있는데도 401 반환 | `SUPABASE_JWT_SECRET`가 `c.env`에 없어서 `undefined`로 검증 | Bindings 타입에 `SUPABASE_JWT_SECRET` 추가 확인 |
| summary의 total이 `"12000"` 문자열 | LibSQL이 `bigint` 반환, `Number()` 변환 없음 | `Number(totalRs.rows[0]?.total ?? 0)` 확인 |
| 중복 요청이 201 반환 | `rowsAffected` 체크 없음 | Fix 2 적용 여부 확인 |
| 삭제 후에도 200 반환 (두 번째) | `AND deleted_at IS NULL` 조건 없음 | Fix 3 적용 여부 확인 |
| summary가 404 반환 | route 순서 문제 (transactions가 summary보다 먼저 등록됨) | `index.ts`에서 summary route를 먼저 등록 확인 |

---

## 배포 전 필수 확인

로컬 테스트가 모두 통과한 후 배포 전에 아래를 확인한다.

```bash
# 1. 환경변수 secrets 등록 (프로덕션)
wrangler secret put SUPABASE_JWT_SECRET
wrangler secret put TURSO_DATABASE_URL
wrangler secret put TURSO_AUTH_TOKEN

# 2. 배포
npm run deploy

# 3. 배포 후 헬스체크
curl https://ledger-agent-api.<your-subdomain>.workers.dev/api/health

# 4. 배포 후 T-2 반드시 재확인 (JWT 없이 401이 나오는지)
curl -s -o /dev/null -w "%{http_code}" \
  https://ledger-agent-api.<your-subdomain>.workers.dev/api/transactions
# 기대: 401
```

> **주의**: 프로덕션에서 T-2가 200이 나오면 인증이 뚫린 것이다. 즉시 Workers 비활성화 후 원인 파악.
