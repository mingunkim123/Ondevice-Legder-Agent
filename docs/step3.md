# Step 3: 온디바이스 자연어 에이전트 아키텍처

스마트폰 안에서 인터넷 연결 없이도, **입력부터 분석, 그리고 저장 승인까지 어떻게 흘러가는지**를 시각적으로 정리한 구조도입니다.

```mermaid
graph TD
    User("사용자 입력\n오늘 스벅 5000원 썼어"):::human

    subgraph UI [UI 화면층 Presentation]
        ChatBar["자연어 입력 바\n홈 화면 하단 고정"]
        ConfirmSheet["확인 바텀시트\n이렇게 저장할까요?"]
        Fallback["수동 폼 입력 화면\n오류 대비용"]
    end

    subgraph Service [에이전트 서비스층 Service]
        Prompt["프롬프트 포장기\n현재시간 + 규칙 부여"]
        Gemma[/"Gemma 1B 모델\n인터넷 없이 기기 내 추론"/]
        Downloader["ModelDownloadService\n최초 1회 다운로드 관리"]
        Parser["JSON 파서 & 검증\n에이전트 대답을 규격에 맞춰 추출"]
    end

    subgraph Domain [규격 정의층 Domain]
        Intent["LedgerIntent 객체\n의도, 금액, 날짜, 카테고리"]
    end

    Repo[("Transaction Repository\n로컬 DB / 서버 API 연결부")]

    User -->|글씨 전송| ChatBar
    ChatBar -->|텍스트 전달| Prompt
    Downloader -.->|1회성 모델 제공| Gemma
    Prompt -->|LLM에 질의| Gemma
    Gemma -->|JSON 형태의 답변| Parser
    Parser -.->|해석 실패| Fallback
    Parser ==>|해석 성공| Intent
    Intent ==>|사용자에게 보여주기| ConfirmSheet
    ConfirmSheet -.->|거절 또는 수정| Fallback
    ConfirmSheet ==>|최종 승인 터치| Repo

    classDef human fill:#fff,stroke:#000,stroke-width:2px,stroke-dasharray:5 5
    style UI fill:#E8F5E9,stroke:#4CAF50,stroke-width:2px
    style Service fill:#E3F2FD,stroke:#2196F3,stroke-width:2px
    style Domain fill:#FFF3E0,stroke:#FF9800,stroke-width:2px
    style Repo fill:#FCE4EC,stroke:#E91E63,stroke-width:2px
```

---

## 구현 파일 의존성 그래프

화살표 방향: **A → B = A가 B를 import(의존)**

색상 기준:
- 파랑: 신규 생성 파일
- 주황: 기존 파일 수정
- 회색: 기존 파일 그대로 사용

```mermaid
graph TD
    subgraph UI [Presentation 화면층]
        HomeScreen["home_screen.dart"]
        NLBar["natural_language_input_bar.dart"]
        ConfirmSheet["agent_confirm_sheet.dart"]
        AmbiguousSheet["agent_ambiguous_sheet.dart"]
    end

    subgraph State [State 상태관리]
        AgentProvider["agent_provider.dart"]
    end

    subgraph Service [Service 서비스층]
        AgentService["ledger_agent_service.dart"]
        DownloadService["model_download_service.dart"]
    end

    subgraph Domain [Domain 도메인]
        LedgerIntent["ledger_intent.dart"]
    end

    subgraph Foundation [Foundation 기반]
        Categories["categories.dart"]
        DateUtils["date_utils.dart"]
        AmountUtils["amount_utils.dart"]
        AppException["app_exception.dart"]
    end

    subgraph Data [Data 데이터]
        Repo["transaction_repository.dart"]
    end

    HomeScreen --> NLBar
    NLBar --> AgentProvider
    NLBar --> ConfirmSheet
    NLBar --> AmbiguousSheet

    ConfirmSheet --> AgentProvider
    ConfirmSheet --> LedgerIntent
    ConfirmSheet --> Repo
    AmbiguousSheet --> AgentProvider
    AmbiguousSheet --> LedgerIntent

    AgentProvider --> AgentService
    AgentProvider --> LedgerIntent
    AgentProvider --> Repo

    AgentService --> LedgerIntent
    AgentService --> Categories
    AgentService --> DateUtils
    AgentService --> AmountUtils
    AgentService --> AppException
    AgentService --> DownloadService

    DownloadService --> AppException

    classDef new fill:#E3F2FD,stroke:#2196F3,stroke-width:2px
    classDef update fill:#FFF3E0,stroke:#FF9800,stroke-width:2px
    classDef existing fill:#F5F5F5,stroke:#9E9E9E,stroke-width:1px

    class NLBar,ConfirmSheet,AmbiguousSheet,AgentProvider,AgentService,DownloadService,LedgerIntent,DateUtils,AmountUtils,AppException new
    class HomeScreen,Repo update
    class Categories existing
```

