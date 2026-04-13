import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ledger_agent/services/model_download_service.dart';

final modelDownloadServiceProvider = Provider((ref) => ModelDownloadService());

final modelDownloadStateProvider =
    StateNotifierProvider<ModelDownloadNotifier, AsyncValue<double>>((ref) {
      return ModelDownloadNotifier(ref.read(modelDownloadServiceProvider));
    });

class ModelDownloadNotifier extends StateNotifier<AsyncValue<double>> {
  final ModelDownloadService _service;

  ModelDownloadNotifier(this._service) : super(const AsyncValue.data(0.0)) {
    _checkInitialState();
  }

  Future<void> _checkInitialState() async {
    final isReady = await _service.isModelReady();
    if (isReady) {
      state = const AsyncValue.data(1.0); // 이미 있으면 다운로드 완료 처리
    } else {
      startDownload();
    }
  }

  void startDownload() {
    state = const AsyncValue.loading();

    _service.downloadModel().listen(
      (progress) {
        state = AsyncValue.data(progress);
      },
      onError: (e, st) {
        state = AsyncValue.error(e, st);
      },
      onDone: () {
        state = const AsyncValue.data(1.0);
      },
      cancelOnError: true,
    );
  }
}

class ModelDownloadIndicator extends ConsumerWidget {
  const ModelDownloadIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadState = ref.watch(modelDownloadStateProvider);

    return downloadState.when(
      data: (progress) {
        if (progress >= 1.0) {
          // 완료되면 안 보임
          return const SizedBox.shrink();
        }
        return _buildCard(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'AI 에이전트 모델 다운로드 중...',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 8),
              Text('${(progress * 100).toStringAsFixed(1)}%'),
            ],
          ),
        );
      },
      loading: () => _buildCard(const CircularProgressIndicator()),
      error: (err, st) => _buildCard(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 32),
            const SizedBox(height: 8),
            const Text('다운로드 실패', style: TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () =>
                  ref.read(modelDownloadStateProvider.notifier).startDownload(),
              child: const Text('재시도'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(Widget child) {
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}
