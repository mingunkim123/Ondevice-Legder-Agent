# Ondevice-Ledger-Agent

> 자연어로 입력하는 온디바이스 개인 가계부

"오늘 점심 12000원 썼어" 라고 타이핑하면 기기 안의 AI가 날짜·금액·카테고리를 자동으로 추출해 가계부에 기록해주는 모바일 앱입니다.

---

## 핵심 아이디어

일반 가계부처럼 폼으로 입력할 수도 있고, 채팅창에 자연어로 입력할 수도 있습니다. 두 가지는 동등한 입력 방법이며, 서버 입장에서는 항상 동일하게 검증된 payload를 받습니다.

```
[자연어 입력] → [Gemma 온디바이스 해석] → [구조화된 intent]
                                                    ↓
[폼 직접 입력] ─────────────────────────→ [동일한 API 엔드포인트]
                                                    ↓
                                       [Hono + Workers + Turso]
```

Gemma 모델은 **기기 안에서만** 실행됩니다. 자연어 원문은 서버로 전송되지 않고, 파싱된 구조화 데이터만 API로 전달됩니다.

---

## 기술 스택

| 레이어 | 기술 | 역할 |
|--------|------|------|
| 모바일 클라이언트 | Flutter | UI, 로컬 SQLite(drift), 오프라인 큐 |
| 온디바이스 AI | Gemma 3 1B (int4) + LiteRT-LM | 자연어 → intent JSON 변환 |
| 백엔드 API | Hono + Cloudflare Workers | REST API, 인증 검증, 비즈니스 규칙 |
| 데이터베이스 | Turso (libSQL) | 정규화된 가계부 데이터 저장 |
| 인증 | Supabase Auth | JWT 발급, 소셜/이메일 로그인 |

---

## 주요 기능 (v1 MVP)

- **이메일/소셜 로그인** (Supabase Auth)
- **지출 기록**: 날짜, 금액, 카테고리(8개 고정), 메모
- **날짜별 목록 조회** + **월별 카테고리별 합계**
- **자연어 지출 기록**: "어제 카페 5500원" → 자동 파싱
- **자연어 조회**: "이번 달 식비 얼마야?"
- **자연어 삭제**: 반드시 사용자 확인 다이얼로그 거침
- **오프라인 우선(Offline-first)**: 오프라인 입력 → 온라인 복귀 시 자동 sync

---

## 백엔드 API (`apps/api`)

Cloudflare Workers 위에서 Hono로 구현된 REST API입니다.

### 엔드포인트

| 메서드 | 경로 | 설명 |
|--------|------|------|
| GET | `/api/health` | 헬스체크 |
| POST | `/api/transactions` | 지출 기록 추가 (idempotency key 필수) |
| GET | `/api/transactions` | 목록 조회 (`?month=2024-04`, 페이지네이션 지원) |
| DELETE | `/api/transactions/:id` | 소프트 삭제 |
| GET | `/api/transactions/summary` | 월별 카테고리 합계 (`?month=2024-04` 필수) |

모든 엔드포인트는 Supabase JWT 인증이 필요합니다.

### 주요 설계 원칙

- **소프트 삭제만 허용**: `deleted_at` 타임스탬프로 처리, 하드 삭제 없음
- **Idempotency**: 중복 요청 시 동일 응답 반환, 재처리 없음
- **감사 로그**: 모든 write 작업을 `audit_logs` 테이블에 기록
- **Gemma는 프론트엔드 파서**: 서버는 intent 출처를 구분하지 않음

### 로컬 개발

```bash
cd apps/api
npm install
npm run dev
```

### 환경 변수

```
TURSO_DATABASE_URL=
TURSO_AUTH_TOKEN=
SUPABASE_JWT_SECRET=
```

### 배포

```bash
npm run deploy
```

---

## 온디바이스 AI 동작 방식

Gemma가 해도 되는 것:
- 텍스트에서 날짜, 금액, 메모, 카테고리 추출
- intent 분류 (`record_expense` / `query_summary` / `delete_record` / `ambiguous`)
- 상대적 날짜 해석 ("어제", "지난주") — 현재 날짜는 앱이 주입

Gemma가 하면 안 되는 것:
- 삭제 직접 실행 (반드시 사용자 확인)
- 금액 합산 (DB aggregate 사용)
- 인증/권한 판단
- DB 직접 조회

---

## 프로젝트 구조

```
Ondevice-Ledger-Agent/
├── apps/
│   └── api/               # Hono + Cloudflare Workers 백엔드
│       └── src/
│           ├── index.ts
│           ├── routes/
│           │   ├── transactions.ts
│           │   └── summary.ts
│           ├── middleware/
│           │   ├── auth.ts
│           │   └── idempotency.ts
│           ├── db/
│           │   └── client.ts
│           └── validators/
│               └── transaction.ts
└── docs/
    └── IMPLEMENTATION_PLAN.md  # 전체 구현 가이드
```

---

## 구현 로드맵

| 단계 | 내용 | 목표 |
|------|------|------|
| Step 0 | 기술 스택 검증 | Gemma 한국어 JSON 추출, Workers-Turso 연결, Supabase 로그인 동작 확인 |
| Step 1 | 백엔드 API 완성 | CRUD + 인증 + idempotency + audit log |
| Step 2 | Flutter 기본 UI | 폼 입력으로 지출 기록/조회/삭제, 오프라인 캐시 |
| Step 3 | 온디바이스 에이전트 통합 | 자연어 입력 → Gemma 해석 → 확인 UI → API 호출 |

v2 이후 예정: 수입 기록, 예산 알림, 영수증 OCR, 통계 차트, 데이터 내보내기

---

## 참고 문서

- [전체 구현 가이드](docs/IMPLEMENTATION_PLAN.md) — 아키텍처, DB 스키마, Sync 설계, 테스트 전략 등 상세 내용
