import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ledger_agent/domain/agent/ledger_intent.dart';
import 'package:ledger_agent/services/ledger_agent_service.dart';
import 'package:ledger_agent/presentation/agent/model_download_indicator.dart';
// (modelDownloadServiceProvider를 빌려오기 위해 임시 import)

enum AgentStatus {
  idle, // 대기 중
  processing, // 모델 추론 중 (로딩 표시)
  confirmRequired, // 신뢰도 >= 0.7 → 확인 바텀시트 표시
  ambiguousConfirm, // 신뢰도 < 0.7 → 모호 확인 시트 표시
  error, // 에러 발생
}

class AgentState {
  final AgentStatus status;
  final LedgerIntent? intent;
  final String? errorMessage;

  AgentState({this.status = AgentStatus.idle, this.intent, this.errorMessage});

  AgentState copyWith({
    AgentStatus? status,
    LedgerIntent? intent,
    String? errorMessage,
  }) {
    return AgentState(
      status: status ?? this.status,
      intent: intent ?? this.intent,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

// 서비스 주입 프로바이더
final ledgerAgentServiceProvider = Provider((ref) {
  final downloadService = ref.read(modelDownloadServiceProvider);
  return LedgerAgentService(downloadService);
});

// 뷰모델(상태관리) 프로바이더
final agentNotifierProvider = StateNotifierProvider<AgentNotifier, AgentState>((
  ref,
) {
  final agentService = ref.read(ledgerAgentServiceProvider);
  return AgentNotifier(agentService, ref);
});

class AgentNotifier extends StateNotifier<AgentState> {
  final LedgerAgentService _agentService;
  // ignore: unused_field
  final Ref _ref;

  AgentNotifier(this._agentService, this._ref) : super(AgentState());

  Future<void> processInput(String text) async {
    if (text.trim().isEmpty) return;

    state = state.copyWith(status: AgentStatus.processing, errorMessage: null);
    try {
      final intent = await _agentService.processUserInput(text, DateTime.now());

      if (intent.type == IntentType.unsupported) {
        state = state.copyWith(
          status: AgentStatus.error,
          errorMessage: '가계부에 넣을 수 없는 내용입니다.\n직접 작성해주세요.',
        );
      } else if (intent.confidence >= 0.7) {
        state = state.copyWith(
          status: AgentStatus.confirmRequired,
          intent: intent,
        );
      } else {
        state = state.copyWith(
          status: AgentStatus.ambiguousConfirm,
          intent: intent,
        );
      }
    } catch (e) {
      state = state.copyWith(
        status: AgentStatus.error,
        errorMessage: '입력하신 내용을 이해하지 못했어요 😢\n다시 말해주시거나 직접 기입해주세요.',
      );
    }
  }

  Future<void> confirmIntent() async {
    if (state.intent == null) return;

    // 차후 TransactionRepository.addTransaction() 호출 부분
    // 파싱된 Intent 데이터를 Database 구조체로 맵핑하여 삽입

    state = state.copyWith(status: AgentStatus.idle, intent: null);
  }

  void rejectIntent() {
    state = state.copyWith(status: AgentStatus.idle, intent: null);
  }

  void updateIntent(LedgerIntent modified) {
    // 유저가 일부 값을 폼에서 수정한 뒤 재반영
    state = state.copyWith(
      status: AgentStatus.confirmRequired,
      intent: modified,
    );
  }

  void reset() {
    state = AgentState();
  }
}
