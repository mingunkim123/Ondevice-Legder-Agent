# Ondevice Ledger Agent — Architecture Diagrams

> 전체 시스템 아키텍처 다이어그램 모음

---

## 목차

1. [전체 시스템 아키텍처](#1-전체-시스템-아키텍처)
2. [기술 스택 레이어](#2-기술-스택-레이어)
3. [자연어 입력 플로우](#3-자연어-입력-플로우)
4. [Flutter 앱 내부 구조](#4-flutter-앱-내부-구조)
5. [온디바이스 에이전트 상태 머신](#5-온디바이스-에이전트-상태-머신)
6. [오프라인 Sync 플로우](#6-오프라인-sync-플로우)
7. [API 요청 흐름 (인증 포함)](#7-api-요청-흐름-인증-포함)
8. [DB 스키마 (ER 다이어그램)](#8-db-스키마-er-다이어그램)
9. [신뢰 경계 (Trust Boundary)](#9-신뢰-경계-trust-boundary)
10. [개발 단계별 로드맵](#10-개발-단계별-로드맵)

---

## 1. 전체 시스템 아키텍처

```mermaid
graph TB
    subgraph DEVICE["📱 사용자 기기 (On-Device)"]
        direction TB
        UI["Flutter UI\n(화면 / 입력)"]
        AGENT["LedgerAgentService\n(Gemma 호출 + 파싱)"]
        LiteRT["LiteRT-LM Runtime\n(모델 추론 엔진)"]
        GEMMA["Gemma 3 1B int4\n(NL → JSON 변환)"]
        LOCAL["Local SQLite\n(Drift)\n거래 캐시 + sync_queue"]
        SECURE["flutter_secure_storage\n(JWT 토큰)"]

        UI -->|"자연어 문장"| AGENT
        AGENT -->|"프롬프트"| LiteRT
        LiteRT -->|"추론"| GEMMA
        GEMMA -->|"JSON 응답"| LiteRT
        LiteRT -->|"raw output"| AGENT
        AGENT -->|"ParsedAction"| UI
        UI -->|"확인 후 저장"| LOCAL
    end

    subgraph CLOUD["☁️ 클라우드"]
        direction TB
        WORKERS["Hono + Cloudflare Workers\n(REST API)"]
        TURSO["Turso\n(LibSQL / SQLite)\n정규화 DB"]
        SUPABASE["Supabase Auth\n(JWT 발급 / 검증)"]
        STORAGE["Supabase Storage\n(모델 파일 호스팅)"]

        WORKERS -->|"read/write"| TURSO
        WORKERS -->|"JWT 검증"| SUPABASE
    end

    UI -->|"로그인 요청"| SUPABASE
    SUPABASE -->|"JWT"| SECURE
    LOCAL -->|"sync (JWT + idempotency key)"| WORKERS
    DEVICE -->|"첫 실행 시 모델 다운로드"| STORAGE
```

---

## 2. 기술 스택 레이어

```mermaid
graph TB
    subgraph L1["Layer 1 — 사용자 인터페이스"]
        FL["Flutter\n• 모든 화면\n• 상태관리 (Riverpod)\n• 로컬 DB (Drift / SQLite)"]
    end

    subgraph L2["Layer 2 — 온디바이스 AI"]
        LM["LiteRT-LM\n(추론 런타임)"]
        GM["Gemma 3 1B int4\n(자연어 → JSON 파서)"]
        LM --> GM
    end

    subgraph L3["Layer 3 — API 게이트웨이"]
        HN["Hono\n(라우팅 / 미들웨어)"]
        CF["Cloudflare Workers\n(서버리스 엣지 런타임)"]
        HN --> CF
    end

    subgraph L4["Layer 4 — 데이터 & 인증"]
        TR["Turso\n(LibSQL)\n거래 데이터 정규화 저장"]
        SA["Supabase Auth\n(JWT / 사용자 관리)"]
        SS["Supabase Storage\n(모델 파일)"]
    end

    FL -->|"모델 추론 요청"| LM
    FL -->|"REST API (JWT)"| CF
    CF -->|"SQL"| TR
    CF -->|"JWT 검증"| SA
    FL -->|"인증"| SA
    FL -->|"모델 다운로드"| SS

    style L1 fill:#dbeafe,stroke:#3b82f6
    style L2 fill:#dcfce7,stroke:#22c55e
    style L3 fill:#fef9c3,stroke:#eab308
    style L4 fill:#fce7f3,stroke:#ec4899
```

---

## 3. 자연어 입력 플로우

```mermaid
sequenceDiagram
    actor User as 사용자
    participant UI as Flutter UI
    participant AS as LedgerAgentService
    participant LM as LiteRT-LM + Gemma
    participant CS as ConfirmSheet
    participant LOCAL as Local SQLite
    participant API as Hono Workers
    participant DB as Turso

    User->>UI: "오늘 점심 12000원 썼어"
    UI->>AS: parse(utterance, today)
    AS->>AS: buildPrompt(utterance, today)
    AS->>LM: infer(prompt)
    Note over LM: ~1-3초 추론

    alt 파싱 성공
        LM-->>AS: {"intent":"record_expense","amount":12000,...}
        AS->>AS: validateAndScore(json)
        AS-->>UI: ParsedAction(confidence=0.9)
        UI->>CS: show ConfirmSheet(parsedAction)
        CS-->>User: "이렇게 기록할까요?\n📅 오늘 💰 12,000원 🏷️ 식비"

        alt 사용자 확인
            User->>CS: 확인 탭
            CS->>LOCAL: insert(transaction, status=pending)
            CS-->>UI: 목록 즉시 반영 (낙관적 업데이트)

            alt 온라인
                LOCAL->>API: POST /api/transactions\n(idempotency-key: uuid)
                API->>API: JWT 검증 + Zod 검증
                API->>DB: INSERT ON CONFLICT DO NOTHING
                DB-->>API: ok
                API-->>LOCAL: 201 Created
                LOCAL->>LOCAL: sync_queue 항목 제거
            else 오프라인
                LOCAL->>LOCAL: sync_queue에 적재
                Note over LOCAL: 온라인 복구 시 자동 retry
            end

        else 사용자 취소 / 수정
            User->>CS: 수정 탭
            CS->>UI: 폼 화면 열기 (파싱값 미리채움)
        end

    else 파싱 실패 / 모호
        LM-->>AS: 파싱 불가 또는 ambiguous
        AS-->>UI: ParsedAction(intent=unclear)
        UI-->>User: "이해하지 못했어요.\n직접 입력해 주세요."
        UI->>UI: 폼 화면 열기
    end
```

---

## 4. Flutter 앱 내부 구조

```mermaid
graph TB
    subgraph PRES["Presentation Layer"]
        LS["LoginScreen"]
        HS["HomeScreen\n+ NLInputBar\n+ TransactionList\n+ MonthlySummary"]
        ACS["AgentConfirmSheet"]
        AAS["AgentAmbiguousSheet"]
        ATS["AddTransactionScreen\n(폼)"]
    end

    subgraph PROV["Providers (Riverpod)"]
        AP["AuthProvider"]
        TP["TransactionsProvider\n(Stream<List<Transaction>>)"]
        AGP["AgentNotifier\nidle|processing|confirm|error"]
        SP["SyncStatusProvider"]
    end

    subgraph DOMAIN["Domain Layer"]
        LAS["LedgerAgentService\n(Gemma 호출 + 파싱)"]
        LI["LedgerIntent\n(ParsedAction schema)"]
        TR_M["Transaction model"]
    end

    subgraph DATA["Data Layer"]
        REPO["TransactionRepository\n(로컬 + 리모트 조율)"]
        LOCAL_DB["Drift DB\n• TransactionsTable\n• SyncQueueTable"]
        REMOTE["TransactionApi\n(Dio)"]
    end

    subgraph CORE["Core / Services"]
        SS["SyncService\n(큐 처리 + retry)"]
        MDS["ModelDownloadService\n(첫 실행 다운로드)"]
        CONN["ConnectivityMonitor"]
    end

    LS --> AP
    HS --> TP
    HS --> AGP
    HS --> SP
    ACS --> AGP
    AAS --> AGP
    ATS --> TP

    AGP --> LAS
    LAS --> LI
    TP --> REPO
    AGP --> REPO

    REPO --> LOCAL_DB
    REPO --> REMOTE

    SS --> LOCAL_DB
    SS --> REMOTE
    CONN --> SS

    style PRES fill:#dbeafe,stroke:#3b82f6
    style PROV fill:#ede9fe,stroke:#8b5cf6
    style DOMAIN fill:#dcfce7,stroke:#22c55e
    style DATA fill:#fef9c3,stroke:#eab308
    style CORE fill:#fee2e2,stroke:#ef4444
```

---

## 5. 온디바이스 에이전트 상태 머신

```mermaid
stateDiagram-v2
    [*] --> Idle : 앱 시작

    Idle --> ModelLoading : 첫 실행\n(모델 미다운로드)
    ModelLoading --> Idle : 다운로드 완료
    ModelLoading --> ModelError : 다운로드 실패

    Idle --> Processing : 사용자 입력 전송

    Processing --> Confirm : 파싱 성공\n(confidence ≥ 0.7)
    Processing --> Ambiguous : 카테고리 모호\n(confidence 0.4~0.7)
    Processing --> FallbackForm : 파싱 실패\n또는 unsupported intent
    Processing --> RiskyConfirm : 삭제/수정 intent 감지

    Confirm --> Idle : 사용자 취소
    Confirm --> Saving : 사용자 확인
    Confirm --> FallbackForm : 사용자 수정 선택

    Ambiguous --> Confirm : 카테고리 선택 완료
    Ambiguous --> Idle : 사용자 취소

    RiskyConfirm --> Idle : 사용자 취소
    RiskyConfirm --> Saving : 사용자 최종 확인\n(경고 다이얼로그 통과)

    Saving --> Idle : 저장 완료\n(로컬 + 큐 적재)
    Saving --> SaveError : 로컬 저장 실패

    FallbackForm --> Idle : 폼에서 저장 완료
    FallbackForm --> Idle : 폼에서 취소

    ModelError --> Idle : 재시도 또는 건너뜀
    SaveError --> Idle : 에러 토스트 표시

    note right of Processing : LiteRT-LM 추론 중\n(1~3초, Isolate 실행)
    note right of RiskyConfirm : 배경 오렌지색\n건너뛸 수 없는 확인
```

---

## 6. 오프라인 Sync 플로우

```mermaid
flowchart TD
    INPUT["사용자 입력\n(오프라인/온라인)"]

    INPUT --> LOCAL_WRITE["1. 로컬 SQLite에 즉시 저장\n(status = pending)"]
    LOCAL_WRITE --> OPTIMISTIC["2. UI 즉시 반영\n(낙관적 업데이트)"]
    OPTIMISTIC --> QUEUE["3. sync_queue에 operation 적재\n(idempotency_key = UUIDv7)"]

    QUEUE --> ONLINE_CHECK{"네트워크\n온라인?"}

    ONLINE_CHECK -->|"Yes"| SEND["4. API 호출\nPOST /api/transactions\n+ Idempotency-Key 헤더"]
    ONLINE_CHECK -->|"No"| WAIT["대기\n(connectivity_plus 감지)"]
    WAIT -->|"온라인 복구"| SEND

    SEND --> RESPONSE{"서버 응답"}

    RESPONSE -->|"201 Created\n또는 200 duplicate"| SUCCESS["5. sync_queue 항목 삭제\n(sync 완료)"]
    RESPONSE -->|"4xx (검증 실패)"| PERM_FAIL["영구 실패 처리\n사용자에게 알림\n(데이터 보존)"]
    RESPONSE -->|"5xx / 타임아웃"| RETRY_CHECK{"retry_count\n< 3?"}

    RETRY_CHECK -->|"Yes"| BACKOFF["Exponential Backoff\n5s → 30s → 120s"]
    BACKOFF --> SEND
    RETRY_CHECK -->|"No"| MARK_FAILED["status = failed 마킹\n배너 알림 표시"]

    SUCCESS --> DONE["✅ 동기화 완료"]
    PERM_FAIL --> DONE
    MARK_FAILED --> MANUAL["사용자 수동 확인 필요"]

    subgraph SERVER["서버 (Turso)"]
        DB_INSERT["INSERT INTO transactions\nON CONFLICT(id) DO NOTHING\n→ 중복 방지"]
    end

    SEND --> DB_INSERT
    DB_INSERT --> RESPONSE

    style SUCCESS fill:#dcfce7,stroke:#22c55e
    style PERM_FAIL fill:#fee2e2,stroke:#ef4444
    style MARK_FAILED fill:#fef9c3,stroke:#eab308
    style MANUAL fill:#fee2e2,stroke:#ef4444
```

---

## 7. API 요청 흐름 (인증 포함)

```mermaid
sequenceDiagram
    participant App as Flutter App
    participant SB as Supabase Auth
    participant CF as Cloudflare Workers\n(Hono)
    participant DB as Turso

    Note over App,DB: 로그인 플로우
    App->>SB: signInWithEmail(email, password)
    SB-->>App: JWT (access_token + refresh_token)
    App->>App: flutter_secure_storage에 JWT 저장

    Note over App,DB: 거래 기록 API 호출
    App->>CF: POST /api/transactions\nAuthorization: Bearer {jwt}\nIdempotency-Key: {uuid}
    CF->>CF: authMiddleware:\njwtVerify(token, supabaseSecret)

    alt JWT 유효
        CF->>CF: idempotencyMiddleware:\nbody.id === Idempotency-Key 확인
        CF->>CF: zodValidate(body)

        alt 검증 통과
            CF->>DB: INSERT INTO transactions\n(id, user_id, amount, ...)\nON CONFLICT(id) DO NOTHING
            DB-->>CF: rows_affected: 0 or 1
            CF->>DB: INSERT INTO audit_logs\n(user_id, action, record_id, payload)

            alt rows_affected = 1 (신규)
                CF-->>App: 201 Created {id, created_at}
            else rows_affected = 0 (중복)
                CF-->>App: 200 OK {id, created_at, duplicate: true}
            end
        else 검증 실패
            CF-->>App: 400 Bad Request {error}
        end
    else JWT 만료
        CF-->>App: 401 Unauthorized
        App->>SB: refreshSession()
        SB-->>App: 새 JWT
        App->>CF: 요청 재시도
    else JWT 무효
        CF-->>App: 401 Unauthorized
        App->>App: 로그인 화면으로 이동
    end
```

---

## 8. DB 스키마 (ER 다이어그램)

```mermaid
erDiagram
    TRANSACTIONS {
        text id PK "UUIDv7 (client-generated)"
        text user_id FK "Supabase auth.users.id"
        integer amount "원 단위 정수 (소수점 없음)"
        text date "YYYY-MM-DD"
        text category_id FK "고정 카테고리 ID"
        text memo "nullable"
        text raw_utterance "원문 자연어 (nullable)"
        text source "'form' or 'agent'"
        text deleted_at "soft delete: ISO8601 or NULL"
        text created_at "datetime('now')"
        text updated_at "datetime('now')"
    }

    AUDIT_LOGS {
        integer id PK "AUTOINCREMENT"
        text user_id "Supabase auth.users.id"
        text action "'insert' or 'soft_delete'"
        text record_id "transactions.id"
        text payload "JSON snapshot"
        text created_at "datetime('now')"
    }

    CATEGORIES {
        text id PK "'food','cafe','transport'..."
        text label "한국어 레이블"
        text emoji "이모지"
    }

    SYNC_QUEUE {
        integer id PK "AUTOINCREMENT (로컬 전용)"
        text operation "'insert' or 'delete'"
        text record_id "transactions.id"
        text payload "JSON"
        text idempotency_key "= record_id (UUIDv7)"
        text status "'pending' or 'failed'"
        integer retry_count "default 0"
        text created_at "datetime('now')"
    }

    TRANSACTIONS ||--o{ AUDIT_LOGS : "기록됨"
    TRANSACTIONS }o--|| CATEGORIES : "속함"
    TRANSACTIONS ||--o| SYNC_QUEUE : "큐잉됨"
```

---

## 9. 신뢰 경계 (Trust Boundary)

```mermaid
graph TB
    subgraph UNTRUSTED["🔴 신뢰 불가 영역 (Untrusted)"]
        USER_INPUT["사용자 자연어 입력"]
        MODEL_OUTPUT["Gemma 모델 출력 JSON"]
    end

    subgraph SEMI["🟡 부분 신뢰 (Flutter App — 사용자 기기)"]
        PARSER["JSON 파서\n(방어적 파싱 + try/catch)"]
        RULE_CHECK["Rule-based 후처리\n(날짜/금액 범위 검증)"]
        CONFIRM_UI["사용자 확인 UI\n(모든 write의 최종 게이트)"]
        LOCAL_STORE["로컬 SQLite\n(암호화 없음, v1)"]
        JWT_STORE["JWT\n(Secure Storage)"]
    end

    subgraph TRUSTED["🟢 신뢰 영역 (Hono Workers + Turso)"]
        AUTH_MW["JWT 검증 미들웨어\n(Supabase secret)"]
        ZOD_VALID["Zod 스키마 검증\n(amount, date, category)"]
        USER_ISOLATE["user_id 격리\n(JWT.sub → WHERE user_id=?)"]
        SOFT_DELETE["소프트 삭제만 허용\n(하드 삭제 endpoint 없음)"]
        AUDIT["Audit Log\n(모든 write 기록)"]
        TURSO_DB["Turso DB\n(최종 정규화 데이터)"]
    end

    USER_INPUT -->|"파싱 요청"| PARSER
    MODEL_OUTPUT -->|"절대 직접 실행 안 함"| PARSER
    PARSER -->|"ParsedAction"| RULE_CHECK
    RULE_CHECK -->|"사용자에게 보여줌"| CONFIRM_UI
    CONFIRM_UI -->|"사용자 승인 후에만"| LOCAL_STORE
    LOCAL_STORE -->|"JWT + idempotency key"| AUTH_MW
    JWT_STORE -->|"Bearer token"| AUTH_MW
    AUTH_MW -->|"검증 통과"| ZOD_VALID
    ZOD_VALID -->|"유효한 payload"| USER_ISOLATE
    USER_ISOLATE --> SOFT_DELETE
    SOFT_DELETE --> AUDIT
    AUDIT --> TURSO_DB

    MODEL_OUTPUT -.->|"❌ 직접 DB 접근 불가"| TURSO_DB
    MODEL_OUTPUT -.->|"❌ 서버 직접 호출 불가"| AUTH_MW

    style UNTRUSTED fill:#fee2e2,stroke:#ef4444
    style SEMI fill:#fef9c3,stroke:#eab308
    style TRUSTED fill:#dcfce7,stroke:#22c55e
```

---

## 10. 개발 단계별 로드맵

```mermaid
gantt
    title Ondevice Ledger Agent — 6주 개발 로드맵
    dateFormat  YYYY-MM-DD
    axisFormat  %m/%d

    section Phase 0: 기술 검증
    Flutter + LiteRT-LM 연동     :p0a, 2026-04-08, 2d
    Gemma 한국어 JSON 출력 검증   :p0b, after p0a, 1d
    Workers + Turso 연동         :p0c, after p0a, 1d
    Supabase JWT 검증 확인        :p0d, after p0c, 1d

    section Phase 1: 기본 가계부
    Turso 스키마 + 마이그레이션   :p1a, after p0b, 2d
    Hono API 전 endpoint         :p1b, after p1a, 2d
    Flutter 로그인 화면           :p1c, after p0d, 1d
    Flutter 홈 + 목록 + 폼       :p1d, after p1c, 3d
    Drift 로컬 캐시 세팅          :p1e, after p1c, 2d

    section Phase 2: 온디바이스 에이전트
    LedgerAgentService 구현      :p2a, after p1b, 3d
    프롬프트 튜닝 + 파싱 테스트   :p2b, after p2a, 2d
    확인 바텀시트 UI              :p2c, after p1d, 2d
    삭제 확인 플로우              :p2d, after p2c, 1d
    모델 다운로드 서비스          :p2e, after p2a, 2d

    section Phase 3: Sync 안정화
    sync_queue 구현              :p3a, after p2d, 2d
    중복 방지 end-to-end 테스트  :p3b, after p3a, 1d
    retry + 실패 처리            :p3c, after p3b, 1d
    sync 상태 UI 표시            :p3d, after p3c, 1d

    section Phase 4: 프로덕션 하드닝
    Sentry 연동 (Flutter + Workers) :p4a, after p3d, 1d
    Rate limiting                :p4b, after p3d, 1d
    릴리즈 빌드 테스트            :p4c, after p4a, 2d
    실 사용 테스트 + 버그 수정    :p4d, after p4c, 3d
```

---

## 다이어그램 범례

| 색상 | 의미 |
|------|------|
| 🔵 파란색 | Flutter / UI 레이어 |
| 🟢 초록색 | 온디바이스 AI (Gemma / LiteRT-LM) |
| 🟡 노란색 | API 레이어 (Hono / Workers) |
| 🩷 분홍색 | 데이터 / 인증 레이어 (Turso / Supabase) |
| 🔴 빨간색 | 신뢰 불가 / 위험 영역 |
| 🟢 초록 테두리 | 신뢰 가능 / 안전한 영역 |

> 이 다이어그램들은 [Mermaid](https://mermaid.js.org/)로 작성되어 GitHub에서 자동으로 렌더링됩니다.
