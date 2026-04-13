// 파일 위치: lib/services/ledger_agent_service.dart
//
// [flutter_gemma 0.3.1 동작 방식]
// flutter_gemma는 모델을 내부적으로 documents_dir/model.bin 경로에 고정 저장한다.
// 우리의 ModelDownloadService가 같은 경로에 파일을 저장하므로,
// 다운로드 완료 후 init()만 호출하면 flutter_gemma가 바로 모델을 사용한다.
import 'dart:async';
import 'dart:convert';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:ledger_agent/core/constants/model_config.dart';
import 'package:ledger_agent/core/utils/date_utils.dart';
import 'package:ledger_agent/core/utils/amount_utils.dart';
import 'package:ledger_agent/core/constants/categories.dart';
import 'package:ledger_agent/domain/agent/ledger_intent.dart';
import 'package:ledger_agent/core/exceptions/app_exception.dart';
import 'package:ledger_agent/services/model_download_service.dart';

class LedgerAgentService {
  final ModelDownloadService _downloadService;

  // Gemma 모델은 한 번만 초기화하면 GPU 메모리에 상주한다.
  bool _isInitialized = false;

  LedgerAgentService(this._downloadService);

  /// 모델이 로드되지 않았다면 초기화한다.
  /// 다운로드 완료 후 flutter_gemma의 init()을 호출하는 구조:
  ///   ModelDownloadService → documents_dir/model.bin 저장
  ///   → FlutterGemmaPlugin.instance.init() → 네이티브 추론 엔진 초기화
  Future<void> _ensureModelLoaded() async {
    if (_isInitialized) return;

    final isReady = await _downloadService.isModelReady();
    if (!isReady) {
      throw ModelInferenceException(
        '모델이 아직 다운로드되지 않았습니다. 잠시 후 다시 시도해주세요.',
      );
    }

    try {
      await FlutterGemmaPlugin.instance.init(
        maxTokens: kMaxTokens,
        temperature: kTemperature,
        topK: kTopK,
        randomSeed: 1,
      );
      _isInitialized = true;
    } catch (e) {
      throw ModelInferenceException(
        '모델 초기화에 실패했습니다. 기기 메모리를 확인해주세요.',
        debugInfo: e.toString(),
      );
    }
  }

  String buildPrompt(String userInput, DateTime now) {
    final catList = kCategories.map((c) => "${c.id}(${c.label})").join(', ');
    final todayStr =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final weekdayStr = weekdays[now.weekday - 1];

    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayStr =
        "${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}";

    return '''
당신은 가계부 기입을 도와주는 AI 어시스턴트입니다.
사용자의 자연어 입력을 분석하여 반드시 아래 JSON 형식으로만 응답하세요. 다른 설명은 제외합니다.

현재 날짜: $todayStr ($weekdayStr요일)
사용 가능한 카테고리 ID: $catList

[JSON 스키마]
{
  "intent": "record_expense" | "record_income" | "query_balance" | "delete_last" | "delete_by_date" | "ambiguous" | "unsupported",
  "amount": 숫자(금액 모르면 null),
  "date": "YYYY-MM-DD" (날짜 모르면 null),
  "category_id": 카테고리 ID (모르면 null),
  "memo": "간단한 내역",
  "ambiguity_reason": "모호한 경우 이유 설명"
}

[예시]
사용자 입력: "어제 스타벅스 5400원"
응답 JSON: {"intent": "record_expense", "amount": 5400, "date": "$yesterdayStr", "category_id": "cafe", "memo": "스타벅스", "ambiguity_reason": null}

사용자 입력: "$userInput"
응답 JSON:
''';
  }

  Future<String> runInference(String prompt) async {
    await _ensureModelLoaded();

    try {
      final response = await FlutterGemmaPlugin.instance.getResponse(
        prompt: prompt,
      );
      return response ?? '';
    } catch (e) {
      throw ModelInferenceException(
        '모델 추론 중 오류가 발생했습니다.',
        debugInfo: e.toString(),
      );
    }
  }

