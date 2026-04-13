import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ledger_agent/presentation/agent/agent_provider.dart';

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
                enabled: !isProcessing,
                decoration: InputDecoration(
                  hintText: '예: 어제 스타벅스 5400원',
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
                    color: Theme.of(context).primaryColor,
                    onPressed: _submit,
                  ),
          ],
        ),
      ),
    );
  }
}
