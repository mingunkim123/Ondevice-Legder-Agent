# Step 3: 온디바이스 자연어 에이전트 아키텍처

스마트폰 안에서 인터넷 연결 없이도, **입력부터 분석, 그리고 저장 승인까지 어떻게 흘러가는지**를 시각적으로 정리한 구조도입니다.

```mermaid
graph TD
    %% 사용자 입력 Layer
    User("👤 사용자 입력\n'오늘 스벅 5000원 썼어'"):::human
    
    %% UI Layer (Presentation)
    subgraph UI["📱 UI 화면층 (Presentation)"]
        ChatBar["💬 자연어 입력 바\n(홈 화면 하단 고정)"]
        ConfirmSheet["🤔 확인 바텀시트\n('이렇게 저장할까요?')"]
        Fallback["✍️ 수동 폼 입력 화면\n(오류 대비용)"]
    end
    
    %% Service Layer (Agent & Logic)
    subgraph Service["🧠 에이전트 뇌층 (Service)"]
        Prompt["📝 프롬프트 포장기\n(현재시간 + 규칙 부여)"]
        Gemma[/"🤖 Gemma 1B 모델\n(인터넷 없이 기기 내 추론)"/]
        Downloader["📦 ModelDownloadService\n(최초 1회 다운로드 관리)"]
        Parser["⚙️ JSON 파서 & 검증\n(에이전트 대답을 규격에 맞춰 추출)"]
    end
    
    %% Domain Layer (Data Schema)
    subgraph Domain["📋 규격 정의층 (Domain)"]
        Intent["LedgerIntent 객체\n(의도, 금액, 날짜, 카테고리)"]
    end
    
    %% Core Repository (기존 Step2 시스템)
    Repo[("💾 Transaction Repository\n(로컬 DB / 서버 API 연결부)")]

    %% 데이터 흐름
    User -->|글씨 전송| ChatBar
    ChatBar -->|텍스트 전달| Prompt
    Downloader -.->|1회성 모델 제공| Gemma
    Prompt -->|LLM에 질의| Gemma
    Gemma -->|JSON 형태의 답변| Parser
    Parser -.->|해석 실패(모호할 때)| Fallback
    Parser ==>|해석 성공 시| Intent
    Intent ==>|사용자에게 보여주기| ConfirmSheet
    ConfirmSheet -.->|거절/수정| Fallback
    ConfirmSheet ==>|✅ 최종 승인 터치| Repo

    %% 스타일 설정
    classDef human fill:#fff,stroke:#000,stroke-width:2px,stroke-dasharray: 5 5;
    style UI fill:#E8F5E9,stroke:#4CAF50,stroke-width:2px
    style Service fill:#E3F2FD,stroke:#2196F3,stroke-width:2px
    style Domain fill:#FFF3E0,stroke:#FF9800,stroke-width:2px
    style Repo fill:#FCE4EC,stroke:#E91E63,stroke-width:2px
```

### 💡 구조도 요약 포인트
1. **서버 불개입**: `Gemma 1B 모델`이 폰 안에 다운로드 되고 나면, 사용자의 텍스트를 받을 때 스스로 생각하고 출력합니다. 절대로 클라우드 서버로 데이터를 전송하지 않습니다.
2. **에이전트 보조 역할**: 모델이 해석한 정보(`LedgerIntent 객체`)는 곧바로 저장되는 게 아니라 일차적으로 **확인 바텀시트** 창에 뿌려집니다. 사람이 직접 "승인"을 눌러야만 기존에 만들어둔 안전한 가계부 저장소(`Transaction Repository`)로 들어가 데이터베이스에 기록됩니다.
3. **오류 대비(Fallback)**: 모델이 "어? 무슨 말인지 모르겠어" 하거나 무엇을 샀는지 분류가 모호할 땐, 강제로 데이터를 기록하여 망치지 않고 곧바로 **수동 폼 입력 화면**으로 넘겨버리는 안전장치가 마련되어 있습니다.
