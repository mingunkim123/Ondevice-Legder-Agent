DateTime? parseKoreanRelativeDate(String text, DateTime now) {
  if (text.contains('오늘')) {
    return DateTime(now.year, now.month, now.day);
  } else if (text.contains('그저께') ||
      text.contains('그제') ||
      text.contains('엊그제')) {
    return DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 2));
  } else if (text.contains('어제')) {
    return DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 1));
  } else if (text.contains('모레')) {
    return DateTime(now.year, now.month, now.day).add(const Duration(days: 2));
  } else if (text.contains('내일')) {
    return DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
  } else if (text.contains('지난주')) {
    return DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 7));
  }
  return null;
}
