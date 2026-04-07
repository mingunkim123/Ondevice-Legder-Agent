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

## 수정하지 않은 것 (의도적 결정)

### Bindings 타입 중복 선언 유지

`index.ts`, `transactions.ts`, `summary.ts`에 동일한 Bindings 타입이 중복 선언되어 있다. `src/types.ts`로 추출하는 것이 이상적이지만, 현재는 파일 수가 적고 타입 내용이 단순하므로 `types.ts` 추가 작업을 하지 않았다. 파일이 늘어나거나 Bindings 타입이 변경될 일이 생기면 그때 `src/types.ts`로 분리한다.

### `.dev.vars` 형식 유지

```
TURSO_DATABASE_URL= "libsql://..."
```

`=` 뒤 공백과 따옴표가 섞인 형식이다. Wrangler의 dotenv 파서는 이를 올바르게 처리하는 것으로 확인(`test.md` T-0 참고)되어야 하므로, 수정 여부는 직접 테스트 후 판단한다.
