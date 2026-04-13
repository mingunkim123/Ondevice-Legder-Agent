import 'dart:async';
import 'dart:convert';
import 'package:ledger_agent/core/utils/date_utils.dart';
import 'package:ledger_agent/core/utils/amount_utils.dart';
import 'package:ledger_agent/core/constants/categories.dart';
import 'package:ledger_agent/domain/agent/ledger_intent.dart';
import 'package:ledger_agent/core/exceptions/app_exception.dart';
import 'package:ledger_agent/services/model_download_service.dart';

class LedgerAgentService {
  final ModelDownloadService _downloadService;

  LedgerAgentService(this._downloadService);

  String buildPrompt(String userInput, DateTime now) {
    final catList = kCategories.map((c) => "\${c.id}(\${c.label})").join(', ');
    final todayStr =
        "\${now.year}-\${now.month.toString().padLeft(2, '0')}-\${now.day.toString().padLeft(2, '0')}";
    final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final weekdayStr = weekdays[now.weekday - 1];

    // Few-shot 예시에 사용할 전날 날짜 계산
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayStr =
        "\${yesterday.year}-\${yesterday.month.toString().padLeft(2, '0')}-\${yesterday.day.toString().padLeft(2, '0')}";

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
    // 모델이 디바이스에 준비되었는지 경로 확인
    await _downloadService.getModelPath();

    // LiteRT-LM 추론 연동 코드가 들어가야 할 곳.
    // 현재 환경에서는 모델 로드가 불가능하므로 지연 후 응답을 모사(Mock)합니다.
    await Future.delayed(const Duration(seconds: 1));

    // 테스트용 단순 키워드 분기 (실제 모델이 들어가면 삭제될 Mock 응답들입니다)
    if (prompt.contains("삭제해") || prompt.contains("지워줘")) {
      return '{"intent": "delete_last", "amount": null, "date": null, "category_id": null, "memo": null}';
    }
    if (prompt.contains("삭제") && prompt.contains("어제")) {
      return '{"intent": "delete_by_date", "amount": null, "date": null, "category_id": null, "memo": null}';
    }
    if (prompt.contains("얼마야") ||
        prompt.contains("조회") ||
        prompt.contains("이번 달")) {
      return '{"intent": "query_balance", "amount": null, "date": null, "category_id": null, "memo": null}';
    }
    if (prompt.contains("ㅁㄴㅇㄹ") || prompt.contains("안녕하세요")) {
      return '{"intent": "unsupported", "amount": null, "date": null, "category_id": null, "memo": null}';
    }

    // 기본적으로 지출로 분류되도록 모의 응답 (JSON 파싱 및 Rule-based 보정 검증용)
    return '{"intent": "record_expense", "amount": null, "date": null, "category_id": null, "memo": null}';
  }

  Future<LedgerIntent> processUserInput(String text, DateTime now) async {
    final prompt = buildPrompt(text, now);
    try {
      final rawOutput = await runInference(
        prompt,
      ).timeout(const Duration(seconds: 10));
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

      // Rule-based 보정 1: 날짜가 누락되었거나 모델이 추론하지 못한 경우
      if (jsonMap['date'] == null) {
        final parsedDate = parseKoreanRelativeDate(userInput, now);
        if (parsedDate != null) {
          jsonMap['date'] =
              "\${parsedDate.year}-\${parsedDate.month.toString().padLeft(2, '0')}-\${parsedDate.day.toString().padLeft(2, '0')}";
        }
      }

      // Rule-based 보정 2: 금액이 누락된 경우
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

      final intent = LedgerIntent.fromJson(jsonMap, userInput);

      // confidence 계산 규칙 적용
      double conf = 0.1;
      if (intent.amount != null) conf += 0.4;
      if (intent.date != null) conf += 0.3;
      if (intent.categoryId != null) conf += 0.3;

      intent.confidence = conf > 1.0 ? 1.0 : conf;

      // 추가적인 검증을 통한 상태 강제 조정 (예: 비용 관련인데 금액이 없으면 모호함)
      if ((intent.type == IntentType.recordExpense ||
              intent.type == IntentType.recordIncome) &&
          intent.amount == null) {
        intent.confidence = 0.5; // 강제로 ambiguous 상태로 이동
      }

      return intent;
    } catch (e) {
      // 1차 파싱 완전 실패시 fallback으로 자체 추출 로직 수행
      final fallbackAmt = parseKoreanAmount(null, userInput);
      if (fallbackAmt != null) {
        return LedgerIntent(
          type: IntentType.recordExpense,
          amount: fallbackAmt.toDouble(),
          date: parseKoreanRelativeDate(userInput, now) ?? now,
          categoryId: null,
          memo: null,
          rawText: userInput,
          confidence: 0.5, // 모호 확인 시트 띄우기 위함
          ambiguityReason: "텍스트에서 금액은 찾았지만 내용을 정확히 이해하지 못했어요.",
        );
      }
      throw ParseException("에이전트 응답을 이해할 수 없습니다.", debugInfo: e.toString());
    }
  }
}
