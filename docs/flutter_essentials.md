# Flutter 필수 기초 — 이 프로젝트에 필요한 것만

> 이 프로젝트(Ondevice Ledger Agent)를 개발하는 데 반드시 알아야 할 Flutter/Dart 개념만 정리했다.
> 화려한 UI 기술은 없다. Gemma를 돌리고, 데이터를 화면에 보여주고, API를 호출하는 데 필요한 것만.

---

## 1. Dart 기초 문법

### 핵심만

```dart
// 타입 선언
String name = '지출';
int amount = 5000;
double confidence = 0.9;
bool isOnline = true;

// null 안전성 (이 프로젝트 전체에서 사용됨)
String? memo;          // null 가능
memo ?? '메모 없음';   // null이면 오른쪽 값 사용
memo?.length;          // null이면 null 반환 (NPE 방지)

// async/await — API 호출, Gemma 추론 전부 이 방식
Future<void> addTransaction() async {
  final result = await _dio.post('/api/transactions', data: {...});
}

// factory 생성자 — LedgerIntent.fromJson()에서 쓰임
factory LedgerIntent.fromJson(Map<String, dynamic> json, String rawText) {
  return LedgerIntent(...);
}

// enum — IntentType 같은 분류형 데이터에 사용
enum IntentType { recordExpense, recordIncome, ambiguous }
```

### 컬렉션

```dart
List<String> ids = ['food', 'transport'];
Map<String, dynamic> payload = {'amount': 5000, 'memo': '점심'};

// map/where — 리스트 가공할 때
final filtered = list.where((tx) => tx['amount'] > 0).toList();
```

---

## 2. Widget — Flutter의 모든 것은 Widget

Flutter에서 화면의 모든 요소(버튼, 텍스트, 레이아웃)는 Widget이다.

### StatelessWidget vs ConsumerWidget

```dart
// StatelessWidget: 상태 없는 단순 화면
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Text('로그인'));
  }
}

// ConsumerWidget: Riverpod Provider를 watch하는 화면 (이 프로젝트 대부분)
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(summaryProvider); // Provider 구독
    return Scaffold(...);
  }
}
```

**규칙:** API 데이터를 보여주는 화면 → `ConsumerWidget`. 단순 입력 폼 → `StatelessWidget`으로 시작.

### 자주 쓰는 Widget 목록

| Widget | 용도 | 이 프로젝트 사용 위치 |
|--------|------|----------------------|
| `Scaffold` | 기본 화면 틀 (AppBar + body + FAB) | 모든 화면 |
| `Column` / `Row` | 세로/가로 배치 | 카드 내부 레이아웃 |
| `Text` | 텍스트 표시 | 금액, 메모, 날짜 |
| `Card` | 카드형 컨테이너 | 통계 카드 |
| `ListTile` | 리스트 한 행 | 거래 내역 목록 |
| `TextField` | 텍스트 입력 | 자연어 입력창, 금액 입력 |
| `ElevatedButton` | 버튼 | 저장, 로그인 |
| `CircularProgressIndicator` | 로딩 스피너 | API 응답 대기 중 |
| `SnackBar` | 하단 알림 | 저장 성공/실패 알림 |
| `AlertDialog` | 확인 다이얼로그 | 삭제 확인창 |

---

## 3. Riverpod — 상태 관리

이 프로젝트의 상태 관리 라이브러리. API 데이터를 가져오고 화면에 뿌리는 핵심.

### Provider 종류 (이 프로젝트에서 쓰는 것만)

```dart
// Provider: 단순 객체 제공 (Repository)
final transactionRepositoryProvider = Provider(
  (ref) => TransactionRepository(),
);

// FutureProvider: 비동기 데이터 (API 응답)
final summaryProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final repo = ref.watch(transactionRepositoryProvider);
  return repo.fetchSummary('2026-04');
});
```

### Widget에서 사용하기

