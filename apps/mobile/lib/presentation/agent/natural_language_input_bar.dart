import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ledger_agent/presentation/agent/agent_provider.dart';
import 'package:ledger_agent/presentation/agent/model_download_indicator.dart';

class NaturalLanguageInputBar extends ConsumerStatefulWidget {
  const NaturalLanguageInputBar({super.key});

  @override
  ConsumerState<NaturalLanguageInputBar> createState() =>
      _NaturalLanguageInputBarState();
}

class _NaturalLanguageInputBarState
    extends ConsumerState<NaturalLanguageInputBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    // 에이전트 서비스에 텍스트 전달
    ref.read(agentNotifierProvider.notifier).processInput(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final agentState = ref.watch(agentNotifierProvider);
    final isProcessing = agentState.status == AgentStatus.processing;

    // 모델 다운로드가 완료되지 않았으면 입력 비활성화
    final downloadState = ref.watch(modelDownloadStateProvider);
    final isModelReady = downloadState.value != null && downloadState.value! >= 1.0;

    final isEnabled = isModelReady && !isProcessing;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), // 하단 여백 감안
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: isEnabled,
                decoration: InputDecoration(
                  hintText: isModelReady ? '예: 어제 스타벅스 5400원' : 'AI 모델 준비 중...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(width: 8),
            isProcessing
                ? const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.send),
                    color: isEnabled
                        ? Theme.of(context).primaryColor
                        : Colors.grey,
                    onPressed: isEnabled ? _submit : null,
                  ),
          ],
        ),
      ),
    );
  }
}
