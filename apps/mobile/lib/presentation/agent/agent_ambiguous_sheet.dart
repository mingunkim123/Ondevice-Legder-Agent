import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ledger_agent/presentation/agent/agent_provider.dart';
import 'package:ledger_agent/core/constants/categories.dart';
import 'package:ledger_agent/domain/agent/ledger_intent.dart';

class AgentAmbiguousSheet extends ConsumerStatefulWidget {
  const AgentAmbiguousSheet({super.key});

  @override
  ConsumerState<AgentAmbiguousSheet> createState() =>
      _AgentAmbiguousSheetState();
}

class _AgentAmbiguousSheetState extends ConsumerState<AgentAmbiguousSheet> {
  String? _selectedCategory;
  final _amountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final intent = ref.read(agentNotifierProvider).intent;
    if (intent != null) {
      _selectedCategory = intent.categoryId;
      if (intent.amount != null) {
        _amountController.text = intent.amount!.toInt().toString();
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentNotifierProvider);
    final intent = state.intent;

    if (intent == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '정보를 확인해주세요',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              if (intent.ambiguityReason != null) ...[
                const SizedBox(height: 8),
                Text(
                  intent.ambiguityReason!,
                  style: const TextStyle(color: Colors.orange),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                '금액 보정',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '정확한 금액을 입력하세요',
                  suffixText: '원',
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '카테고리 선택',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: kCategories.map((c) {
                  final isSelected = c.id == _selectedCategory;
                  return ChoiceChip(
                    label: Text(c.label),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedCategory = selected ? c.id : null;
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 32),
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
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        // 수정된 내용으로 새 Intent를 만들기
                        final modified = LedgerIntent(
                          type: intent.type,
                          amount: double.tryParse(_amountController.text),
                          date: intent.date,
                          categoryId: _selectedCategory,
                          memo: intent.memo,
                          rawText: intent.rawText,
                          confidence: 1.0,
                          ambiguityReason: null,
                        );
                        ref
                            .read(agentNotifierProvider.notifier)
                            .updateIntent(modified);
                        Navigator.pop(context);
                      },
                      child: const Text('보정 적용'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('수동 입력 폼으로 이동 (기능 연동 예정)')),
                  );
                  ref.read(agentNotifierProvider.notifier).rejectIntent();
                  Navigator.pop(context);
                },
                child: const Text('직접 폼 작성하기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