```dart
// ref.watch: Provider 구독 (데이터 변경 시 화면 자동 갱신)
final summaryAsync = ref.watch(summaryProvider);

// ref.read: 1회 읽기 (버튼 클릭 이벤트 등)
await ref.read(transactionRepositoryProvider).addTransaction(...);

// ref.invalidate: Provider 캐시 무효화 → 데이터 다시 fetch
ref.invalidate(summaryProvider);
```

### AsyncValue 처리 패턴 — 반드시 외울 것

FutureProvider는 항상 3가지 상태를 가진다. `.when()`으로 분기한다.

```dart
summaryAsync.when(
  loading: () => CircularProgressIndicator(),   // 로딩 중
  error: (e, st) => Text('오류: $e'),           // 실패
  data: (data) => Text('${data['total']}원'),   // 성공
);
```

---

## 4. 화면 전환 (Navigation)

```dart
// 다음 화면으로 이동
Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => const AddTransactionScreen()),
);

// 이동하고 결과값 받기 (이 프로젝트: 거래 추가 후 홈 새로고침)
final result = await Navigator.push(...);
if (result == true) {
  ref.invalidate(summaryProvider);
}

// 현재 화면 닫고 결과 반환
Navigator.pop(context, true);
```

---

## 5. 비동기 UI 패턴

### StreamBuilder — 로그인 상태 감지 (main.dart의 AuthGate)

```dart
StreamBuilder<AuthState>(
  stream: Supabase.instance.client.auth.onAuthStateChange,
  builder: (context, snapshot) {
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) return const HomeScreen();
    return const LoginScreen();
  },
);
```

스트림을 구독하다가 로그인 세션이 생기면 자동으로 `HomeScreen`으로 전환된다.

### context.mounted 체크 — async 후 UI 접근 시 필수

```dart
try {
  await repo.deleteTransaction(id);
  return true;
} catch (e) {
  if (context.mounted) { // async 작업 후 Widget이 아직 화면에 있는지 확인
    ScaffoldMessenger.of(context).showSnackBar(...);
  }
  return false;
}
```

---

## 6. 프로젝트 구조 읽는 법

```
lib/
├── main.dart                          # 앱 진입점, ProviderScope, AuthGate
├── core/
│   ├── constants/categories.dart      # 카테고리 고정값 (food, transport...)
│   └── network/dio_client.dart        # Dio HTTP 클라이언트 설정
├── domain/
│   └── agent/ledger_intent.dart       # Gemma 출력 → Dart 객체 (LedgerIntent)
├── data/
│   ├── local/                         # Drift (SQLite) 로컬 DB
│   └── repositories/
│       └── transaction_repository.dart # API 호출 담당
└── presentation/
    ├── auth/login_screen.dart         # 로그인 화면
    ├── home/home_screen.dart          # 메인 화면 (통계 + 거래 목록)
    └── transaction/
        └── add_transaction_screen.dart # 거래 추가 화면
```

**데이터 흐름:**
```
화면(presentation) → Repository(data) → API 또는 로컬 DB
화면(presentation) → LedgerAgentService(domain) → Gemma 추론
```

---

## 7. 이 프로젝트에서 안 써도 되는 것

| 개념 | 이유 |
|------|------|
| StatefulWidget | Riverpod으로 대체. 거의 쓸 일 없음 |
| InheritedWidget | Riverpod이 내부적으로 처리 |
| setState() | Riverpod 쓰면 불필요 |
| CustomPainter | 커스텀 그래픽 없음 |
| Animation / Tween | v1은 애니메이션 없음 |
| BuildContext 깊은 이해 | `context.mounted` 체크 정도면 충분 |

---

## 빠른 참고

| 상황 | 쓸 것 |
|------|-------|
| API 데이터 화면에 보여주기 | `FutureProvider` + `.when()` |
| 버튼 클릭 → API 호출 | `ref.read(provider).method()` |
| 데이터 갱신 | `ref.invalidate(provider)` |
| 화면 이동 | `Navigator.push()` |
| 화면 닫고 결과 전달 | `Navigator.pop(context, true)` |
| 하단 알림 | `ScaffoldMessenger.of(context).showSnackBar()` |
| 로딩 표시 | `CircularProgressIndicator()` |
