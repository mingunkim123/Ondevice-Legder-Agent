# 프론트엔드 바이브 코딩 가이드

> AI에게 Flutter 코드를 생성시킬 때 반드시 알아야 할 최소한의 것들.
> 백엔드(Hono + Turso)는 이미 완성됐다고 가정한다.

---

## 1. 환경변수 — 하드코딩 절대 금지

Flutter에서 민감한 값은 `--dart-define`으로 주입한다. 코드에 직접 쓰지 않는다.

```dart
// ✅ 올바른 방법
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8787');

// ❌ 절대 하지 말 것
const supabaseUrl = 'https://xxxx.supabase.co';
```

실행 시:
```bash
flutter run \
  --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJxxx \
  --dart-define=API_BASE_URL=http://10.0.2.2:8787
```

플랫폼별 로컬 API 주소:
| 환경 | API_BASE_URL |
|------|-------------|
| Android 에뮬레이터 | `http://10.0.2.2:8787` (기본값) |
| iOS 시뮬레이터 | `http://localhost:8787` |
| 실기기 | `http://192.168.x.x:8787` (컴퓨터 로컬 IP) |
| 프로덕션 | `https://ledger-agent-api.xxx.workers.dev` |

---

## 2. 인증 — 반드시 이 패턴만 쓴다

### Auth Gate (필수 패턴)

로그인 여부에 따라 화면을 자동 전환하는 루트 위젯. `main.dart`의 `home:`에 넣는다.

```dart
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null) return const HomeScreen();
        return const LoginScreen();
      },
    );
  }
}
```

- `onAuthStateChange` 스트림을 구독하면 OTP 링크 클릭 → 세션 생성 순간 자동으로 HomeScreen으로 이동한다.
- `Navigator.push`로 직접 화면 전환하지 않는다. AuthGate가 자동으로 처리한다.

### JWT 자동 첨부 (Dio Interceptor)

모든 API 요청에 JWT를 붙이는 인터셉터. `DioClient`에 한 번만 설정한다.

```dart
dio.interceptors.add(InterceptorsWrapper(
  onRequest: (options, handler) async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session?.accessToken != null) {
      options.headers['Authorization'] = 'Bearer ${session!.accessToken}';
    }
    return handler.next(options);
  },
));
```

- `supabase_flutter`가 토큰 자동 갱신을 처리하므로 `currentSession.accessToken`은 항상 유효하다.
- 개별 API 호출마다 JWT를 직접 붙이지 않는다.

---

## 3. API 계약 — 이걸 어기면 서버가 400/401을 뱉는다

### 공통 헤더 (모든 요청)

```
Authorization: Bearer <JWT>
Content-Type: application/json
```

### POST 요청에만 추가 헤더

```
Idempotency-Key: <transaction id와 동일한 UUID>
```

**Idempotency-Key 규칙**: 반드시 body의 `id`와 동일한 값이어야 한다. 다르면 400.

---

### Endpoint 목록

#### `POST /api/transactions` — 거래 추가

```dart
// Request body
{
  "id": "uuid-v4-string",         // 클라이언트가 생성 (uuid 패키지)
  "amount": 12000,                 // int (원 단위 정수. double 보내면 서버에서 정수로 저장)
  "date": "2026-04-08",           // "YYYY-MM-DD" 형식만 허용
  "category_id": "food",          // 아래 카테고리 목록 중 하나만 허용
  "memo": "점심",                  // 선택, 최대 200자
  "raw_utterance": "오늘 점심...", // 선택, 자연어 원문 (에이전트 입력 시)
  "source": "form"                 // "form" 또는 "agent"
}

// Response 201 (신규 생성)
{"id": "...", "message": "Transaction created"}

// Response 200 (중복 요청, 데이터는 이미 있음)
{"id": "...", "duplicate": true}
```

#### `GET /api/transactions?month=2026-04` — 목록 조회

```dart
// Response 200
{
  "data": [
    {
      "id": "string",
      "amount": 12000,           // int
      "date": "2026-04-08",
      "category_id": "food",
      "memo": "점심",            // nullable
      "source": "form",
      "created_at": "..."
    }
  ]
}

// month 파라미터 없으면 전체 조회
```

#### `GET /api/transactions/summary?month=2026-04` — 월별 합계

```dart
// Response 200
{
  "month": "2026-04",
  "total": 56000,                // int, 데이터 없으면 0
  "by_category": [
    {"category_id": "food", "amount": 45000, "count": 5}
  ]
}

// month 파라미터 필수. 없으면 400.
```

#### `DELETE /api/transactions/:id` — 소프트 삭제

