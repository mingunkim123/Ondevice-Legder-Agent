// 파일 위치: lib/presentation/agent/model_download_indicator.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ledger_agent/services/model_download_service.dart';

final modelDownloadServiceProvider = Provider((ref) => ModelDownloadService());

final modelReadyProvider = FutureProvider<bool>((ref) async {
  final service = ref.read(modelDownloadServiceProvider);
  return service.isModelReady();
});

final modelDownloadStateProvider =
    StateNotifierProvider<ModelDownloadNotifier, AsyncValue<double>>((ref) {
      return ModelDownloadNotifier(ref.read(modelDownloadServiceProvider), ref);
    });

class ModelDownloadNotifier extends StateNotifier<AsyncValue<double>> {
  final ModelDownloadService _service;
  final Ref _ref;

  ModelDownloadNotifier(this._service, this._ref)
      : super(const AsyncValue.data(0.0)) {
    _checkInitialState();
  }

  Future<void> _checkInitialState() async {
    final isReady = await _service.isModelReady();
    if (isReady) {
      state = const AsyncValue.data(1.0);
      // modelReadyProvider 갱신
      _ref.invalidate(modelReadyProvider);
    } else {
      startDownload();
    }
  }

  void startDownload() {
    state = const AsyncValue.loading();

    _service.downloadModelWithProgress().listen(
      (progress) {
        state = AsyncValue.data(progress);
      },
      onError: (e, st) {
        state = AsyncValue.error(e, st);
      },
      onDone: () {
        state = const AsyncValue.data(1.0);
        _ref.invalidate(modelReadyProvider);
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
        if (progress >= 1.0) return const SizedBox.shrink();

        return _buildCard(
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.downloading, color: Colors.green),
                  SizedBox(width: 8),
                  Text(
                    'AI 모델 다운로드 중...',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Gemma 3 1B (약 600MB) — 최초 1회만 다운로드합니다.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.grey.shade200,
                color: Colors.green,
              ),
              const SizedBox(height: 6),
              Text(
                '${(progress * 100).toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
          context,
        );
      },
      loading: () => _buildCard(
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('AI 모델 확인 중...'),
          ],
        ),
        context,
      ),
      error: (err, st) => _buildCard(
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red),
                SizedBox(width: 8),
                Text(
                  '다운로드 실패',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              err.toString().replaceFirst('Exception: ', ''),
              style: const TextStyle(fontSize: 12, color: Colors.red),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () =>
                  ref.read(modelDownloadStateProvider.notifier).startDownload(),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('재시도'),
            ),
          ],
        ),
        context,
      ),
    );
  }

  Widget _buildCard(Widget child, BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}
