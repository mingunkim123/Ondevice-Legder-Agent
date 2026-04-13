// 파일 위치: lib/core/constants/model_config.dart
//
// [모델 설정 방법]
// 1. HuggingFace(https://huggingface.co)에 가입한다.
// 2. https://huggingface.co/google/gemma-2b-it-gpu-int4 에서 이용 약관에 동의한다.
//    (google 계정으로 로그인 후 "Agree and access repository" 버튼 클릭)
// 3. HuggingFace → Settings → Access Tokens → New Token (Read 권한) 발급
// 4. 아래 kHuggingFaceToken에 발급받은 토큰을 붙여넣는다.
// 5. 앱 실행 시 첫 화면에서 자동으로 모델을 다운로드한다. (~1.5GB)
//
// [개발 중 ADB로 빠르게 테스트하는 방법]
// HuggingFace에서 PC로 모델 파일을 직접 다운로드한 뒤:
//   adb push gemma-2b-it-gpu-int4.bin /data/data/com.mingunkim.ledger_agent/files/model.bin
// 앱을 재시작하면 다운로드 단계를 건너뛰고 바로 사용 가능하다.

/// HuggingFace 액세스 토큰 (hf_로 시작하는 값으로 교체하세요)
const String kHuggingFaceToken = 'hf_YOUR_TOKEN_HERE';

/// 모델 파일명 — flutter_gemma가 내부적으로 사용하는 고정 경로와 반드시 일치해야 한다.
/// (flutter_gemma 소스: lib/flutter_gemma_mobile.dart, const _modelPath = 'model.bin')
const String kModelFileName = 'model.bin';

/// HuggingFace에서 다운로드할 모델 URL
/// 모델: Gemma 2B IT GPU int4 (~1.5GB) — flutter_gemma 공식 지원 모델
const String kModelDownloadUrl =
    'https://huggingface.co/google/gemma-2b-it-gpu-int4/resolve/main/gemma-2b-it-gpu-int4.bin';

/// 추론 설정
const int kMaxTokens = 512;
const double kTemperature = 0.1; // 낮을수록 JSON 출력이 안정적
const int kTopK = 1;             // 가장 확률 높은 토큰만 선택 (결정론적)
