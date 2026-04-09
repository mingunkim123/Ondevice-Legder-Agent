# Flutter 필수 기초 — 이 프로젝트에 필요한 것만

> 이 문서는 Ondevice Ledger Agent 코드를 읽고 수정할 수 있는 수준을 목표로 한다.
> 각 개념은 실제 프로젝트 코드와 연결해서 설명한다.

---

## 1. Flutter는 어떻게 화면을 만드는가

Flutter에서 화면의 모든 요소는 **Widget**이다. 버튼 하나, 텍스트 한 줄, 화면 전체 레이아웃 모두 Widget이다. Widget을 나무처럼 중첩해서 화면을 만든다.

```dart
Scaffold(                          // 화면 틀
  appBar: AppBar(                  // 상단 바
    title: Text('온디바이스 가계부'),
  ),
  body: Column(                    // 세로로 쌓는 컨테이너
    children: [
      Text('이번 달 총 지출'),
      Text('32,000원'),
    ],
  ),
  floatingActionButton: FloatingActionButton(  // 우하단 버튼
    onPressed: () {},
    child: Icon(Icons.add),
  ),
)
```

이게 `home_screen.dart`의 기본 골격이다. `Scaffold` 하나가 화면 한 장이다.

---

## 2. StatelessWidget vs StatefulWidget vs ConsumerWidget

Flutter Widget은 세 가지 중 하나다.

### StatelessWidget — 상태가 없는 화면

데이터를 받아서 그냥 보여주기만 하는 Widget. 내부에서 값이 바뀔 일이 없을 때 쓴다.

```dart
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const AuthGate(),
    );
  }
}
```

`build()`가 호출되면 Widget 트리를 반환한다. 이게 화면에 그려진다. `StatelessWidget`은 한 번 그려지면 스스로 다시 그려지지 않는다.

### StatefulWidget — 내부 상태가 있는 화면

버튼을 눌렀을 때 로딩 스피너를 보여줘야 하는 것처럼, **위젯 내부에서 값이 바뀌고 그 변화를 화면에 반영**해야 할 때 쓴다.

`login_screen.dart`와 `add_transaction_screen.dart`가 이 방식이다.

```dart
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;   // 이 값이 "내부 상태"

  Future<void> _signIn() async {
    setState(() => _isLoading = true);   // 값을 바꾸고 화면을 다시 그려달라고 요청
    try {
      await Supabase.instance.client.auth.signInWithOtp(email: '...');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ElevatedButton(
        onPressed: _isLoading ? null : _signIn,   // 로딩 중이면 버튼 비활성화
        child: _isLoading
            ? CircularProgressIndicator()          // 로딩 중이면 스피너
            : Text('로그인 링크 보내기'),            // 아니면 텍스트
      ),
    );
  }
}
```

`setState()`가 핵심이다. `setState()` 안에서 값을 바꾸면 Flutter가 `build()`를 다시 호출해서 화면을 갱신한다. `setState()` 없이 값만 바꾸면 화면에 반영되지 않는다.

### ConsumerWidget — Riverpod Provider를 구독하는 화면

API 데이터를 가져와서 보여주는 화면에서 쓴다. `StatefulWidget` + Riverpod 연결을 한 번에 해결한다.

```dart
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {   // ref가 추가됨
    final summaryAsync = ref.watch(summaryProvider);    // Provider 구독
    // summaryAsync 값이 바뀌면 build()가 자동으로 다시 호출됨
    return Scaffold(...);
  }
}
```

**언제 무엇을 쓰나:**
- API 데이터를 보여주는 화면 → `ConsumerWidget`
- 입력 폼처럼 내부 상태(로딩, 입력값)만 있는 화면 → `StatefulWidget`
- 단순히 레이아웃이나 정적 콘텐츠만 → `StatelessWidget`

---

## 3. Riverpod — API 데이터를 화면에 연결하는 방법

이 프로젝트에서 가장 많이 만지게 되는 부분이다.

