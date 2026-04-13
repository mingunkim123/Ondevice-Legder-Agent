// 파일 위치: lib/presentation/agent/model_download_indicator.dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ledger_agent/services/model_download_service.dart';

final modelDownloadServiceProvider = Provider((ref) => ModelDownloadService());

// -1.0 = 모델 없음(선택 화면), 0.0~0.99 = 진행 중, 1.0 = 완료
final modelDownloadStateProvider =
    StateNotifierProvider<ModelDownloadNotifier, AsyncValue<double>>((ref) {
      return ModelDownloadNotifier(ref.read(modelDownloadServiceProvider));
    });

class ModelDownloadNotifier extends StateNotifier<AsyncValue<double>> {
  final ModelDownloadService _service;

  ModelDownloadNotifier(this._service) : super(const AsyncValue.loading()) {
    _checkInitialState();
  }

  Future<void> _checkInitialState() async {
    final isReady = await _service.isModelReady();
    state = AsyncValue.data(isReady ? 1.0 : -1.0);
  }

  /// HuggingFace에서 다운로드
  void startDownload() {
    _service.downloadModelWithProgress().listen(
      (progress) => state = AsyncValue.data(progress),
      onError: (e, st) => state = AsyncValue.error(e, st),
      onDone: () => state = const AsyncValue.data(1.0),
      cancelOnError: true,
    );
  }

  /// 기기 내 파일에서 가져오기
  Future<void> importFromDevice() async {
    // 파일 피커로 .bin 파일 선택 (SAF 사용 — 저장소 권한 불필요)
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return;

    final pickedPath = result.files.single.path;
    if (pickedPath == null) {
      state = AsyncValue.error(
        Exception('파일 경로를 가져올 수 없습니다.'),
        StackTrace.current,
      );
      return;
    }

    _service.importFromFile(pickedPath).listen(
      (progress) => state = AsyncValue.data(progress),
      onError: (e, st) => state = AsyncValue.error(e, st),
      onDone: () => state = const AsyncValue.data(1.0),
      cancelOnError: true,
    );
  }

  /// 오류 후 선택 화면으로 돌아가기
  void reset() => state = const AsyncValue.data(-1.0);
}

class ModelDownloadIndicator extends ConsumerWidget {
  const ModelDownloadIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadState = ref.watch(modelDownloadStateProvider);

    return downloadState.when(
      // 초기 확인 중
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

      data: (progress) {
        // 완료 → 위젯 숨김
        if (progress >= 1.0) return const SizedBox.shrink();

        // 모델 없음 → 선택 화면
        if (progress < 0) {
          return _buildCard(
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.psychology_outlined, color: Colors.green),
                    SizedBox(width: 8),
                    Text(
                      'AI 모델 준비가 필요합니다',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Gemma 2B 모델(~1.5GB)을 설치해야 자연어 입력이 가능합니다.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                // 파일에서 가져오기 (권장)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => ref
                        .read(modelDownloadStateProvider.notifier)
                        .importFromDevice(),
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('파일에서 가져오기 (권장)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // HuggingFace 다운로드
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => ref
                        .read(modelDownloadStateProvider.notifier)
                        .startDownload(),
                    icon: const Icon(Icons.cloud_download, size: 18),
                    label: const Text('HuggingFace에서 다운로드'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.green,
                    ),
                  ),
                ),
              ],
            ),
            context,
          );
        }

        // 진행 중 (다운로드 or 복사)
        final isNearDone = progress > 0.95;
        return _buildCard(
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.downloading, color: Colors.green),
                  const SizedBox(width: 8),
                  Text(
                    isNearDone ? 'AI 모델 마무리 중...' : 'AI 모델 설치 중...',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                '완료 후 자동으로 활성화됩니다.',
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

      // 오류
      error: (err, st) {
        final msg = err is Exception
            ? err.toString().replaceFirst('Exception: ', '')
            : err.toString();
        return _buildCard(
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red),
                  SizedBox(width: 8),
                  Text(
                    '설치 실패',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                msg,
                style: const TextStyle(fontSize: 12, color: Colors.red),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () =>
                    ref.read(modelDownloadStateProvider.notifier).reset(),
                icon: const Icon(Icons.arrow_back, size: 16),
                label: const Text('돌아가기'),
              ),
            ],
          ),
          context,
        );
      },
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
