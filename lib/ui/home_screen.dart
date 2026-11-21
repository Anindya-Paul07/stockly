import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import '../data/inventory_store.dart' hide Row;
import '../services/excel_report.dart';

typedef InventoryRow = Map<String, Object?>;

String stamp(Object? value) =>
    DateTime.parse(value as String).toLocal().toString().split('.').first;

class HomeScreen extends StatefulWidget {
  final InventoryStore store;
  const HomeScreen({super.key, required this.store});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<InventoryRow> items = [], movements = [];
  String search = '';
  bool loading = true, exporting = false;
  String? loadError;
  int tab = 0;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  void message(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> refresh() async {
    try {
      final result = await widget.store.snapshot();
      if (mounted)
        setState(() {
          items = result.items.where((r) => r['archived'] == 0).toList();
          movements = result.movements.reversed.toList();
          loading = false;
          loadError = null;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          loading = false;
          loadError = 'Could not load inventory: $e';
        });
    }
  }

  Future<void> edit([InventoryRow? item]) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ItemForm(store: widget.store, item: item)));
    await refresh();
  }

  Future<void> move(InventoryRow item, bool incoming) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) =>
            MovementForm(store: widget.store, item: item, incoming: incoming)));
    await refresh();
  }

  Future<void> archive(InventoryRow item) async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Archive item?'),
                content: const Text(
                    'Its stock must be zero. History remains in reports.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Archive'))
                ]));
    if (yes != true) return;
    try {
      await widget.store.archive(item['id'] as int);
      await refresh();
    } catch (e) {
      message(e.toString());
    }
  }

  Future<void> export() async {
    setState(() => exporting = true);
    try {
      final snapshot = await widget.store.snapshot();
      final bytes = ExcelReport.build(snapshot.items, snapshot.movements);
      final dir = await getApplicationDocumentsDirectory();
      final reports =
          await Directory('${dir.path}/reports').create(recursive: true);
      final file = File(
          '${reports.path}/stockly_${DateTime.now().microsecondsSinceEpoch}.xlsx');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      message('Excel report saved on this device.');
      final box = context.findRenderObject() as RenderBox?;
      await Share.shareXFiles([
        XFile(file.path,
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
      ],
          subject: 'Stockly inventory report',
          sharePositionOrigin:
              box == null ? null : box.localToGlobal(Offset.zero) & box.size);
    } catch (e) {
      message('Report could not be generated or shared: $e');
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = items
        .where((r) => '${r['name']} ${r['sku']} ${r['category']}'
            .toLowerCase()
            .contains(search.toLowerCase()))
        .toList();
    final low = items
        .where((r) => (r['balance'] as int) <= (r['minimum'] as int))
        .length;
    return Scaffold(
      appBar:
          AppBar(title: const Text('Stockly · Offline inventory'), actions: [
        IconButton(
            tooltip: 'Refresh',
            onPressed: refresh,
            icon: const Icon(Icons.refresh)),
        IconButton(
            tooltip: 'Export Excel',
            onPressed: exporting ? null : export,
            icon: exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.file_download_outlined))
      ]),
      bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (v) => setState(() => tab = v),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.inventory_2_outlined), label: 'Inventory'),
            NavigationDestination(icon: Icon(Icons.history), label: 'History'),
            NavigationDestination(
                icon: Icon(Icons.table_view), label: 'Reports')
          ]),
      floatingActionButton: tab == 0
          ? FloatingActionButton.extended(
              onPressed: () => edit(),
              icon: const Icon(Icons.add),
              label: const Text('Add item'))
          : null,
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : loadError != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(loadError!),
                  FilledButton(onPressed: refresh, child: const Text('Retry'))
                ]))
              : tab == 2
                  ? ListView(padding: const EdgeInsets.all(20), children: [
                      const Text('Excel reports',
                          style: TextStyle(fontSize: 24)),
                      const Text(
                          'Exports all items (including archived items), current balances, low-stock count and the complete stock movement history in three worksheets. Quantities use each item’s own unit.'),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                          onPressed: exporting ? null : export,
                          icon: const Icon(Icons.download),
                          label: const Text('Generate and share .xlsx')),
                      const SizedBox(height: 16),
                      const Text(
                          'Reports are saved locally in the app documents folder. Use the share sheet to keep a copy in Files or another app. Excel exports are reports, not restorable database backups. Uninstalling the app can remove its local inventory and reports.')
                    ])
                  : tab == 1
                      ? (movements.isEmpty
                          ? const Center(child: Text('No stock movements yet.'))
                          : ListView.builder(
                              itemCount: movements.length,
                              itemBuilder: (_, index) {
                                final m = movements[index];
                                final q = m['quantity'] as int;
                                return ListTile(
                                    leading: Icon(q > 0
                                        ? Icons.south_west
                                        : Icons.north_east),
                                    title: Text(
                                        '${m['name']} · ${q > 0 ? '+' : ''}$q ${m['unit']}'),
                                    subtitle: Text(
                                        '${m['sku']} · ${stamp(m['occurred_at'])}\n${m['note']}'),
                                    isThreeLine: true);
                              }))
                      : Column(children: [
                          Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                        '${items.length} items · $low at or below minimum'),
                                    const SizedBox(height: 12),
                                    TextField(
                                        onChanged: (v) =>
                                            setState(() => search = v),
                                        decoration: const InputDecoration(
                                            labelText:
                                                'Search name, SKU or category',
                                            prefixIcon: Icon(Icons.search),
                                            border: OutlineInputBorder()))
                                  ])),
                          Expanded(
                              child: visible.isEmpty
                                  ? Center(
                                      child: Text(items.isEmpty
                                          ? 'Add your first item, then record stock in.'
                                          : 'No matching items.'))
                                  : ListView.builder(
                                      padding:
                                          const EdgeInsets.only(bottom: 90),
                                      itemCount: visible.length,
                                      itemBuilder: (context, index) {
                                        final i = visible[index];
                                        final isLow = (i['balance'] as int) <=
                                            (i['minimum'] as int);
                                        return Card(
                                            margin: const EdgeInsets.symmetric(
                                                horizontal: 16, vertical: 6),
                                            child: Padding(
                                                padding:
                                                    const EdgeInsets.all(12),
                                                child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Row(children: [
                                                        Expanded(
                                                            child: Text(
                                                                '${i['name']}',
                                                                style: Theme.of(
                                                                        context)
                                                                    .textTheme
                                                                    .titleMedium)),
                                                        PopupMenuButton<String>(
                                                            onSelected: (v) {
                                                              if (v == 'edit') {
                                                                edit(i);
                                                              } else {
                                                                archive(i);
                                                              }
                                                            },
                                                            itemBuilder:
                                                                (_) => const [
                                                                      PopupMenuItem(
                                                                          value:
                                                                              'edit',
                                                                          child:
                                                                              Text('Edit details')),
                                                                      PopupMenuItem(
                                                                          value:
                                                                              'archive',
                                                                          child:
                                                                              Text('Archive'))
                                                                    ])
                                                      ]),
                                                      Text(
                                                          '${i['sku']} · ${i['category']}'),
                                                      Text(
                                                          '${i['balance']} ${i['unit']} · Minimum ${i['minimum']}${isLow ? ' · Low stock' : ''}',
                                                          style: TextStyle(
                                                              color: isLow
                                                                  ? Theme.of(
                                                                          context)
                                                                      .colorScheme
                                                                      .error
                                                                  : null)),
                                                      Wrap(
                                                          spacing: 8,
                                                          children: [
                                                            TextButton.icon(
                                                                onPressed: () =>
                                                                    move(i,
                                                                        true),
                                                                icon: const Icon(
                                                                    Icons.add),
                                                                label: const Text(
                                                                    'Stock in')),
                                                            TextButton.icon(
                                                                onPressed: () =>
                                                                    move(i,
                                                                        false),
                                                                icon: const Icon(
                                                                    Icons
                                                                        .remove),
                                                                label: const Text(
                                                                    'Stock out'))
                                                          ])
                                                    ])));
                                      }))
                        ]),
    );
  }
}

