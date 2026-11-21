import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:excel/excel.dart';
import 'package:stockly/data/inventory_store.dart';
import 'package:stockly/services/excel_report.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late InventoryStore store;
  late int id;
  setUp(() async {
    store = await InventoryStore.open(path: inMemoryDatabasePath);
    id = await store.saveItem(name: 'Rice', sku: 'R001', category: 'Food', unit: 'bags', minimum: 2);
  });
  tearDown(() => store.db.close());
  test('stock cannot become negative and failed movement leaves history unchanged', () async {
    await store.move(id, 10, 'Opening');
    await store.move(id, -3, 'Used');
    await expectLater(store.move(id, -8, 'Too much'), throwsStateError);
    expect((await store.items()).single['balance'], 7);
    expect(await store.history(), hasLength(2));
  });
  test('competing withdrawals cannot overspend the balance', () async {
    await store.move(id, 5, 'Opening');
    final results = await Future.wait([3, 3].map((q) async {
      try { await store.move(id, -q, 'Concurrent'); return true; }
      on StateError { return false; }
    }));
    expect(results.where((r) => r), hasLength(1));
    expect((await store.items()).single['balance'], 2);
  });
  test('SKU is unique without case distinctions', () async {
    await expectLater(store.saveItem(name: 'Duplicate', sku: 'r001', category: '', unit: 'bags', minimum: 0), throwsA(isA<DatabaseException>()));
  });
  test('archiving requires zero balance and preserves history', () async {
    await store.move(id, 2, 'Opening');
    await expectLater(store.archive(id), throwsStateError);
    await store.move(id, -2, 'Used');
    await store.archive(id);
    expect(await store.items(), isEmpty);
    expect(await store.history(), hasLength(2));
    await expectLater(store.move(id, 1, ''), throwsStateError);
    expect((await store.snapshot()).items.single['archived'], 1);
  });
  test('Excel contains numeric quantities and literal user text', () async {
    await store.move(id, 12, '=1+1');
    final snapshot = await store.snapshot();
    final workbook = Excel.decodeBytes(ExcelReport.build(snapshot.items, snapshot.movements));
    expect(workbook.tables.keys, containsAll(['Summary', 'Inventory', 'Movements']));
    expect(workbook['Inventory'].rows[1][5]!.value, IntCellValue(12));
    expect(workbook['Movements'].rows[1][9]!.value, TextCellValue('=1+1'));
  });
  test('data survives closing and reopening a file database', () async {
    final temp = await databaseFactory.getDatabasesPath();
    final path = '$temp/stockly_persistence_test.db';
    await databaseFactory.deleteDatabase(path);
    var disk = await InventoryStore.open(path: path);
    try {
      final item = await disk.saveItem(name: 'Box', sku: 'B1', category: '', unit: 'pcs', minimum: 0);
      await disk.move(item, 4, 'Opening');
      await disk.db.close();
      disk = await InventoryStore.open(path: path);
      expect((await disk.items()).single['balance'], 4);
    } finally {
      await disk.db.close();
      await databaseFactory.deleteDatabase(path);
    }
  });
}