```dart
// Response 200 (성공)
{"message": "Transaction deleted"}

// Response 404 (존재하지 않거나 이미 삭제됨)
{"error": "Transaction not found"}
```

---

## 4. 데이터 타입 규칙

### amount는 반드시 int

```dart
// ✅ 올바름
final amount = int.tryParse(amountText);

// ❌ 틀림 — double로 보내면 서버 DB에 소수점이 생길 수 있음
final amount = double.tryParse(amountText);
```

서버 Turso DB: `amount INTEGER`  
로컬 Drift DB: `IntColumn get amount`  
둘 다 정수다. `double`을 보내도 현재 서버는 받지만, 타입 일관성을 위해 항상 `int`로 처리한다.

### date는 "YYYY-MM-DD" 문자열

```dart
// ✅ 올바른 날짜 생성
final now = DateTime.now();
final dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

// ❌ 서버가 400을 반환함
"date": "2026/04/08"   // 슬래시 사용
"date": "08-04-2026"   // 순서 다름
```

### id는 UUID v4

```dart
import 'package:uuid/uuid.dart';

final id = const Uuid().v4();
// Idempotency-Key 헤더와 body의 id에 동일하게 사용
```

---

## 5. 고정 카테고리 목록

서버가 이 8개 외의 값을 받으면 400을 반환한다. UI에서 직접 문자열 입력을 받지 말고 이 목록에서 선택하게 한다.

```dart
const kCategories = [
  {'id': 'food',      'label': '식비',      'emoji': '🍽️'},
  {'id': 'cafe',      'label': '카페',      'emoji': '☕'},
  {'id': 'transport', 'label': '교통비',    'emoji': '🚌'},
  {'id': 'shopping',  'label': '쇼핑',      'emoji': '🛍️'},
  {'id': 'health',    'label': '의료/건강', 'emoji': '💊'},
  {'id': 'culture',   'label': '문화/여가', 'emoji': '🎬'},
  {'id': 'utility',   'label': '생활비',    'emoji': '🏠'},
  {'id': 'etc',       'label': '기타',      'emoji': '📌'},
];
```

---

## 6. 로컬 DB (Drift) 스키마

Drift는 SQLite 위의 타입 안전한 ORM이다. 테이블 정의는 `lib/data/local/tables/transactions_table.dart`에 있다.

### Transactions 테이블

| Drift 필드 | SQLite 컬럼 | 타입 | 비고 |
|-----------|------------|------|------|
| `id` | `id` | TEXT | PK, UUID |
| `amount` | `amount` | INTEGER | 원 단위 정수 |
| `date` | `date` | TEXT | YYYY-MM-DD |
| `categoryId` | `category_id` | TEXT | |
| `memo` | `memo` | TEXT | nullable |
| `rawUtterance` | `raw_utterance` | TEXT | nullable |
| `source` | `source` | TEXT | 기본값 'form' |
| `deletedAt` | `deleted_at` | DATETIME | nullable, soft delete |
| `createdAt` | `created_at` | DATETIME | 자동 생성 |
| `updatedAt` | `updated_at` | DATETIME | 자동 생성 |

### SyncQueue 테이블 (오프라인 큐)

| Drift 필드 | 타입 | 비고 |
|-----------|------|------|
| `id` | INTEGER | PK, autoIncrement |
| `operation` | TEXT | `'insert'` 또는 `'delete'` |
| `recordId` | TEXT | transaction id |
| `payload` | TEXT | JSON 문자열 |
| `idempotencyKey` | TEXT | transaction id와 동일 |
| `status` | TEXT | `'pending'` 또는 `'failed'` |
| `retryCount` | INTEGER | 기본값 0 |
| `createdAt` | DATETIME | 자동 생성 |

### 테이블 수정 시 반드시 실행

```bash
# 테이블 정의를 변경하면 항상 재생성
dart run build_runner build --delete-conflicting-outputs
```

`database.g.dart`는 자동 생성 파일이다. 직접 수정하지 않는다.

---

## 7. 삭제 UI — 반드시 이 패턴

`Dismissible`에서 API 호출은 반드시 `confirmDismiss`에서 한다. `onDismissed`에서 하면 API 실패 시 아이템이 화면에서 이미 사라져서 복원이 불가능하다.

