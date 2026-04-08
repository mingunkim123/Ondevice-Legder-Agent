# 백엔드 소프트웨어 엔지니어링 검토

결론: **기초는 단단하지만 프로덕션 수준은 아닙니다.**

---

## 잘 된 것

### 보안 — 수준 높음

- SQL 인젝션 없음. 모든 쿼리가 파라미터 바인딩 (`?` + `args` 배열) 사용
- 모든 엔드포인트에 `authMiddleware` 적용, 인증 누락 불가
- 모든 쿼리에 `WHERE user_id = ?` — 다른 사용자 데이터 접근 불가
- Zod 검증이 DB 접근 전에 실행됨

### 멱등성 — 잘 설계됨

- DB 레벨에서 `INSERT ... ON CONFLICT(id) DO NOTHING` 으로 중복 차단
- 중복 요청 시 201이 아니라 200 + `duplicate: true` 반환

---

## 문제점

### P0 — 프로덕션 전에 반드시

**페이지네이션 없음**
- `GET /api/transactions`가 `LIMIT` 없이 전체를 반환 (`transactions.ts:63`)
- 거래가 수천 건 쌓이면 응답이 폭발적으로 커짐

**에러 로깅 없음**
- 모든 `catch` 블록이 에러를 그냥 삼켜버림 (`transactions.ts:51`, `79`, `109`, `summary.ts:46`)
- 프로덕션에서 쿼리가 왜 실패했는지 알 방법이 없음

**month 파라미터 미검증**
- `GET /api/transactions?month=` 과 `/summary?month=` 에서 month 값이 형식 검증 없이 LIKE 쿼리에 그대로 투입됨 (`transactions.ts:68`)

### P1 — 조만간 수정

**관심사 분리 안 됨**
- `createDbClient()`가 모든 핸들러마다 호출됨 (POST, GET, DELETE, summary — 총 4번)
- SQL 쿼리, 비즈니스 로직, 응답 처리가 라우트 핸들러 안에 한데 섞여 있음
- 에러 처리 `try-catch` 패턴이 4군데에서 복붙됨

**레이트 리밋 없음**
- 무제한 요청 가능 — DoS에 무방비

**트랜잭션 미사용**
- `INSERT` 성공 후 audit log INSERT가 따로 실행됨 (`transactions.ts:44`)
- audit log가 실패해도 거래는 이미 저장된 상태 — 두 개가 원자적으로 처리돼야 함

### P2 — 여유 있을 때

**CORS 설정 없음**
- `cors()` 를 설정 없이 사용 중 → 모든 오리진 허용

**서비스 레이어 없음**
- 라우트 핸들러에 비즈니스 로직이 직접 들어 있어 테스트와 재사용이 어려움

---

## 우선순위 요약

| 순위 | 작업 | 관련 파일 |
|------|------|-----------|
| P0 | 페이지네이션 추가 | `routes/transactions.ts:63` |
| P0 | 에러 로깅 추가 | `routes/transactions.ts:51,79,109` / `routes/summary.ts:46` |
| P0 | month 파라미터 형식 검증 | `routes/transactions.ts:68` / `routes/summary.ts:12` |
| P1 | 레이트 리밋 미들웨어 추가 | `middleware/` |
| P1 | DB 클라이언트 싱글톤화 | `routes/*.ts` |
| P1 | INSERT + audit log 트랜잭션으로 묶기 | `routes/transactions.ts:32,44` |
| P2 | CORS 오리진 제한 | `index.ts:11` |
| P2 | 서비스 레이어 분리 | `routes/*.ts` |
