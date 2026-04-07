import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/transaction_repository.dart';

class AddTransactionScreen extends StatefulWidget {
  const AddTransactionScreen({super.key});

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _amountController = TextEditingController();
  final _memoController = TextEditingController();
  bool _isSaving = false; // 로딩 처리

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('지출 추가')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          TextField(
            controller: _amountController,
            decoration: const InputDecoration(
              labelText: '금액 (원)',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _memoController,
            decoration: const InputDecoration(
              labelText: '내용 (어디서 쓰셨나요?)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),

          // 백엔드 직접 전송이 되는 Consumer 위젯
          Consumer(
            builder: (context, ref, child) {
              return ElevatedButton(
                onPressed: _isSaving
                    ? null
                    : () async {
                        final amountText = _amountController.text.trim();

                        // int.tryParse: "1200abc" 같은 입력은 null 반환 → 명확한 에러 메시지
                        // double.tryParse 대신 int를 사용하는 이유:
                        // 서버(Turso)와 로컬 DB(Drift) 모두 amount를 INTEGER로 선언했기 때문.
                        final amount = int.tryParse(amountText);
                        if (amount == null || amount <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('유효한 금액을 입력하세요 (1원 이상의 정수)')),
                          );
                          return;
                        }

                        setState(() => _isSaving = true);
                        try {
                          await ref
                              .read(transactionRepositoryProvider)
                              .addTransaction(
                                amount: amount,
                                memo: _memoController.text.trim(),
                              );
                          if (context.mounted) {
                            // 홈 리스트 갱신 유도를 위해 true 쥐어주고 날려버리기
                            Navigator.pop(context, true);
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('생성 실패: $e')),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _isSaving = false);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: _isSaving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        '전송하고 저장하기',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              );
            },
          ),
        ],
      ),
    );
  }
}
