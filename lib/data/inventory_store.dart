import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

typedef Row = Map<String, Object?>;

class InventoryStore {
  final Database db;
  InventoryStore(this.db);

  static Future<InventoryStore> open({String? path}) async {
    final db = await openDatabase(
      path ?? p.join(await getDatabasesPath(), 'stockly.db'),
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute('''CREATE TABLE items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL CHECK(length(trim(name)) > 0),
          sku TEXT NOT NULL COLLATE NOCASE UNIQUE,
          category TEXT NOT NULL, unit TEXT NOT NULL,
          minimum INTEGER NOT NULL CHECK(minimum >= 0),
          archived INTEGER NOT NULL DEFAULT 0 CHECK(archived IN (0,1))
        )''');
        await db.execute('''CREATE TABLE movements (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          item_id INTEGER NOT NULL REFERENCES items(id),
          quantity INTEGER NOT NULL CHECK(quantity != 0),
          occurred_at TEXT NOT NULL, note TEXT NOT NULL
        )''');
        await db.execute('CREATE INDEX movements_item ON movements(item_id)');
      },
    );
    return InventoryStore(db);
  }

  static const _inventorySql = '''SELECT i.*, COALESCE(SUM(m.quantity),0) AS balance
    FROM items i LEFT JOIN movements m ON i.id=m.item_id''';

  Future<List<Row>> items({bool includeArchived = false}) => db.rawQuery(
    '$_inventorySql ${includeArchived ? '' : 'WHERE i.archived=0'} GROUP BY i.id ORDER BY i.name COLLATE NOCASE');

  Future<int> saveItem({int? id, required String name, required String sku,
      required String category, required String unit, required int minimum}) async {
    if (name.trim().isEmpty || sku.trim().isEmpty || unit.trim().isEmpty || minimum < 0) {
      throw ArgumentError('Enter a name, SKU, unit and non-negative minimum.');
    }
    final values = {'name': name.trim(), 'sku': sku.trim(),
      'category': category.trim(), 'unit': unit.trim(), 'minimum': minimum};
    if (id == null) return db.insert('items', values);
    final changed = await db.update('items', values, where: 'id=? AND archived=0', whereArgs: [id]);
    if (changed != 1) throw StateError('Item is no longer available.');
    return id;
  }

  Future<void> move(int itemId, int quantity, String note) async {
    if (quantity == 0) throw ArgumentError('Quantity must be greater than zero.');
    await db.transaction((txn) async {
      final item = await txn.query('items', where: 'id=? AND archived=0', whereArgs: [itemId]);
      if (item.isEmpty) throw StateError('Item is no longer available.');
      final result = await txn.rawQuery(
        'SELECT COALESCE(SUM(quantity),0) AS balance FROM movements WHERE item_id=?', [itemId]);
      final balance = result.first['balance'] as int;
      if (balance + quantity < 0) throw StateError('Insufficient stock. Available: $balance.');
      await txn.insert('movements', {'item_id': itemId, 'quantity': quantity,
        'occurred_at': DateTime.now().toUtc().toIso8601String(), 'note': note.trim()});
    });
  }

  Future<void> archive(int id) async {
    await db.transaction((txn) async {
      final rows = await txn.rawQuery('SELECT COALESCE(SUM(quantity),0) AS balance FROM movements WHERE item_id=?', [id]);
      if (rows.first['balance'] != 0) throw StateError('Unload remaining stock before archiving.');
      await txn.update('items', {'archived': 1}, where: 'id=?', whereArgs: [id]);
    });
  }

  Future<List<Row>> history({int? itemId}) => db.rawQuery('''SELECT m.*, i.name, i.sku, i.unit
    FROM movements m JOIN items i ON i.id=m.item_id
    ${itemId == null ? '' : 'WHERE i.id=?'} ORDER BY m.id DESC''', itemId == null ? [] : [itemId]);

  // Both sheets are captured from the same database transaction.
  Future<({List<Row> items, List<Row> movements})> snapshot() => db.transaction((txn) async {
    final items = await txn.rawQuery('$_inventorySql GROUP BY i.id ORDER BY i.name COLLATE NOCASE');
    final movements = await txn.rawQuery('''SELECT m.*, i.name, i.sku, i.unit
      FROM movements m JOIN items i ON i.id=m.item_id ORDER BY m.id''');
    return (items: items, movements: movements);
  });
}
