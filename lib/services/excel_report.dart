import 'package:excel/excel.dart';
import '../data/inventory_store.dart';

class ExcelReport {
  static List<int> build(List<Row> items, List<Row> movements) {
    final book = Excel.createExcel();
    book.rename('Sheet1', 'Inventory');
    void add(String sheet, List<Object> values) {
      book[sheet].appendRow(values
          .map<CellValue>((v) => switch (v) {
                int n => IntCellValue(n),
                double n => DoubleCellValue(n),
                _ => TextCellValue(v.toString()),
              })
          .toList());
    }

    add('Summary',
        ['Stockly report', 'All-time inventory and movement history']);
    add('Summary', ['Generated UTC', DateTime.now().toUtc().toIso8601String()]);
    add('Summary',
        ['Active items', items.where((r) => r['archived'] == 0).length]);
    add('Summary', [
      'Low-stock active items',
      items
          .where((r) =>
              r['archived'] == 0 &&
              (r['balance'] as int) <= (r['minimum'] as int))
          .length
    ]);
    add('Summary', ['Movement records', movements.length]);
    add('Inventory', [
      'ID',
      'Name',
      'SKU',
      'Category',
      'Unit',
      'Current quantity',
      'Minimum',
      'Status'
    ]);
    for (final i in items) {
      add('Inventory', [
        i['id']!,
        i['name']!,
        i['sku']!,
        i['category']!,
        i['unit']!,
        i['balance']!,
        i['minimum']!,
        i['archived'] == 1 ? 'Archived' : 'Active'
      ]);
    }
    add('Movements', [
      'ID',
      'Item ID',
      'Name',
      'SKU',
      'Unit',
      'Type',
      'Quantity',
      'Signed quantity',
      'UTC time',
      'Note',
      'Received from',
      'Sent to / Used for',
      'Reference',
    ]);

    for (final m in movements) {
      final quantity = m['quantity'] as int;
      final incoming = quantity > 0;

      final party = (m['counterparty'] as String? ?? '').trim();
      final reference = (m['reference'] as String? ?? '').trim();

      final recordedParty = party.isEmpty ? 'Not specified' : party;

      add('Movements', [
        m['id']!,
        m['item_id']!,
        m['name']!,
        m['sku']!,
        m['unit']!,
        incoming ? 'Stock in' : 'Stock out',
        quantity.abs(),
        quantity,
        m['occurred_at']!,
        m['note']!,
        incoming ? recordedParty : '',
        incoming ? '' : recordedParty,
        reference,
      ]);
    }
    for (final sheet in book.tables.values) {
      for (var c = 0; c < sheet.maxColumns; c++) {
        sheet.setColumnWidth(c, c == 2 ? 28 : 20);
      }
    }
    return book.encode()!;
  }
}
