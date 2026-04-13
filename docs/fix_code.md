# API 코드 수정 기록

> 코드 리뷰에서 발견된 버그와 문제점, 수정 내용 정리
>
> 대상 파일: `apps/api/src/` 하위

---

## 수정 목록

| # | 심각도 | 파일 | 문제 요약 |
|---|--------|------|-----------|
| 1 | 🔴 Critical | `index.ts` / `transactions.ts` / `summary.ts` | `SUPABASE_JWT_SECRET` Bindings 타입 누락 |
| 2 | 🔴 Critical | `routes/transactions.ts` | POST 중복 요청에 항상 201 반환 |
| 3 | 🔴 Critical | `routes/transactions.ts` | DELETE 존재하지 않는 ID에 항상 200 반환 |
| 4 | 🟡 Medium  | `routes/summary.ts` | total 값 추출 방식 불명확 |
| 5 | 🔴 Critical | `middleware/auth.ts` | JWT 알고리즘 불일치 — HS256 방식으로 ES256 토큰 검증 시도 |

---

## Fix 1 — `SUPABASE_JWT_SECRET` Bindings 타입 누락

### 문제

`index.ts`, `routes/transactions.ts`, `routes/summary.ts` 세 파일 모두에서 Hono의 Bindings 타입에 `SUPABASE_JWT_SECRET`가 빠져 있었다.

```typescript
// 수정 전 (세 파일 동일)
new Hono<{
  Bindings: { TURSO_DATABASE_URL: string; TURSO_AUTH_TOKEN: string },
  //         ^^^ SUPABASE_JWT_SECRET 없음
  Variables: { userId: string }
}>()
```

`auth.ts`에서는 `c.env.SUPABASE_JWT_SECRET as string`으로 강제 캐스팅해서 TypeScript 빌드는 통과하지만, 실제 값은 `undefined`가 된다.

### 왜 문제인가

- **로컬 개발 환경**에서는 `.dev.vars`에 `SUPABASE_JWT_SECRET`가 선언되어 있어서 정상 동작하는 것처럼 보인다.
- **프로덕션 배포** 시 `wrangler secret put SUPABASE_JWT_SECRET`을 실행해도, Bindings 타입에 선언이 없으면 Workers 런타임이 해당 환경변수를 `c.env`에 노출하지 않는다.
- 결과적으로 배포 후 **모든 요청에서 JWT 검증이 실패**해 전체 API가 동작 불가 상태가 된다.

### 수정 내용

```typescript
// 수정 후 (세 파일 동일하게 적용)
new Hono<{
  Bindings: {
    TURSO_DATABASE_URL: string;
    TURSO_AUTH_TOKEN: string;
    SUPABASE_JWT_SECRET: string   // ← 추가
  },
  Variables: { userId: string }
}>()
```

### 수정된 파일

- `apps/api/src/index.ts` — line 8
- `apps/api/src/routes/transactions.ts` — line 9
- `apps/api/src/routes/summary.ts` — line 6

---

## Fix 2 — POST 중복 요청에 항상 201 반환

### 문제

`POST /api/transactions`에서 `ON CONFLICT(id) DO NOTHING`을 사용해 중복 insert를 무시하도록 했지만, 실제로 insert가 일어났는지 여부를 확인하지 않고 항상 201을 반환했다.

```typescript
// 수정 전
await db.execute({
    sql: `INSERT INTO transactions ... ON CONFLICT(id) DO NOTHING`,
    args: [...]
});
// rowsAffected 확인 없이 항상 201
return c.json({ id: data.id, message: 'Transaction created' }, 201);
```

또한 중복 요청에서도 `audit_log`에 insert 기록이 남았다.

### 왜 문제인가

- Flutter sync 로직은 201과 200을 다르게 처리할 수 있다. 중복 응답을 명시적으로 구분하지 않으면 sync 상태 추적이 부정확해진다.
- 중복 insert 시에도 `audit_log`에 기록이 쌓이면 로그가 오염된다.
- 계획서에서 명시한 스펙: 신규 → 201, 중복 → 200 + `duplicate: true`.

### 수정 내용

```typescript
// 수정 후
const result = await db.execute({
    sql: `INSERT INTO transactions ... ON CONFLICT(id) DO NOTHING`,
    args: [...]
});

// rowsAffected로 실제 insert 여부 판단
if (result.rowsAffected === 0) {
    return c.json({ id: data.id, duplicate: true }, 200);  // 중복 → 200
}

// 신규 insert 성공 시에만 감사 로그 기록
await db.execute({ sql: `INSERT INTO audit_logs ...`, args: [...] });

return c.json({ id: data.id, message: 'Transaction created' }, 201);  // 신규 → 201
```

### 수정된 파일

- `apps/api/src/routes/transactions.ts` — POST 핸들러

---

## Fix 3 — DELETE 존재하지 않는 ID에 항상 200 반환

### 문제

`DELETE /api/transactions/:id`에서 소프트 삭제 `UPDATE` 쿼리를 실행한 후 실제로 업데이트된 행이 있는지 확인하지 않았다.

