class Category {
  final String id;
  final String label;

  const Category({required this.id, required this.label});
}

// 모델 프롬프트에도 주입하게 될 8개의 기준 카테고리
const kCategories = [
  Category(id: 'food', label: '식비'),
  Category(id: 'cafe', label: '카페'),
  Category(id: 'transport', label: '교통비'),
  Category(id: 'shopping', label: '쇼핑'),
  Category(id: 'health', label: '의료/건강'),
  Category(id: 'culture', label: '문화/여가'),
  Category(id: 'utility', label: '생활비'),
  Category(id: 'etc', label: '기타'),
];