### Provider — 객체를 앱 전체에서 공유하기

Repository처럼 "만들어 두고 여러 곳에서 쓰는 객체"를 등록할 때 쓴다.

```dart
// transaction_repository.dart
final transactionRepositoryProvider = Provider(
  (ref) => TransactionRepository(),
);
```

이렇게 등록해두면 어느 화면에서든 `ref.read(transactionRepositoryProvider)`로 꺼내 쓸 수 있다. 매번 `TransactionRepository()`를 `new`로 만들지 않아도 된다.

### FutureProvider — API를 호출하고 결과를 화면에 뿌리기

비동기 작업(API 호출)의 결과를 Widget에 연결할 때 쓴다. `home_screen.dart`의 핵심 패턴이다.

```dart
// home_screen.dart
final summaryProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final repo = ref.watch(transactionRepositoryProvider);  // Repository 가져오기
  return repo.fetchSummary('2026-04');                    // API 호출
});
```

`autoDispose`는 이 Provider를 구독하는 화면이 없어지면(다른 화면으로 이동하면) 자동으로 데이터를 버리고 다음에 돌아올 때 다시 fetch한다는 뜻이다. 이걸 붙이지 않으면 앱을 종료할 때까지 데이터가 캐시된 채로 남는다.

### AsyncValue — FutureProvider의 3가지 상태

FutureProvider는 항상 3가지 상태 중 하나다. `.when()`으로 각 상태를 처리한다.

```dart
summaryAsync.when(
  // 1. API 호출 중
  loading: () => const SizedBox(
    height: 100,
    child: Center(child: CircularProgressIndicator()),
  ),
  // 2. API 호출 실패
  error: (e, st) => Container(
    color: Colors.red.shade100,
    child: Text('통계 에러 발생: $e'),
  ),
  // 3. API 호출 성공 → data에 결과가 담김
  data: (data) {
    final total = data['total'] ?? 0;
    return Text('${total}원');
  },
);
```

`loading`, `error`, `data` 세 가지를 모두 처리해야 한다. 하나라도 빠지면 컴파일 에러가 난다.

### ref.watch vs ref.read

```dart
// ref.watch: build() 안에서 써야 한다. Provider 값이 바뀌면 build()가 다시 호출된다.
final summaryAsync = ref.watch(summaryProvider);

// ref.read: 버튼 클릭 같은 이벤트 핸들러에서 1회 읽을 때 쓴다.
// build() 안에서 ref.read를 쓰면 값이 바뀌어도 화면이 갱신되지 않는다.
onPressed: () async {
  await ref.read(transactionRepositoryProvider).addTransaction(...);
}

// ref.invalidate: Provider의 캐시를 버리고 다시 fetch하게 강제한다.
// 거래를 추가/삭제한 후 목록을 새로고침할 때 쓴다.
ref.invalidate(summaryProvider);
ref.invalidate(transactionsProvider);
```

실제 사용 예: 거래 삭제 후 목록 갱신

```dart
// home_screen.dart의 onDismissed
onDismissed: (direction) {
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('삭제되었습니다.')),
    );
    ref.invalidate(summaryProvider);       // 통계 카드 새로고침
    ref.invalidate(transactionsProvider);  // 거래 목록 새로고침
  }
},
```

---

## 4. async/await — 비동기 처리

API 호출, Gemma 추론 등 시간이 걸리는 작업은 모두 `async/await`로 처리한다.

```dart
Future<void> _signIn() async {
  // setState로 로딩 시작
  setState(() => _isLoading = true);
  try {
    // await: 이 줄이 끝날 때까지 기다린 다음 다음 줄로 넘어간다
    await Supabase.instance.client.auth.signInWithOtp(email: '...');

    // await가 끝난 후 시점에는 Widget이 화면에 없을 수도 있다
    // (사용자가 뒤로 갔거나, 다른 화면으로 전환됐을 때)
    // 그래서 context를 쓰기 전에 mounted 체크를 한다
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(...);
    }
  } catch (error) {
    // API 실패, 네트워크 오류 등을 여기서 잡는다
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('에러: $error')),
      );
    }
  } finally {
    // try든 catch든 무조건 실행 → 로딩 종료
    if (mounted) setState(() => _isLoading = false);
  }
}
```