```typescript
// 수정 전
await db.execute({
    sql: `UPDATE transactions SET deleted_at = ... WHERE id = ? AND user_id = ?`,
    args: [txId, userId]
});
// rowsAffected 확인 없이 항상 200
return c.json({ message: 'Transaction deleted' });
```

추가로 `WHERE` 조건에 `AND deleted_at IS NULL`이 없어서, 이미 삭제된 거래를 다시 삭제해도 200이 반환됐다.

### 왜 문제인가

- 존재하지 않는 ID로 DELETE 요청 시 200이 반환되면, 클라이언트가 삭제 성공으로 오인한다.
- 다른 유저의 거래 ID로 DELETE 요청 시 `WHERE user_id = ?` 조건에 의해 실제로는 삭제되지 않지만 200이 반환된다. 정보 유출은 아니지만 클라이언트에 잘못된 피드백을 준다.
- 이미 삭제된 거래를 sync 중에 다시 DELETE 요청하면 `deleted_at`이 덮어씌워져 삭제 시각 기록이 오염된다.

### 수정 내용

```typescript
// 수정 후
const result = await db.execute({
    sql: `UPDATE transactions
          SET deleted_at = datetime('now'), updated_at = datetime('now')
          WHERE id = ? AND user_id = ? AND deleted_at IS NULL`,
    //                                    ^^^^^^^^^^^^^^^^^^^ 추가: 이미 삭제된 거 방지
    args: [txId, userId]
});

if (result.rowsAffected === 0) {
    return c.json({ error: 'Transaction not found' }, 404);  // ← 추가
}

await db.execute({ sql: `INSERT INTO audit_logs ...`, args: [...] });
return c.json({ message: 'Transaction deleted' });
```

### 수정된 파일

- `apps/api/src/routes/transactions.ts` — DELETE 핸들러

---

## Fix 4 — `summary.ts` total 값 추출 방식 불명확

### 문제

```typescript
// 수정 전
const total = totalRs.rows[0]?.[0] || totalRs.rows[0]?.total || 0;
```

두 가지 접근 방식(`[0]` 인덱스와 `.total` 컬럼명)을 OR로 연결하고 있었다.

### 왜 문제인가

- LibSQL의 `Row` 타입은 배열 인덱스와 컬럼명 양쪽으로 접근 가능하지만, `[0]`이 먼저 평가된다.
- **거래가 0건인 달** 조회 시 `SUM()`은 `NULL`을 반환한다. `rows[0]?.[0]`이 `null`이면 `null || rows[0]?.total`로 넘어가는데, 이것도 `null`이므로 최종 `|| 0`으로 처리된다. 우연히 맞지만, 의도가 불명확하고 타입이 `number | bigint | string | null`로 불확정적이다.
- 향후 LibSQL의 Row 타입이 변경되면 `[0]` 접근이 깨질 수 있다.

### 수정 내용

```typescript
// 수정 후
const total = Number(totalRs.rows[0]?.total ?? 0);
```

- `?.total`: 컬럼명으로만 접근 (더 명확하고 안전)
- `?? 0`: `null`과 `undefined` 모두 0으로 처리 (`||`는 `0`도 falsy로 처리하지만 `??`는 nullish만 처리)
- `Number(...)`: LibSQL이 반환하는 `bigint` 또는 `string` 타입도 number로 통일

### 수정된 파일

- `apps/api/src/routes/summary.ts` — total 추출 라인

---

---

## Fix 5 — JWT 알고리즘 불일치 (HS256 vs ES256)

### 증상

로그인 직후 홈 화면이 뜨자마자 `통계 에러 발생`, `목록 통신 오류` 메시지가 나타나고 wrangler 로그에 아래가 반복됐다.

```
[wrangler:info] GET /api/transactions/summary 401 Unauthorized
[wrangler:info] GET /api/transactions 401 Unauthorized
```

### 원인 찾는 과정

처음에는 auth.ts에 최근 추가된 `atob()` base64 디코딩 코드가 원인일 것이라 의심했다.

```typescript
// 의심된 코드
const secretBytes = Uint8Array.from(atob(secretStr), (c) => c.charCodeAt(0));
```

이를 원래의 `TextEncoder` 방식으로 되돌렸지만 동일하게 401이 발생했다.

auth.ts에 디버그 로그를 추가한 뒤 앱을 실행하자 핵심 단서가 나왔다.

```
[auth] 토큰 수신, 앞 20자: eyJhbGciOiJFUzI1NiIs
[auth] JWT_SECRET 로드 여부: true 길이: 88
✘ [ERROR] [auth] JWT 검증 실패:
  Key for the ES256 algorithm must be one of type CryptoKey,
  KeyObject, or JSON Web Key. Received an instance of Uint8Array
```

토큰 앞부분 `eyJhbGciOiJFUzI1NiIs`를 base64 디코딩하면 `{"alg":"ES256",` 이다. 토큰이 **ES256** 방식으로 서명되어 있었던 것.

