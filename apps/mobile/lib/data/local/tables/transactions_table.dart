// 파일 위치: lib/data/local/tables/transactions_table.dart
import 'package:drift/drift.dart';

class Transactions extends Table {
  TextColumn get id => text()();
  // integer: 원(KRW) 단위 정수 저장. 서버 Turso의 amount INTEGER와 타입 일치.
  // float/double 사용 시 부동소수점 오차 버그 가능성 있으므로 정수로 고정.
  IntColumn get amount => integer()();
  TextColumn get date => text()();
  TextColumn get categoryId => text()();
  TextColumn get memo => text().nullable()();
  TextColumn get rawUtterance => text().nullable()();
  TextColumn get source => text().withDefault(const Constant('form'))();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// 오프라인 상태일 때 데이터를 잠시 쌓아두었다가 인터넷이 돌아오면 서버로 일제히 쏠 대기열(Queue) 테이블
class SyncQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get operation => text()(); // 'insert' 혹은 'delete'
  TextColumn get recordId => text()();
  TextColumn get payload => text()(); // 전송할 JSON 데이터 꾸러미
  TextColumn get idempotencyKey => text()(); // 서버 중복 등록 방지용 고유키
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