`mounted`는 StatefulWidget의 State가 현재 Widget 트리에 연결돼 있는지를 나타낸다. `async` 작업이 끝난 뒤 `context`나 `setState`를 쓸 때는 항상 `if (mounted)`를 먼저 확인해야 한다. 이걸 빠뜨리면 화면을 이미 나간 상태에서 UI를 건드리려 해서 앱이 경고를 뿜거나 크래시가 날 수 있다.

ConsumerWidget에서는 `mounted` 대신 `context.mounted`를 쓴다.

```dart
// add_transaction_screen.dart
try {
  await ref.read(transactionRepositoryProvider).addTransaction(...);
  if (context.mounted) {
    Navigator.pop(context, true);
  }
} catch (e) {
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(...);
  }
}
```

---

## 5. 화면 전환 (Navigation)

Flutter는 화면을 스택으로 관리한다. 새 화면을 열면 스택에 쌓이고, 뒤로 가면 꺼낸다.

### 다음 화면으로 이동

```dart
// home_screen.dart의 FloatingActionButton
onPressed: () async {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const AddTransactionScreen()),
  );
}
```

### 이동하고 결과값 받기

거래 추가 화면에서 저장에 성공했을 때 홈 화면의 목록을 새로고침해야 한다. 이때 `push`가 반환하는 `Future`를 `await`하면, 다음 화면이 닫힐 때 결과값을 받을 수 있다.

```dart
// home_screen.dart
final result = await Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => const AddTransactionScreen()),
);
// 이 코드는 AddTransactionScreen이 닫힌 후에 실행된다
if (result == true) {
  ref.invalidate(summaryProvider);
  ref.invalidate(transactionsProvider);
}
```

```dart
// add_transaction_screen.dart — 저장 성공 시
Navigator.pop(context, true);   // true를 실어서 이전 화면으로 돌아감
```

### StreamBuilder — 스트림을 실시간으로 구독

한 번 읽는 게 아니라 값이 바뀔 때마다 화면을 갱신해야 할 때 쓴다. 로그인 상태 감지가 대표적인 예다.

```dart
// main.dart의 AuthGate
StreamBuilder<AuthState>(
  stream: Supabase.instance.client.auth.onAuthStateChange,
  builder: (context, snapshot) {
    // 로그인 세션이 있으면 홈, 없으면 로그인 화면
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) return const HomeScreen();
    return const LoginScreen();
  },
)
```

사용자가 이메일 링크를 클릭하는 순간 Supabase가 세션을 만들고, `onAuthStateChange` 스트림에 이벤트를 발행한다. `StreamBuilder`가 이를 감지해서 `builder`를 다시 호출하고, `HomeScreen`이 화면에 나타난다. 버튼 클릭이나 `setState` 없이 자동으로 화면이 전환되는 이유가 이 구조 때문이다.

---

## 6. null 안전성 — Dart의 핵심 특성

Dart는 `null`이 될 수 있는 값과 없는 값을 타입 수준에서 구분한다.

```dart
String name = '지출';    // null 불가. null을 대입하면 컴파일 에러
String? memo = null;     // null 가능. ? 를 붙인다

// null인지 모를 때 안전하게 접근하는 방법
memo?.length            // memo가 null이면 null 반환, 아니면 length 반환
memo ?? '메모 없음'      // memo가 null이면 '메모 없음' 사용
memo!.length            // null이 절대 아니라고 단언. null이면 런타임 에러 → 가급적 피한다
```

실제 코드에서 자주 보이는 패턴:

```dart
// home_screen.dart
title: Text(tx['memo'] ?? tx['category_id'] ?? '카테고리 없음'),
// memo가 있으면 memo, null이면 category_id, 그것도 null이면 '카테고리 없음'

// ledger_intent.dart
date: json['date'] != null ? DateTime.tryParse(json['date']) : null,
// json에 date 키가 있을 때만 파싱 시도
```

---

## 7. TextEditingController — 입력 필드 다루기

`TextField`의 값을 읽거나 조작할 때 쓰는 컨트롤러다. `add_transaction_screen.dart`와 `login_screen.dart`에서 사용한다.

```dart
class _AddTransactionScreenState extends State<AddTransactionScreen> {
  // 1. 컨트롤러 생성
  final _amountController = TextEditingController();
  final _memoController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 2. TextField에 컨트롤러 연결
        TextField(
          controller: _amountController,
          keyboardType: TextInputType.number,  // 숫자 키패드 표시
          decoration: InputDecoration(
            labelText: '금액 (원)',
            border: OutlineInputBorder(),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            // 3. 값 읽기
            final text = _amountController.text.trim();  // trim(): 앞뒤 공백 제거
            final amount = int.tryParse(text);           // 숫자로 변환, 실패하면 null
            if (amount == null || amount <= 0) {
              // 유효하지 않은 입력 처리
            }
          },
          child: Text('저장'),
        ),
      ],
    );
  }
}
```

`int.tryParse()`를 쓰는 이유: 사용자가 "만원"처럼 숫자가 아닌 걸 입력했을 때 앱이 터지지 않고 `null`을 반환해 안전하게 처리할 수 있기 때문이다. `int.parse()`는 변환 실패 시 예외를 던진다.

---

## 8. 프로젝트 파일 구조와 데이터 흐름

```
lib/
├── main.dart                          # 앱 시작점. ProviderScope로 감싸야 Riverpod 작동
├── core/
│   ├── constants/categories.dart      # food, transport 같은 카테고리 고정값
│   └── network/dio_client.dart        # HTTP 클라이언트 설정 (baseUrl, JWT 헤더 등)
├── domain/
│   └── agent/ledger_intent.dart       # Gemma가 뱉은 JSON → Dart 객체로 변환하는 클래스
├── data/
│   ├── local/                         # Drift (SQLite) 로컬 DB 정의
│   └── repositories/
│       └── transaction_repository.dart # API 호출 로직만 모아둔 곳
└── presentation/
    ├── auth/login_screen.dart
    ├── home/home_screen.dart
    └── transaction/add_transaction_screen.dart
```

**화면에서 데이터가 흘러가는 순서:**

```
1. HomeScreen의 build()가 호출됨
2. ref.watch(summaryProvider)가 실행됨
3. summaryProvider가 처음 구독되면 자동으로 API 호출 시작
4. 그 동안 .when()의 loading 블록이 화면에 그려짐
5. API 응답이 오면 data 블록이 화면에 그려짐
6. 거래를 추가/삭제하면 ref.invalidate(summaryProvider) 호출
7. 3번부터 반복
```

---

## 9. 자주 보이는 패턴 요약

| 상황 | 코드 |
|------|------|
| 화면에서 API 데이터 보여주기 | `FutureProvider` 정의 → `ref.watch()` → `.when()` |
| 버튼 누르면 API 호출 | `ref.read(provider).method()` |
| API 성공 후 목록 새로고침 | `ref.invalidate(provider)` |
| 화면 이동 | `Navigator.push(context, MaterialPageRoute(...))` |
| 화면 닫으면서 결과 전달 | `Navigator.pop(context, true)` |
| async 후 UI 건드리기 | `if (mounted)` 또는 `if (context.mounted)` 먼저 확인 |
| TextField 값 읽기 | `controller.text.trim()` |
| 하단 알림 표시 | `ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(...)))` |
| 확인 다이얼로그 | `showDialog()` + `AlertDialog` |
