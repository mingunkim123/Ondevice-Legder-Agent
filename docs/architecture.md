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
11. [모노레포 전체 파일 트리](#11-모노레포-전체-파일-트리)
12. [Flutter 파일 의존성 그래프](#12-flutter-파일-의존성-그래프)
13. [Flutter 파일별 역할 일람](#13-flutter-파일별-역할-일람)
14. [Hono API 파일 의존성 그래프](#14-hono-api-파일-의존성-그래프)
15. [API 파일별 역할 일람](#15-api-파일별-역할-일람)
16. [마이그레이션 파일 적용 순서](#16-마이그레이션-파일-적용-순서)

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

---

## 11. 모노레포 전체 파일 트리

```mermaid
graph LR
    ROOT["📁 ondevice-ledger-agent/"]

    ROOT --> APPS["📁 apps/"]
    ROOT --> MIGRATIONS["📁 migrations/"]
    ROOT --> DOCS["📁 docs/"]
    ROOT --> SCRIPTS["📁 scripts/"]
    ROOT --> GH["📁 .github/workflows/"]
    ROOT --> README["📄 README.md"]

    APPS --> MOBILE["📁 mobile/\n(Flutter)"]
    APPS --> API["📁 api/\n(Hono + Workers)"]

    MOBILE --> MOBILE_LIB["📁 lib/"]
    MOBILE --> MOBILE_TEST["📁 test/"]
    MOBILE --> PUBSPEC["📄 pubspec.yaml"]
    MOBILE --> ANDROID["📁 android/"]
    MOBILE --> IOS["📁 ios/"]

    MOBILE_LIB --> MAIN["📄 main.dart"]
    MOBILE_LIB --> APP["📄 app.dart"]
    MOBILE_LIB --> LIB_CORE["📁 core/"]
    MOBILE_LIB --> LIB_DATA["📁 data/"]
    MOBILE_LIB --> LIB_DOMAIN["📁 domain/"]
    MOBILE_LIB --> LIB_PRES["📁 presentation/"]
    MOBILE_LIB --> LIB_SVC["📁 services/"]

    API --> API_SRC["📁 src/"]
    API --> API_TEST["📁 test/"]
    API --> WRANGLER["📄 wrangler.toml"]
    API --> PKG_JSON["📄 package.json"]

    API_SRC --> IDX["📄 index.ts"]
    API_SRC --> API_ROUTES["📁 routes/"]
    API_SRC --> API_MW["📁 middleware/"]
    API_SRC --> API_DB["📁 db/"]
    API_SRC --> API_VAL["📁 validators/"]
    API_SRC --> API_TYPES["📄 types.ts"]

    MIGRATIONS --> M001["📄 001_initial.sql"]
    MIGRATIONS --> M002["📄 002_audit_log.sql"]

    DOCS --> IMPL["📄 IMPLEMENTATION_PLAN.md"]
    DOCS --> ARCH["📄 architecture.md"]
    DOCS --> API_DOC["📄 api.md"]
    DOCS --> PROMPTS["📄 agent-prompts.md"]

    SCRIPTS --> SETUP["📄 setup.sh"]
    SCRIPTS --> MIGRATE["📄 migrate.sh"]

    GH --> DEPLOY_YML["📄 api-deploy.yml"]
    GH --> TEST_YML["📄 flutter-test.yml"]

    style ROOT fill:#f8fafc,stroke:#64748b
    style MOBILE fill:#dbeafe,stroke:#3b82f6
    style API fill:#fef9c3,stroke:#eab308
    style MIGRATIONS fill:#fce7f3,stroke:#ec4899
    style DOCS fill:#f0fdf4,stroke:#22c55e
```

---

## 12. Flutter 파일 의존성 그래프

### 12-1. 진입점 및 라우팅

```mermaid
graph LR
    subgraph entry["진입점"]
        MAIN["main.dart\n• ProviderScope 설정\n• runApp 호출"]
        APP["app.dart\n• MaterialApp.router\n• GoRouter 설정\n• 테마 설정"]
    end

    subgraph screens["화면 (presentation/)"]
        LOGIN["auth/login_screen.dart"]
        HOME["home/home_screen.dart"]
        ADD["transaction/\nadd_transaction_screen.dart"]
        CONFIRM["agent/\nagent_confirm_sheet.dart"]
        AMBIG["agent/\nagent_ambiguous_sheet.dart"]
    end

    MAIN -->|"주입"| APP
    APP -->|"/login"| LOGIN
    APP -->|"/home"| HOME
    APP -->|"/add"| ADD
    HOME -->|"showModalBottomSheet"| CONFIRM
    CONFIRM -->|"모호할 때"| AMBIG
    HOME -->|"push"| ADD

    style entry fill:#f0fdf4,stroke:#22c55e
    style screens fill:#dbeafe,stroke:#3b82f6
```

### 12-2. Presentation → Provider → Repository 의존성

```mermaid
graph TD
    subgraph PRES["📁 presentation/"]
        LOGIN_S["auth/login_screen.dart"]
        HOME_S["home/home_screen.dart"]
        NL_BAR["home/widgets/\nnatural_language_input_bar.dart"]
        TX_TILE["home/widgets/\ntransaction_list_tile.dart"]
        SUMMARY["home/widgets/\nmonthly_summary_card.dart"]
        ADD_S["transaction/\nadd_transaction_screen.dart"]
        CAT_SEL["transaction/widgets/\ncategory_selector.dart"]
        CONFIRM_S["agent/agent_confirm_sheet.dart"]
        AMBIG_S["agent/agent_ambiguous_sheet.dart"]
    end

    subgraph PROV["📁 providers (Riverpod)"]
        LOGIN_P["auth/login_provider.dart\nAuthNotifier"]
        HOME_P["home/home_provider.dart\nmonthlyTransactionsProvider\nsummaryProvider"]
        AGENT_P["agent/agent_provider.dart\nAgentNotifier\nidle→processing→confirm→error"]
        ADD_P["transaction/\nadd_transaction_provider.dart"]
        SYNC_P["SyncStatusProvider\n(services/sync_service.dart 구독)"]
    end

    subgraph REPO["📁 data/repositories/"]
        AUTH_REPO["auth_repository.dart\n로그인/로그아웃/세션"]
        TX_REPO["transaction_repository.dart\n로컬 우선 read/write"]
    end

    LOGIN_S --> LOGIN_P
    HOME_S --> HOME_P
    HOME_S --> SYNC_P
    NL_BAR --> AGENT_P
    TX_TILE --> HOME_P
    SUMMARY --> HOME_P
    ADD_S --> ADD_P
    ADD_S --> CAT_SEL
    CONFIRM_S --> AGENT_P
    AMBIG_S --> AGENT_P

    LOGIN_P --> AUTH_REPO
    HOME_P --> TX_REPO
    ADD_P --> TX_REPO
    AGENT_P --> TX_REPO

    style PRES fill:#dbeafe,stroke:#3b82f6
    style PROV fill:#ede9fe,stroke:#8b5cf6
    style REPO fill:#fef9c3,stroke:#eab308
```

### 12-3. Data 레이어 파일 의존성

```mermaid
graph TD
    subgraph REPO["📁 data/repositories/"]
        TX_REPO["transaction_repository.dart\n• 로컬 캐시 우선 읽기\n• 낙관적 write\n• sync 큐 적재"]
        AUTH_REPO["auth_repository.dart\n• Supabase 세션 관리\n• JWT 갱신"]
    end

    subgraph LOCAL["📁 data/local/"]
        DB["database.dart\n• Drift DB 설정\n• 테이블 등록\n• migration 버전 관리"]
        TX_TABLE["tables/transactions_table.dart\n• 컬럼 정의\n• 인덱스"]
        SQ_TABLE["tables/sync_queue_table.dart\n• operation/status/retry_count"]
        TX_DAO["dao/transactions_dao.dart\n• watchByMonth()\n• insert()\n• softDelete()"]
        SQ_DAO["dao/sync_queue_dao.dart\n• getPending()\n• incrementRetry()\n• markFailed()"]
    end

    subgraph REMOTE["📁 data/remote/"]
        TX_API["transaction_api.dart\n• POST /api/transactions\n• GET /api/transactions\n• DELETE /api/transactions/:id"]
        AUTH_API["auth_api.dart\n• Supabase signIn\n• refreshSession"]
    end

    subgraph CORE_NET["📁 core/network/"]
        DIO["dio_client.dart\n• Dio 싱글턴\n• baseUrl, timeout"]
        INTERCEPTOR["auth_interceptor.dart\n• JWT 자동 첨부\n• 401 시 refresh 재시도"]
    end

    TX_REPO --> TX_DAO
    TX_REPO --> SQ_DAO
    TX_REPO --> TX_API
    AUTH_REPO --> AUTH_API

    TX_DAO --> DB
    SQ_DAO --> DB
    DB --> TX_TABLE
    DB --> SQ_TABLE

    TX_API --> DIO
    AUTH_API --> DIO
    DIO --> INTERCEPTOR

    style REPO fill:#fef9c3,stroke:#eab308
    style LOCAL fill:#dcfce7,stroke:#22c55e
    style REMOTE fill:#fce7f3,stroke:#ec4899
    style CORE_NET fill:#fee2e2,stroke:#ef4444
```

### 12-4. Domain 및 Agent 파일 의존성

```mermaid
graph TD
    subgraph AGENT_FILES["📁 domain/agent/"]
        AGENT_SVC["ledger_agent_service.dart\n• buildPrompt(utterance, today)\n• infer(prompt) via LiteRT-LM\n• parseModelOutput(rawJson)\n• fallbackAmountExtract(text)"]
        INTENT["ledger_intent.dart\n• enum IntentType\n• class LedgerIntent\n• class ParsedAction\n• fromJson() / toJson()"]
    end

    subgraph MODEL_FILES["📁 domain/models/"]
        TX_MODEL["transaction.dart\n• id, amount, date\n• categoryId, memo\n• rawUtterance, source\n• copyWith()"]
        CAT_MODEL["category.dart\n• id, label, emoji"]
    end

    subgraph CORE_UTILS["📁 core/"]
        DATE_UTIL["utils/date_utils.dart\n• parseKoreanRelativeDate()\n• '어제'→DateTime\n• '지난주'→DateTime"]
        AMT_UTIL["utils/amount_utils.dart\n• parseKoreanAmount()\n• '만이천원'→12000"]
        UUID_UTIL["utils/uuid.dart\n• generateId() → UUIDv7"]
        CATEGORIES["constants/categories.dart\n• kCategories (8개 고정)\n• findById()"]
    end

    subgraph SVC["📁 services/"]
        MODEL_DL["model_download_service.dart\n• checkModelExists()\n• downloadModel(onProgress)\n• getModelPath()"]
        SYNC_SVC["sync_service.dart\n• processQueue()\n• getRetryDelay()\n• notifyFailure()"]
    end

    subgraph CORE_CONN["📁 core/network/"]
        CONN["connectivity.dart\n• onConnectivityChanged Stream\n• isOnline()"]
    end

    AGENT_SVC --> INTENT
    AGENT_SVC --> DATE_UTIL
    AGENT_SVC --> AMT_UTIL
    AGENT_SVC --> CATEGORIES
    AGENT_SVC -->|"LiteRT-LM 패키지\n(외부 의존성)"| LITERT(["litert_lm\n(pub.dev)"])

    SYNC_SVC --> CONN
    MODEL_DL --> UUID_UTIL

    TX_MODEL --> CAT_MODEL

    style AGENT_FILES fill:#dcfce7,stroke:#22c55e
    style MODEL_FILES fill:#dbeafe,stroke:#3b82f6
    style CORE_UTILS fill:#fee2e2,stroke:#ef4444
    style SVC fill:#fce7f3,stroke:#ec4899
```

---

## 13. Flutter 파일별 역할 일람

### `main.dart` / `app.dart`

| 파일 | 책임 | 주요 내용 |
|------|------|-----------|
| `main.dart` | 앱 진입점 | `ProviderScope` 감싸기, `runApp` |
| `app.dart` | 앱 설정 | `MaterialApp.router`, `GoRouter` 라우트 정의, 테마 |

### `core/` — 공통 유틸

| 파일 | 책임 | 핵심 함수/클래스 |
|------|------|-----------------|
| `network/dio_client.dart` | Dio 싱글턴 | `dioClientProvider`, baseUrl, timeout 설정 |
| `network/auth_interceptor.dart` | JWT 자동 처리 | `onRequest`: JWT 헤더 첨부, `onError`: 401 시 refresh |
| `network/connectivity.dart` | 네트워크 상태 | `connectivityProvider` (Stream), `isOnline()` |
| `utils/date_utils.dart` | 한국어 날짜 파싱 | `parseKoreanRelativeDate(text, now)` |
| `utils/amount_utils.dart` | 한국어 금액 파싱 | `parseKoreanAmount(raw, utterance)` |
| `utils/uuid.dart` | ID 생성 | `generateId()` → UUIDv7 문자열 |
| `constants/categories.dart` | 고정 카테고리 | `kCategories` 리스트 8개, `findById(id)` |
| `constants/api_endpoints.dart` | API URL | `ApiEndpoints.transactions`, `ApiEndpoints.summary` |
| `errors/app_exception.dart` | 에러 타입 | `AppException`, `NetworkException`, `ParseException` |

### `data/local/` — 로컬 DB (Drift)

| 파일 | 책임 | 핵심 내용 |
|------|------|-----------|
| `database.dart` | Drift DB 설정 | `@DriftDatabase(tables: [...])`, `schemaVersion`, migration |
| `tables/transactions_table.dart` | 거래 테이블 스키마 | 컬럼 정의, `deleted_at` soft delete |
| `tables/sync_queue_table.dart` | sync 큐 스키마 | `operation`, `status`, `retry_count` |
| `dao/transactions_dao.dart` | 거래 쿼리 | `watchByMonth()`, `insert()`, `softDelete()` |
| `dao/sync_queue_dao.dart` | 큐 쿼리 | `getPending()`, `incrementRetry()`, `markFailed()`, `delete()` |

### `data/remote/` — 서버 API 호출

| 파일 | 책임 | 핵심 내용 |
|------|------|-----------|
| `transaction_api.dart` | 거래 API | `createTransaction()`, `fetchTransactions()`, `deleteTransaction()` |
| `auth_api.dart` | 인증 API | Supabase `signIn()`, `signOut()`, `refreshSession()` |

### `data/repositories/` — 로컬+리모트 조율

| 파일 | 책임 | 핵심 내용 |
|------|------|-----------|
| `transaction_repository.dart` | 거래 저장소 | 로컬 우선 읽기, 낙관적 write, sync 큐 적재 |
| `auth_repository.dart` | 인증 상태 | JWT 저장/삭제, 세션 유효성 확인 |

### `domain/` — 비즈니스 로직

| 파일 | 책임 | 핵심 내용 |
|------|------|-----------|
| `models/transaction.dart` | 거래 데이터 클래스 | 불변 클래스, `copyWith()`, `toJson()` / `fromJson()` |
| `models/category.dart` | 카테고리 클래스 | `id`, `label`, `emoji` |
| `agent/ledger_intent.dart` | intent 스키마 | `enum IntentType`, `class ParsedAction` |
| `agent/ledger_agent_service.dart` | Gemma 파싱 | `parse(utterance, now)`, `buildPrompt()`, `parseModelOutput()` |

### `presentation/` — UI 화면

| 파일 | 책임 | 핵심 내용 |
|------|------|-----------|
| `auth/login_screen.dart` | 로그인 화면 | 이메일/비밀번호 입력, Supabase 로그인 버튼 |
| `auth/login_provider.dart` | 로그인 상태 | `AuthNotifier`: loading / authenticated / error |
| `home/home_screen.dart` | 메인 화면 | 월 선택, 거래 목록, 하단 NL 입력바 |
| `home/home_provider.dart` | 홈 상태 | `monthlyTransactionsProvider`, `summaryProvider` |
| `home/widgets/natural_language_input_bar.dart` | NL 입력창 | TextField + 전송 버튼, AgentNotifier 트리거 |
| `home/widgets/transaction_list_tile.dart` | 거래 항목 | 스와이프 삭제, 금액/카테고리/날짜 표시 |
| `home/widgets/monthly_summary_card.dart` | 월별 합계 | 총 지출, 카테고리별 금액 |
| `transaction/add_transaction_screen.dart` | 거래 추가 폼 | 날짜 선택, 금액 입력, 카테고리 선택 |
| `transaction/add_transaction_provider.dart` | 폼 상태 | 폼 필드 상태, submit 로직 |
| `transaction/widgets/category_selector.dart` | 카테고리 선택 | 8개 카테고리 칩 그리드 |
| `agent/agent_confirm_sheet.dart` | 확인 바텀시트 | ParsedAction 미리보기, 확인/수정/취소 버튼 |
| `agent/agent_ambiguous_sheet.dart` | 재질문 UI | 모호한 필드 입력 요청 (카테고리 선택 등) |
| `agent/agent_provider.dart` | 에이전트 상태 | `AgentNotifier`: idle→processing→confirm→error |

### `services/` — 앱 서비스

| 파일 | 책임 | 핵심 내용 |
|------|------|-----------|
| `sync_service.dart` | 오프라인 큐 처리 | `processQueue()`, exponential backoff, 실패 알림 |
| `model_download_service.dart` | Gemma 모델 관리 | `checkModelExists()`, `downloadModel(onProgress)`, 파일 경로 반환 |

---

## 14. Hono API 파일 의존성 그래프

### 14-1. 전체 파일 의존성

```mermaid
graph TD
    subgraph ENTRY["진입점"]
        IDX["src/index.ts\n• Hono 인스턴스 생성\n• 전역 미들웨어 등록\n• route 마운트\n• Workers export default"]
    end

    subgraph ROUTES["📁 src/routes/"]
        TX_ROUTE["transactions.ts\n• POST /api/transactions\n• GET /api/transactions\n• GET /api/transactions/:id\n• DELETE /api/transactions/:id"]
        SUM_ROUTE["summary.ts\n• GET /api/transactions/summary"]
    end

    subgraph MIDDLEWARE["📁 src/middleware/"]
        AUTH_MW["auth.ts\n• JWT 검증 (jose)\n• c.set('userId', sub)\n• 401 반환"]
        IDEM_MW["idempotency.ts\n• Idempotency-Key 헤더 확인\n• body.id 일치 확인"]
    end

    subgraph VALIDATORS["📁 src/validators/"]
        TX_VAL["transaction.ts\n• createTransactionSchema (Zod)\n• deleteParamsSchema\n• queryParamsSchema"]
    end

    subgraph DB_FILES["📁 src/db/"]
        DB_CLIENT["client.ts\n• Turso createClient()\n• 환경변수에서 URL/token"]
        DB_QUERIES["queries.ts\n• insertTransaction()\n• fetchTransactions()\n• softDeleteTransaction()\n• fetchSummary()\n• insertAuditLog()"]
    end

    subgraph TYPES["타입"]
        TYPES_F["types.ts\n• Env (Bindings)\n• Variables (userId)\n• TransactionRow"]
    end

    IDX --> TX_ROUTE
    IDX --> SUM_ROUTE
    IDX --> AUTH_MW

    TX_ROUTE --> AUTH_MW
    TX_ROUTE --> IDEM_MW
    TX_ROUTE --> TX_VAL
    TX_ROUTE --> DB_QUERIES

    SUM_ROUTE --> AUTH_MW
    SUM_ROUTE --> TX_VAL
    SUM_ROUTE --> DB_QUERIES

    DB_QUERIES --> DB_CLIENT

    TX_ROUTE --> TYPES_F
    SUM_ROUTE --> TYPES_F
    AUTH_MW --> TYPES_F
    DB_CLIENT --> TYPES_F

    style ENTRY fill:#fef9c3,stroke:#eab308
    style ROUTES fill:#dbeafe,stroke:#3b82f6
    style MIDDLEWARE fill:#fee2e2,stroke:#ef4444
    style VALIDATORS fill:#dcfce7,stroke:#22c55e
    style DB_FILES fill:#fce7f3,stroke:#ec4899
```

### 14-2. 요청별 파일 실행 경로

```mermaid
graph LR
    subgraph POST_TX["POST /api/transactions"]
        direction TB
        P1["index.ts\n(라우터 분기)"]
        P2["middleware/auth.ts\nJWT 검증"]
        P3["middleware/idempotency.ts\nkey 확인"]
        P4["validators/transaction.ts\nZod 검증"]
        P5["db/queries.ts\ninsertTransaction()"]
        P6["db/queries.ts\ninsertAuditLog()"]
        P7["db/client.ts\nTurso 연결"]
        P1 --> P2 --> P3 --> P4 --> P5 --> P6 --> P7
    end

    subgraph GET_TX["GET /api/transactions"]
        direction TB
        G1["index.ts"]
        G2["middleware/auth.ts"]
        G3["validators/transaction.ts\nquery params 검증"]
        G4["db/queries.ts\nfetchTransactions()"]
        G5["db/client.ts"]
        G1 --> G2 --> G3 --> G4 --> G5
    end

    subgraph DEL_TX["DELETE /api/transactions/:id"]
        direction TB
        D1["index.ts"]
        D2["middleware/auth.ts"]
        D3["db/queries.ts\nsoftDeleteTransaction()"]
        D4["db/queries.ts\ninsertAuditLog()"]
        D5["db/client.ts"]
        D1 --> D2 --> D3 --> D4 --> D5
    end
```

---

## 15. API 파일별 역할 일람

### `src/index.ts`

```
역할: Hono 앱 루트 설정
- Hono 인스턴스 생성
- 전역 CORS / logger 미들웨어
- /api/transactions → transactions 라우터 마운트
- /api/transactions/summary → summary 라우터 마운트
- GET /api/health → 헬스체크 (인증 불필요)
- export default app (Workers 엔트리포인트)
```

### `src/middleware/`

| 파일 | 역할 | 동작 |
|------|------|------|
| `auth.ts` | JWT 검증 | `Authorization: Bearer {jwt}` 파싱 → `jose.jwtVerify()` → `c.set('userId', payload.sub)` → 실패 시 401 |
| `idempotency.ts` | 중복 방지 게이트 | `Idempotency-Key` 헤더 존재 확인 → `body.id === key` 검증 → 불일치 시 400 |

### `src/routes/`

| 파일 | 엔드포인트 | 핵심 로직 |
|------|-----------|-----------|
| `transactions.ts` | `POST /api/transactions` | auth → idempotency → Zod 검증 → `insertTransaction()` → `insertAuditLog()` → 201 또는 200(duplicate) |
| `transactions.ts` | `GET /api/transactions` | auth → query params 검증 → `fetchTransactions(userId, month)` → 200 |
| `transactions.ts` | `DELETE /api/transactions/:id` | auth → `softDeleteTransaction(id, userId)` → `insertAuditLog()` → 200 |
| `summary.ts` | `GET /api/transactions/summary` | auth → `fetchSummary(userId, month)` → 200 |

### `src/validators/transaction.ts`

```
createTransactionSchema (Zod):
  - id: UUID
  - amount: number, positive, max 100_000_000
  - date: string, regex /^\d{4}-\d{2}-\d{2}$/
  - category_id: enum (8개 고정값)
  - memo: string, max 200, optional
  - raw_utterance: string, max 500, optional
  - source: enum ['form', 'agent']

queryParamsSchema:
  - month: string, regex /^\d{4}-\d{2}$/, optional
  - category_id: enum, optional
```

### `src/db/`

| 파일 | 역할 | 핵심 내용 |
|------|------|-----------|
| `client.ts` | Turso 클라이언트 | `createClient({ url: env.TURSO_URL, authToken: env.TURSO_TOKEN })` |
| `queries.ts` | SQL 쿼리 함수 | `insertTransaction()`: `INSERT ... ON CONFLICT(id) DO NOTHING` + rows_affected 확인 |
| `queries.ts` | | `softDeleteTransaction()`: `UPDATE ... SET deleted_at = datetime('now') WHERE id = ? AND user_id = ?` |
| `queries.ts` | | `fetchSummary()`: `GROUP BY category_id` aggregate 쿼리 |
| `queries.ts` | | `insertAuditLog()`: 모든 write 이벤트 기록 |

### `src/types.ts`

```typescript
// Workers 환경변수 바인딩
type Env = {
  TURSO_URL: string
  TURSO_TOKEN: string
  SUPABASE_JWT_SECRET: string
}

// Hono context 변수 (미들웨어가 설정)
type Variables = {
  userId: string
}
```

### `wrangler.toml`

```
역할: Cloudflare Workers 배포 설정
- name: ledger-agent-api
- main: src/index.ts
- compatibility_date
- [vars]: 비민감 환경변수
- secrets (별도 wrangler secret put으로 설정):
    TURSO_URL, TURSO_TOKEN, SUPABASE_JWT_SECRET
```

---

## 16. 마이그레이션 파일 적용 순서

```mermaid
flowchart LR
    subgraph FILES["📁 migrations/"]
        M001["001_initial.sql\n\n• CREATE TABLE transactions\n• CREATE TABLE categories\n• CREATE INDEX idx_transactions_user_date\n• CREATE INDEX idx_transactions_user_category"]
        M002["002_audit_log.sql\n\n• CREATE TABLE audit_logs\n• CREATE INDEX idx_audit_logs_user\n• CREATE INDEX idx_audit_logs_record"]
    end

    subgraph LOCAL["📱 로컬 (Drift)"]
        DRIFT_V1["schemaVersion 1\n• TransactionsTable\n• SyncQueueTable"]
        DRIFT_V2["schemaVersion 2\n(향후 컬럼 추가 시)"]
    end

    subgraph SCRIPT["📁 scripts/migrate.sh"]
        SH["turso db shell \$DB_NAME\n< migrations/001_initial.sql\n\nturso db shell \$DB_NAME\n< migrations/002_audit_log.sql"]
    end

    START(["최초 Turso DB 생성\nturso db create ledger-db"]) --> M001
    M001 -->|"순서 보장"| M002
    M002 --> DONE(["✅ 프로덕션 DB 준비 완료"])

    SH -->|"실행"| M001

    DRIFT_V1 -->|"앱 업데이트 시\nMigrationStrategy"| DRIFT_V2

    style M001 fill:#fce7f3,stroke:#ec4899
    style M002 fill:#fce7f3,stroke:#ec4899
    style LOCAL fill:#dbeafe,stroke:#3b82f6
    style SCRIPT fill:#fef9c3,stroke:#eab308
```

### 마이그레이션 적용 규칙

| 규칙 | 내용 |
|------|------|
| **번호 순서 보장** | 001 → 002 → ... 반드시 순서대로 실행 |
| **멱등성** | 모든 DDL에 `IF NOT EXISTS` 사용 |
| **롤백 없음** | Turso는 DDL rollback 미지원. 문제 시 새 migration으로 fix-forward |
| **Drift 별도 관리** | 서버 Turso 스키마와 Flutter Drift 스키마는 독립적으로 버전 관리 |
| **컬럼 추가만** | v1에서는 컬럼 삭제/이름 변경 금지. 추가만 허용 |
