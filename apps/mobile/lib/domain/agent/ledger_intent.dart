// 어떤 의도(목적)로 유저가 말을 걸었는지 분류표
enum IntentType {
  recordExpense, // 지출 기록형
  recordIncome, // 수입 기록형
  queryBalance, // 잔액/목록 조회형
  deleteLast, // 방금 거 삭제해줘
  deleteByDate, // 특정 구간 삭제해줘
  ambiguous, // 모호한 말 (되묻기용)
  unsupported, // 가계부와 관련 없는 말
}

class LedgerIntent {
  final IntentType type;
  final double? amount;
  final DateTime? date;
  final String? categoryId; // kCategories의 id값
  final String? memo;
  final String? rawText; // 유저가 친 원본 문장
  double confidence; // 추론 신뢰 가능성 (0.0 ~ 1.0)
  final String? ambiguityReason;

  LedgerIntent({
    required this.type,
    this.amount,
    this.date,
    this.categoryId,
    this.memo,
    this.rawText,
    required this.confidence,
    this.ambiguityReason,
  });

  // 모델이 뱉어낸 JSON String 파싱 결과를 Dart 객체 구조로 매핑
  factory LedgerIntent.fromJson(Map<String, dynamic> json, String rawText) {
    IntentType parseType(String? intentStr) {
      switch (intentStr) {
        case 'record_expense':
          return IntentType.recordExpense;
        case 'record_income':
          return IntentType.recordIncome;
        case 'query_balance':
          return IntentType.queryBalance;
        case 'delete_last':
          return IntentType.deleteLast;
        case 'delete_by_date':
          return IntentType.deleteByDate;
        case 'ambiguous':
          return IntentType.ambiguous;
        default:
          return IntentType.unsupported;
      }
    }

    return LedgerIntent(
      type: parseType(json['intent'] as String?),
      amount: (json['amount'] as num?)?.toDouble(),
      date: json['date'] != null ? DateTime.tryParse(json['date']) : null,
      categoryId: json['category_id'] as String?,
      memo: json['memo'] as String?,
      rawText: rawText,
      confidence: 1.0, // 추후 rule-based 보정 예정
      ambiguityReason: json['ambiguity_reason'] as String?,
    );
  }
}