class ItemForm extends StatefulWidget {
  final InventoryStore store;
  final InventoryRow? item;
  const ItemForm({super.key, required this.store, this.item});
  @override
  State<ItemForm> createState() => _ItemFormState();
}

class _ItemFormState extends State<ItemForm> {
  final form = GlobalKey<FormState>();
  late final controllers = [
    TextEditingController(text: widget.item?['name'] as String? ?? ''),
    TextEditingController(text: widget.item?['sku'] as String? ?? ''),
    TextEditingController(text: widget.item?['category'] as String? ?? ''),
    TextEditingController(text: widget.item?['unit'] as String? ?? 'pcs'),
    TextEditingController(text: '${widget.item?['minimum'] ?? 0}')
  ];
  bool saving = false;
  String? error;
  @override
  void dispose() {
    for (final c in controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.store.saveItem(
          id: widget.item?['id'] as int?,
          name: controllers[0].text,
          sku: controllers[1].text,
          category: controllers[2].text,
          unit: controllers[3].text,
          minimum: int.parse(controllers[4].text));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted)
        setState(() {
          saving = false;
          error = e is DatabaseException && e.isUniqueConstraintError()
              ? 'This SKU already exists (including archived items).'
              : e.toString();
        });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar:
          AppBar(title: Text(widget.item == null ? 'Add item' : 'Edit item')),
      body: Form(
          key: form,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            for (var i = 0; i < controllers.length; i++)
              Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: TextFormField(
                      controller: controllers[i],
                      readOnly: i == 3 && widget.item != null,
                      keyboardType:
                          i == 4 ? TextInputType.number : TextInputType.text,
                      decoration: InputDecoration(
                          labelText: [
                            'Name',
                            'SKU / unique code',
                            'Category (optional)',
                            'Unit (fixed after creation)',
                            'Low-stock minimum'
                          ][i],
                          border: const OutlineInputBorder()),
                      validator: (v) => i == 2
                          ? null
                          : i == 4
                              ? (int.tryParse(v ?? '') == null ||
                                      int.parse(v!) < 0
                                  ? 'Enter a non-negative whole number'
                                  : null)
                              : (v!.trim().isEmpty ? 'Required' : null))),
            if (error != null)
              Text(error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            FilledButton(
                onPressed: saving ? null : save,
                child: Text(saving ? 'Saving…' : 'Save item')),
            const Text(
                'New items start at zero. Record stock in to set the opening quantity. Quantities are whole numbers in this first version.')
          ])));
}

