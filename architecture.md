# Ledger Agent — Architecture

## Flutter Frontend Folder Structure

![Flutter Frontend Folder Structure](/home/mingun/.gemini/antigravity/brain/3e2984cd-c267-414a-bfde-c6654288f09d/flutter_folder_structure_1775695255446.png)

## Data Flow

![Ledger Agent Data Flow](/home/mingun/.gemini/antigravity/brain/3e2984cd-c267-414a-bfde-c6654288f09d/flutter_data_flow_1775695271536.png)

## 계층별 핵심 책임

| 계층 | 폴더 | 책임 |
|------|------|------|
| **UI** | `presentation/` | 사용자에게 보여줄 화면과 위젯 |
| **AI 서비스** | `services/` ✨ | ONNX 세션·추론·디코딩 등 외부 SDK 캡슐화 |
| **도메인** | `domain/` ✨ | 프롬프트 설계, 데이터 모델 정의 등 비즈니스 규칙 |
| **데이터** | `data/` | 로컬 SQLite(Drift), 원격 Hono API(Dio) 통합 |
| **공통** | `core/` | 모든 계층에서 공유되는 설정·상수·네트워크 클라이언트 |

> ✨ = Step 3에서 새로 추가/확장되는 계층
