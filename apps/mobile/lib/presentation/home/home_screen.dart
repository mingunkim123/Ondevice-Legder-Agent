import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/transaction_repository.dart';
import '../transaction/add_transaction_screen.dart';
import '../agent/natural_language_input_bar.dart';
import '../agent/agent_provider.dart';
import '../agent/agent_confirm_sheet.dart';
import '../agent/agent_ambiguous_sheet.dart';

String _getCurrentMonth() {
  final now = DateTime.now();
  return "${now.year}-${now.month.toString().padLeft(2, '0')}";
}

// 상단 통계 데이터를 자동으로 가져오는 Provider
final summaryProvider = FutureProvider.autoDispose<Map<String, dynamic>>((
  ref,
) async {
  final repo = ref.watch(transactionRepositoryProvider);
  return repo.fetchSummary(_getCurrentMonth());
});

// 하단 리스트 데이터를 자동으로 가져오는 Provider
final transactionsProvider = FutureProvider.autoDispose<List<dynamic>>((
  ref,
) async {
  final repo = ref.watch(transactionRepositoryProvider);
  return repo.fetchTransactions(_getCurrentMonth());
});

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(summaryProvider);
    final transactionsAsync = ref.watch(transactionsProvider);

    // 에이전트 상태를 구독하여 바텀시트나 스낵바를 띄웁니다.
    ref.listen<AgentState>(agentNotifierProvider, (previous, next) {
      if (next.status == AgentStatus.confirmRequired) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (context) => const AgentConfirmSheet(),
        ).whenComplete(() {
          ref.read(agentNotifierProvider.notifier).reset();
        });
      } else if (next.status == AgentStatus.ambiguousConfirm) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (context) => const AgentAmbiguousSheet(),
        ).whenComplete(() {
          ref.read(agentNotifierProvider.notifier).reset();
        });
      } else if (next.status == AgentStatus.error &&
          next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            action: SnackBarAction(
              label: '수동 폼 이동',
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AddTransactionScreen(),
                  ),
                );
                if (result == true) {
                  ref.invalidate(summaryProvider);
                  ref.invalidate(transactionsProvider);
                }
              },
            ),
          ),
        );
        ref.read(agentNotifierProvider.notifier).reset();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('온디바이스 가계부'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '새로고침',
            onPressed: () {
              ref.invalidate(summaryProvider); // 최신 데이터로 새로고침(통계)
              ref.invalidate(transactionsProvider); // 최신 데이터로 새로고침(목록)
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: summaryAsync.when(
                    loading: () => const SizedBox(
                      height: 100,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, st) => Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.red.shade100,
                      child: Text('통계 에러 발생: $e'),
                    ),
                    data: (data) {
                      final total = data['total'] ?? 0;
                      return Card(
                        margin: const EdgeInsets.all(16),
                        color: Colors.green.shade50,
                        elevation: 0,
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            children: [
                              const Text(
                                '이번 달 총 지출',
                                style: TextStyle(fontSize: 16),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${total.toString()}원',
                                style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 8.0,
                    ),
                    child: Text(
                      '지출 내역 목록 (스와이프로 삭제)',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                transactionsAsync.when(
                  loading: () => const SliverToBoxAdapter(
                    child: Center(
                      heightFactor: 3,
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  error: (e, st) => SliverToBoxAdapter(
                    child: Center(child: Text('목록 통신 오류: $e')),
                  ),
                  data: (list) {
                    if (list.isEmpty) {
                      return const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(32.0),
                          child: Center(
                            child: Text('이번 달은 아직 지출 내역이 발견되지 않았습니다 🌱'),
                          ),
                        ),
                      );
                    }
                    return SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final tx = list[index];
                        return Dismissible(
                          // 고유 ID를 키값으로 줘서 삭제할 때 꼬이지 않게 방지
                          key: Key(tx['id']?.toString() ?? index.toString()),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            color: Colors.red,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            child: const Icon(
                              Icons.delete,
                              color: Colors.white,
                            ),
                          ),
                          // confirmDismiss: 확인 다이얼로그 + API 호출을 여기서 처리.
                          // false를 반환하면 아이템이 화면에 복원됨.
                          // onDismissed에서 API를 호출하면 실패해도 아이템이 이미 사라져서 복원 불가.
                          confirmDismiss: (direction) async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (BuildContext dialogContext) {
                                return AlertDialog(
                                  title: const Text('삭제 확인'),
                                  content: const Text('정말로 이 지출 내역을 삭제하시겠습니까?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(
                                        dialogContext,
                                      ).pop(false),
                                      child: const Text('취소'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(dialogContext).pop(true),
                                      child: const Text(
                                        '삭제',
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            );
                            if (confirmed != true) return false;

                            // 사용자가 확인한 경우에만 API 호출
                            try {
                              await ref
                                  .read(transactionRepositoryProvider)
                                  .deleteTransaction(tx['id']);
                              return true; // API 성공 → 아이템 화면에서 제거
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('삭제 실패: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                              return false; // API 실패 → 아이템 화면에 복원
                            }
                          },
                          // onDismissed: confirmDismiss가 true를 반환한 경우에만 호출됨.
                          // 이 시점에서 API는 이미 성공했으므로 UI 갱신만 처리.
                          onDismissed: (direction) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('삭제되었습니다.')),
                              );
                              ref.invalidate(summaryProvider);
                              ref.invalidate(transactionsProvider);
                            }
                          },
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.green.shade100,
                              child: const Icon(
                                Icons.receipt,
                                color: Colors.green,
                              ),
                            ),
                            title: Text(
                              tx['memo'] ?? tx['category_id'] ?? '카테고리 없음',
                            ),
                            subtitle: Text(tx['date'].toString()),
                            trailing: Text(
                              '${tx['amount']}원',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        );
                      }, childCount: list.length),
                    );
                  },
                ),
              ],
            ),
          ),
          const NaturalLanguageInputBar(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          // 작성하기 화면으로 이동 후, 되돌아올 때 true를 가져왔다면(작성 성공시) 새로고침!
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddTransactionScreen()),
          );
          if (result == true) {
            ref.invalidate(summaryProvider);
            ref.invalidate(transactionsProvider);
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
