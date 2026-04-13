import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ledger_agent/presentation/agent/agent_provider.dart';
import 'package:ledger_agent/domain/agent/ledger_intent.dart';

class AgentConfirmSheet extends ConsumerWidget {
  const AgentConfirmSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(agentNotifierProvider);
    final intent = state.intent;

    if (intent == null) return const SizedBox.shrink();

    final isRiskyIntent =
        intent.type == IntentType.deleteLast ||
        intent.type == IntentType.deleteByDate;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isRiskyIntent
            ? Colors.orange.shade50
            : Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  isRiskyIntent
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline,
                  color: isRiskyIntent ? Colors.orange : Colors.green,
                ),
                const SizedBox(width: 8),
                Text(
                  isRiskyIntent ? '정말 삭제할까요?' : '이렇게 기록할까요?',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildRow('분류', intent.type.name),
                    if (intent.date != null)
                      _buildRow(
                        '날짜',
                        '\${intent.date!.year}-\${intent.date!.month}-\${intent.date!.day}',
                      ),
                    if (intent.amount != null)
                      _buildRow('금액', '\${intent.amount!.toInt()}원'),
                    if (intent.categoryId != null)
                      _buildRow('카테고리 ID', intent.categoryId!),
                    if (intent.memo != null) _buildRow('메모', intent.memo!),
                  ],
                ),
              ),
            ),
            if (isRiskyIntent) ...[
              const SizedBox(height: 12),
              const Text(
                '⚠️ 이 작업은 되돌릴 수 없습니다.',
                style: TextStyle(color: Colors.red, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      ref.read(agentNotifierProvider.notifier).rejectIntent();
                      Navigator.pop(context);
                    },
                    child: const Text('취소'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isRiskyIntent ? Colors.red : null,
                      foregroundColor: isRiskyIntent ? Colors.white : null,
                    ),
                    onPressed: () async {
                      await ref
                          .read(agentNotifierProvider.notifier)
                          .confirmIntent();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              isRiskyIntent
                                  ? '정상적으로 삭제되었습니다.'
                                  : '기록되었습니다: [${intent.categoryId ?? '분류없음'}] ${intent.amount?.toInt() ?? 0}원',
                            ),
                          ),
                        );
                        // 홈 스크린의 목록 즉시 갱신 (import 분리가 어렵다면 ref를 통해서만 갱신 가능)
                        Navigator.pop(context);
                        // 상태 리셋은 home_screen의 whenComplete에서 발생함
                      }
                    },
                    child: Text(isRiskyIntent ? '삭제' : '저장'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