class MovementForm extends StatefulWidget {
  final InventoryStore store;
  final InventoryRow item;
  final bool incoming;
  const MovementForm(
      {super.key,
      required this.store,
      required this.item,
      required this.incoming});
  @override
  State<MovementForm> createState() => _MovementFormState();
}

class _MovementFormState extends State<MovementForm> {
  final form = GlobalKey<FormState>();
  final quantity = TextEditingController(), note = TextEditingController();
  bool saving = false;
  String? error;
  @override
  void dispose() {
    quantity.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.store.move(widget.item['id'] as int,
          int.parse(quantity.text) * (widget.incoming ? 1 : -1), note.text);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted)
        setState(() {
          saving = false;
          error = e.toString();
        });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: Text(widget.incoming
              ? 'Stock in / loading'
              : 'Stock out / unloading')),
      body: Form(
          key: form,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Text(
                '${widget.item['name']} · Available ${widget.item['balance']} ${widget.item['unit']}'),
            const SizedBox(height: 16),
            TextFormField(
                controller: quantity,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Quantity', border: OutlineInputBorder()),
                validator: (v) => (int.tryParse(v ?? '') ?? 0) <= 0
                    ? 'Enter a positive whole number'
                    : null),
            const SizedBox(height: 16),
            TextFormField(
                controller: note,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'Note / reference (optional)',
                    border: OutlineInputBorder())),
            if (error != null)
              Text(error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 16),
            FilledButton(
                onPressed: saving ? null : save,
                child: Text(saving ? 'Saving…' : 'Record movement')),
            const Text(
                'Movements remain in history. Correct a mistake by recording the opposite movement with an explanatory note.')
          ])));
}
