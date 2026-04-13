int? parseKoreanAmount(dynamic rawAmount, String utterance) {
  if (rawAmount is int) return rawAmount;
  if (rawAmount is double) return rawAmount.toInt();
  if (rawAmount is String) {
    final cleanStr = rawAmount.replaceAll(',', '');
    final parsed = int.tryParse(cleanStr);
    if (parsed != null) return parsed;
  }

  // 1. "원"으로 끝나는 단어 파싱 시도
  final index = utterance.lastIndexOf('원');
  if (index != -1) {
    int start = index;
    while (start > 0 && utterance[start - 1] != ' ') {
      start--;
    }
    String word = utterance.substring(start, index);
    int? parsed = _parseKoreanNumberWord(word);
    if (parsed != null && parsed > 0) return parsed;
  }

  // 2. 숫자만 있는 경우 파싱 ("12000", "12,000")
  final numMatch = RegExp(r'([0-9,]+)').firstMatch(utterance);
  if (numMatch != null) {
    String found = numMatch.group(1)!.replaceAll(',', '');
    final parsed = int.tryParse(found);
    if (parsed != null) return parsed;
  }

  return null;
}

int? _parseKoreanNumberWord(String word) {
  if (word.isEmpty) return null;

  final digits = {
    '일': 1,
    '이': 2,
    '삼': 3,
    '사': 4,
    '오': 5,
    '육': 6,
    '칠': 7,
    '팔': 8,
    '구': 9,
  };
  final units = {'천': 1000, '백': 100, '십': 10};

  int result = 0;
  int currentPart = 0;
  int tempNum = 0;

  for (int i = 0; i < word.length; i++) {
    String char = word[i];

    if (RegExp(r'[0-9]').hasMatch(char)) {
      int start = i;
      while (i + 1 < word.length && RegExp(r'[0-9]').hasMatch(word[i + 1])) {
        i++;
      }
      tempNum = int.parse(word.substring(start, i + 1));
    } else if (digits.containsKey(char)) {
      tempNum = digits[char]!;
    } else if (units.containsKey(char)) {
      if (tempNum == 0) tempNum = 1;
      currentPart += tempNum * units[char]!;
      tempNum = 0;
    } else if (char == '만') {
      currentPart += tempNum;
      if (currentPart == 0) currentPart = 1;
      result += currentPart * 10000;
      currentPart = 0;
      tempNum = 0;
    }
  }

  result += currentPart + tempNum;
  return result == 0 ? null : result;
}