### 왜 이런 일이 생겼나

Supabase는 과거에 **HS256** (HMAC — 대칭 키)을 기본 알고리즘으로 사용했다. HS256은 서버가 하나의 비밀 문자열(`SUPABASE_JWT_SECRET`)로 서명하고 검증하는 방식이라, 아래처럼 간단하게 구현할 수 있었다.

```typescript
// HS256 시절 — 비밀 문자열 하나로 검증
const secret = new TextEncoder().encode(process.env.SUPABASE_JWT_SECRET);
const { payload } = await jwtVerify(token, secret);
```

그런데 이 프로젝트의 Supabase 프로젝트는 더 최신에 만들어졌고, **ES256** (ECDSA — 비대칭 키)을 사용한다. ES256은 **개인 키(private key)로 서명하고, 공개 키(public key)로 검증**하는 방식이다.

| 항목 | HS256 (구) | ES256 (신) |
|------|------------|------------|
| 종류 | 대칭 암호화 | 비대칭 암호화 |
| 서명 | 비밀 문자열 | 개인 키 |
| 검증 | 동일한 비밀 문자열 | **공개 키** |
| 검증 키 출처 | `.dev.vars`의 JWT_SECRET | Supabase JWKS 엔드포인트 |

공개 키를 직접 하드코딩할 수도 있지만, Supabase는 **JWKS(JSON Web Key Set) 엔드포인트**를 제공한다. 이 URL에 접속하면 현재 유효한 공개 키 목록을 JSON으로 돌려준다.

```
https://<project-ref>.supabase.co/auth/v1/.well-known/jwks.json
```

`jose` 라이브러리의 `createRemoteJWKSet`을 사용하면 이 엔드포인트에서 공개 키를 자동으로 받아오고 캐싱까지 해준다.

### 수정 내용

**`apps/api/src/middleware/auth.ts`**

```typescript
// 수정 전 — HS256 방식 (ES256 토큰에 작동 안 함)
const secret = new TextEncoder().encode(c.env.SUPABASE_JWT_SECRET as string);
const { payload } = await jwtVerify(token, secret);

// 수정 후 — JWKS 엔드포인트에서 ES256 공개 키를 받아와 검증
const jwksUrl = new URL(`${c.env.SUPABASE_URL}/auth/v1/.well-known/jwks.json`);
const JWKS = createRemoteJWKSet(jwksUrl);
const { payload } = await jwtVerify(token, JWKS);
```

**`apps/api/src/index.ts`**

```typescript
// 수정 전
Bindings: { TURSO_DATABASE_URL: string; TURSO_AUTH_TOKEN: string; SUPABASE_JWT_SECRET: string }

// 수정 후 — JWT_SECRET 제거, SUPABASE_URL 추가
Bindings: { TURSO_DATABASE_URL: string; TURSO_AUTH_TOKEN: string; SUPABASE_URL: string }
```

**`apps/api/.dev.vars`**

```diff
- SUPABASE_JWT_SECRET="EJcsEWsjngg..."
+ SUPABASE_URL="https://gndauofpuqmhpmobshnm.supabase.co"
```

> `.dev.vars`를 변경한 경우 `wrangler dev`를 완전히 재시작해야 반영된다. hot reload로는 환경변수 변경이 적용되지 않는다.

### 배운 점

- JWT 토큰의 알고리즘은 토큰 첫 번째 부분(헤더)에 명시되어 있다. base64 디코딩하면 바로 확인 가능하다.
  ```
  eyJhbGciOiJFUzI1NiIs → {"alg":"ES256", ...}
  eyJhbGciOiJIUzI1NiIs → {"alg":"HS256", ...}
  ```
- Supabase 신규 프로젝트는 ES256을 기본으로 사용한다. 인터넷에 있는 오래된 튜토리얼의 HS256 예제 코드를 그대로 쓰면 동작하지 않는다.
- `SUPABASE_JWT_SECRET`은 ES256에서는 필요 없다. JWKS 엔드포인트가 공개 키를 관리해준다.

---

## 수정하지 않은 것 (의도적 결정)

### Bindings 타입 중복 선언 유지

`index.ts`, `transactions.ts`, `summary.ts`에 동일한 Bindings 타입이 중복 선언되어 있다. `src/types.ts`로 추출하는 것이 이상적이지만, 현재는 파일 수가 적고 타입 내용이 단순하므로 `types.ts` 추가 작업을 하지 않았다. 파일이 늘어나거나 Bindings 타입이 변경될 일이 생기면 그때 `src/types.ts`로 분리한다.

### `.dev.vars` 형식 유지

```
TURSO_DATABASE_URL= "libsql://..."
```

`=` 뒤 공백과 따옴표가 섞인 형식이다. Wrangler의 dotenv 파서는 이를 올바르게 처리하는 것으로 확인(`test.md` T-0 참고)되어야 하므로, 수정 여부는 직접 테스트 후 판단한다.