---

## 런타임 호출 흐름

사용자가 텍스트를 입력했을 때 파일들이 어떤 순서로 호출되는지를 나타냅니다.

```mermaid
sequenceDiagram
    participant User as 사용자
    participant NLBar as natural_language_input_bar
    participant AP as agent_provider
    participant AS as ledger_agent_service
    participant DS as model_download_service
    participant CS as agent_confirm_sheet
    participant Repo as transaction_repository

    User->>NLBar: 텍스트 입력 후 전송
    NLBar->>AP: processUserInput(text)
    AP->>AS: parseUserInput(text, now)
    AS->>DS: getModelPath()
    DS-->>AS: 모델 파일 경로

    AS->>AS: buildPrompt(text, now)
    Note over AS: categories + 날짜 컨텍스트 주입
    AS->>AS: LiteRT 추론 실행
    AS->>AS: JSON 파싱 + LedgerIntent 생성

    alt 신뢰도 >= 0.7
        AS-->>AP: LedgerIntent (정상)
        AP-->>NLBar: 상태 confirmRequired
        NLBar->>CS: showModalBottomSheet
        User->>CS: 확인 버튼 터치
        CS->>Repo: addTransaction(intent)
        Repo-->>CS: 완료
        CS-->>User: 바텀시트 닫힘 + 목록 갱신
    else 신뢰도 < 0.7
        AS-->>AP: LedgerIntent (모호)
        AP-->>NLBar: 상태 ambiguousConfirm
        NLBar->>User: agent_ambiguous_sheet 표시
        User->>NLBar: 카테고리/금액 직접 선택
    end

    opt 모델 추론 실패
        AS-->>AP: ModelInferenceException
        AP-->>NLBar: 상태 error
        NLBar->>User: 수동 폼 입력 화면으로 이동
    end
```

---

### 💡 구조도 요약 포인트
1. **서버 불개입**: `Gemma 1B 모델`이 폰 안에 다운로드 되고 나면, 사용자의 텍스트를 받을 때 스스로 생각하고 출력합니다. 절대로 클라우드 서버로 데이터를 전송하지 않습니다.
2. **에이전트 보조 역할**: 모델이 해석한 정보(`LedgerIntent 객체`)는 곧바로 저장되는 게 아니라 일차적으로 **확인 바텀시트** 창에 뿌려집니다. 사람이 직접 "승인"을 눌러야만 기존에 만들어둔 안전한 가계부 저장소(`Transaction Repository`)로 들어가 데이터베이스에 기록됩니다.
3. **오류 대비(Fallback)**: 모델이 "어? 무슨 말인지 모르겠어" 하거나 무엇을 샀는지 분류가 모호할 땐, 강제로 데이터를 기록하여 망치지 않고 곧바로 **수동 폼 입력 화면**으로 넘겨버리는 안전장치가 마련되어 있습니다.