  Future<LedgerIntent> processUserInput(String text, DateTime now) async {
    final prompt = buildPrompt(text, now);
    try {
      final rawOutput = await runInference(prompt).timeout(
        const Duration(seconds: 30), // 온디바이스 추론은 최대 30초 허용
      );
      return parseModelOutput(rawOutput, text, now);
    } catch (e) {
      if (e is TimeoutException) {
        throw ModelInferenceException(
          "추론 시간이 초과되었습니다.",
          debugInfo: e.toString(),
        );
      }
      rethrow;
    }
  }

  LedgerIntent parseModelOutput(
    String rawOutput,
    String userInput,
    DateTime now,
  ) {
    try {
      final jsonBlockRegex = RegExp(r'\{[\s\S]*\}');
      final match = jsonBlockRegex.firstMatch(rawOutput);
      if (match == null) {
        throw ParseException("JSON 포맷을 찾을 수 없습니다.");
      }

      final Map<String, dynamic> jsonMap = jsonDecode(match.group(0)!);

      // Rule-based 보정 1: 날짜 누락
      if (jsonMap['date'] == null) {
        final parsedDate = parseKoreanRelativeDate(userInput, now);
        if (parsedDate != null) {
          jsonMap['date'] =
              "${parsedDate.year}-${parsedDate.month.toString().padLeft(2, '0')}-${parsedDate.day.toString().padLeft(2, '0')}";
        }
      }

      // Rule-based 보정 2: 금액 누락
      if (jsonMap['amount'] == null) {
        final extractedAmt = parseKoreanAmount(null, userInput);
        if (extractedAmt != null) {
          jsonMap['amount'] = extractedAmt;
        }
      }

      // Rule-based 보정 3: 유효하지 않은 카테고리 ID 필터링
      final validCatIds = kCategories.map((c) => c.id).toSet();
      if (jsonMap['category_id'] != null &&
          !validCatIds.contains(jsonMap['category_id'])) {
        jsonMap['category_id'] = null;
      }

      // Rule-based 보정 4: 금액 음수
      if (jsonMap['amount'] != null && (jsonMap['amount'] as num) < 0) {
        jsonMap['amount'] = 0;
        jsonMap['ambiguity_reason'] = "금액이 음수입니다. 확인해주세요.";
      }

      // Rule-based 보정 5: 미래 날짜
      if (jsonMap['date'] != null) {
        final d = DateTime.tryParse(jsonMap['date'].toString());
        if (d != null &&
            d.isAfter(DateTime(now.year, now.month, now.day, 23, 59, 59))) {
          jsonMap['ambiguity_reason'] = "미래 날짜입니다. 맞나요?";
        }
      }

      final intent = LedgerIntent.fromJson(jsonMap, userInput);

      double conf = 0.1;
      if (intent.amount != null) conf += 0.4;
      if (intent.date != null) conf += 0.3;
      if (intent.categoryId != null) conf += 0.3;
      intent.confidence = conf > 1.0 ? 1.0 : conf;

      if ((intent.type == IntentType.recordExpense ||
              intent.type == IntentType.recordIncome) &&
          intent.amount == null) {
        intent.confidence = 0.5;
      }

      if (intent.ambiguityReason != null) {
        intent.confidence = 0.5;
      }

      return intent;
    } catch (e) {
      final fallbackAmt = parseKoreanAmount(null, userInput);
      if (fallbackAmt != null) {
        return LedgerIntent(
          type: IntentType.recordExpense,
          amount: fallbackAmt.toDouble(),
          date: parseKoreanRelativeDate(userInput, now) ?? now,
          categoryId: null,
          memo: null,
          rawText: userInput,
          confidence: 0.5,
          ambiguityReason: "텍스트에서 금액은 찾았지만 내용을 정확히 이해하지 못했어요.",
        );
      }
      throw ParseException("에이전트 응답을 이해할 수 없습니다.", debugInfo: e.toString());
    }
  }
}