```dart
// ✅ 올바른 패턴
Dismissible(
  key: Key(tx['id']),
  confirmDismiss: (direction) async {
    // 1. 사용자 확인 다이얼로그
    final confirmed = await showDialog<bool>(...);
    if (confirmed != true) return false;

    // 2. API 호출
    try {
      await repository.deleteTransaction(tx['id']);
      return true;  // 성공 → 아이템 제거
    } catch (e) {
      // 실패 알림
      return false; // 실패 → 아이템 복원
    }
  },
  onDismissed: (_) {
    // confirmDismiss가 true를 반환했을 때만 호출됨
    // 여기서는 UI 갱신만
    ref.invalidate(transactionsProvider);
  },
)

// ❌ 이렇게 하면 API 실패해도 아이템이 사라짐
onDismissed: (direction) async {
  await repository.deleteTransaction(tx['id']); // 실패해도 이미 늦음
}
```

---

## 8. 상태관리 — Riverpod 사용 규칙

### FutureProvider 기본 패턴

```dart
final transactionsProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final repo = ref.watch(transactionRepositoryProvider);
  return repo.fetchTransactions(_getCurrentMonth());
});
```

### 데이터 갱신

```dart
// 저장/삭제 후 목록을 새로고침할 때
ref.invalidate(transactionsProvider);
ref.invalidate(summaryProvider);

// FutureProvider.autoDispose를 쓰면 화면을 벗어날 때 자동으로 캐시 해제됨
```

### ConsumerWidget vs StatefulWidget

```dart
// 화면 전체가 ref를 사용할 때 → ConsumerWidget
class HomeScreen extends ConsumerWidget {
  Widget build(BuildContext context, WidgetRef ref) { ... }
}

// 로컬 상태(텍스트 컨트롤러 등)가 있고 ref도 써야 할 때 → ConsumerStatefulWidget
class AddScreen extends ConsumerStatefulWidget { ... }
class _AddScreenState extends ConsumerState<AddScreen> {
  // ref는 ConsumerState에서 바로 접근 가능
}
```

`StatefulWidget` 안에 `Consumer`를 중첩하는 방식은 피한다.

---

## 9. 에러 처리 규칙

서버에서 올 수 있는 HTTP 상태 코드:

| 코드 | 의미 | 프론트 대응 |
|------|------|------------|
| 200 | 성공 (중복 요청 포함) | `duplicate: true`면 이미 저장된 것 |
| 201 | 신규 생성 성공 | 목록 갱신 |
| 400 | 입력값 오류 | 사용자에게 에러 메시지 표시 |
| 401 | 인증 실패 | 로그인 화면으로 이동 (AuthGate가 자동 처리) |
| 404 | 리소스 없음 | 이미 삭제된 것으로 처리 |
| 500 | 서버 오류 | "잠시 후 다시 시도해주세요" 메시지 |

```dart
// Dio 에러 처리 패턴
try {
  await dio.post(...);
} on DioException catch (e) {
  final statusCode = e.response?.statusCode;
  if (statusCode == 401) {
    // AuthGate가 세션 변경을 감지해서 자동 처리됨
    return;
  }
  final message = e.response?.data?['error'] ?? '알 수 없는 오류';
  throw Exception(message);
}
```

---

## 10. 알아두면 안 터지는 것들

### `mounted` 체크

비동기 작업 후 `setState`나 `ScaffoldMessenger`를 호출하기 전에 반드시 확인한다.

```dart
await someAsyncOperation();
if (context.mounted) {         // ← 이거 빠뜨리면 dispose 후 에러
  ScaffoldMessenger.of(context).showSnackBar(...);
}
```

### Supabase 초기화 전 접근 금지

`Supabase.instance.client`를 `main()`의 `Supabase.initialize()` 이전에 접근하면 크래시한다. `WidgetsFlutterBinding.ensureInitialized()`와 `Supabase.initialize()`가 `runApp()` 전에 반드시 완료되어야 한다.

### 테스트에서 MyApp 직접 실행 금지

`tester.pumpWidget(const MyApp())`은 Supabase가 초기화되지 않아서 크래시한다. 위젯 테스트는 개별 화면을 mock과 함께 테스트하거나 `ProviderScope`로 mock repository를 주입한다.

### `database.g.dart` 직접 수정 금지

이 파일은 `build_runner`가 자동 생성한다. 직접 수정해도 다음 `build_runner` 실행 시 덮어씌워진다. 항상 원본 테이블 파일(`transactions_table.dart`)만 수정한다.

### amount 금액 포맷팅

서버와 로컬 DB 모두 `int`로 저장되므로, 표시할 때만 포맷팅한다.

```dart
// 표시용
Text('${tx['amount'].toString()}원')

// 쉼표 포함 포맷
import 'package:intl/intl.dart';
final formatter = NumberFormat('#,###');
Text('${formatter.format(amount)}원')  // "12,000원"
```
