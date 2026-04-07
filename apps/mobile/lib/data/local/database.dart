// 파일 위치: lib/data/local/database.dart
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

// 방금 위에서 만든 모양 불러오기
import 'tables/transactions_table.dart';

// 나중에 Drift 빌더가 자동으로 만들어 낼 짝꿍 파일 이름
part 'database.g.dart';

@DriftDatabase(tables: [Transactions, SyncQueue])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    // 스마트폰 시스템 깊숙한 곳의 '이 앱만 쓸 수 있는 안전한 금고(폴더)' 경로 찾기
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'ledger.sqlite'));

    // 옛날 안드로이드 기종에서도 DB를 안정적으로 쓸 수 있는 호환성 패치
    applyWorkaroundToOpenSqlite3OnOldAndroidVersions();

    return NativeDatabase.createInBackground(file);
  });
}
