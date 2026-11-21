import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import '../data/inventory_store.dart' hide Row;
import '../services/excel_report.dart';
import 'widgets/inventory_ledger_card.dart';
import 'widgets/stock_entry_sheet.dart';
import 'widgets/inventory_search.dart';
import 'widgets/movement_history.dart';
import 'widgets/inventory_dashboard.dart';

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
  final searchController = TextEditingController();
  String search = '';
  InventoryFilter stockFilter = InventoryFilter.all;
  bool loading = true, exporting = false;
  String? loadError;
  int tab = 3;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  void message(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void openInventory(InventoryFilter filter) {
    FocusScope.of(context).unfocus();
    searchController.clear();

    setState(() {
      search = '';
      stockFilter = filter;
      tab = 0;
    });
  }

  Future<void> chooseStockItem(bool incoming) async {
    try {
      final availableItems = await widget.store.items();

      final choices = availableItems.where((item) {
        return incoming || (item['balance'] as int) > 0;
      }).toList();

      if (!mounted) return;

      if (choices.isEmpty) {
        message(
          incoming
              ? 'Add an item before loading stock.'
              : 'No items have stock available to unload.',
        );
        return;
      }

      final selected = await showModalBottomSheet<InventoryRow>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) {
          return SafeArea(
            top: false,
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.65,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Text(
                      incoming
                          ? 'Select an item to load'
                          : 'Select an item to unload',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.separated(
                      itemCount: choices.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = choices[index];

                        return ListTile(
                          title: Text(item['name'] as String),
                          subtitle: Text(
                            '${item['sku']} · '
                            '${item['balance']} ${item['unit']} available',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.pop(context, item),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

      if (!mounted || selected == null) return;

      await move(selected, incoming);
    } catch (e) {
      message('Could not load items. Please try again.');
    }
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
    try {
      // Read the latest balance before opening the form.
      final currentItems = await widget.store.items();

      InventoryRow? current;

      for (final candidate in currentItems) {
        if (candidate['id'] == item['id']) {
          current = candidate;
          break;
        }
      }

      if (!mounted) return;

      if (current == null) {
        message('This item is no longer available.');
        await refresh();
        return;
      }

      final selected = current;

      final saved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,

        // Close using the sheet's close button. This prevents accidental
        // dismissal while a database save is running.
        isDismissible: false,
        enableDrag: false,

        builder: (_) => StockEntrySheet(
          store: widget.store,
          itemId: selected['id'] as int,
          name: selected['name'] as String,
          sku: selected['sku'] as String,
          unit: selected['unit'] as String,
          available: selected['balance'] as int,
          incoming: incoming,
        ),
      );

      if (!mounted) return;

      await refresh();

      if (saved == true) {
        message(
          incoming
              ? 'Stock loaded successfully.'
              : 'Stock unloaded successfully.',
        );
      }
    } catch (e) {
      message('Could not open stock entry: $e');
    }
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

  Future<void> showItemHistory(InventoryRow item) async {
    try {
      final records = await widget.store.history(
        itemId: item['id'] as int,
      );

      if (!mounted) return;

      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheetContext) {
          final theme = Theme.of(sheetContext);
          final colors = theme.colorScheme;

          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * 0.7,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['name'] as String,
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Stock movement ledger · ${item['sku']}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: records.isEmpty
                        ? const Center(
                            child: Text('No stock movements yet.'),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                            ),
                            itemCount: records.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, index) {
                              final record = records[index];
                              final quantity = record['quantity'] as int;
                              final incoming = quantity > 0;
                              final note = record['note'] as String;

                              return ListTile(
                                isThreeLine: note.isNotEmpty,
                                leading: Icon(
                                  incoming
                                      ? Icons.south_west
                                      : Icons.north_east,
                                  color: incoming
                                      ? colors.primary
                                      : colors.onSurfaceVariant,
                                ),
                                title: Text(
                                  incoming ? 'Stock loaded' : 'Stock unloaded',
                                ),
                                subtitle: Text(
                                  '${stamp(record['occurred_at'])}'
                                  '${note.isEmpty ? '' : '\n$note'}',
                                ),
                                trailing: Text(
                                  '${incoming ? '+' : ''}$quantity'
                                  '\n${record['unit']}',
                                  textAlign: TextAlign.end,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      message('Could not load item history: $e');
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = search.trim().toLowerCase();

// Every word must match somewhere in the item's searchable details.
    final terms = query.split(RegExp(r'\s+')).where((term) => term.isNotEmpty);

    final visible = items.where((item) {
      final searchable =
          '${item['name']} ${item['sku']} ${item['category']}'.toLowerCase();

      final matchesSearch = terms.every(searchable.contains);

      final balance = item['balance'] as int;
      final minimum = item['minimum'] as int;

      final matchesFilter = switch (stockFilter) {
        InventoryFilter.all => true,
        InventoryFilter.low => balance > 0 && balance <= minimum,
        InventoryFilter.empty => balance == 0,
      };

      return matchesSearch && matchesFilter;
    }).toList();
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
        selectedIndex: const [3, 0, 1, 2].indexOf(tab),
        onDestinationSelected: (index) {
          FocusScope.of(context).unfocus();

          setState(() {
            tab = const [3, 0, 1, 2][index];
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Inventory',
          ),
          NavigationDestination(
            icon: Icon(Icons.history),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.table_view_outlined),
            selectedIcon: Icon(Icons.table_view),
            label: 'Reports',
          ),
        ],
      ),
      floatingActionButton: tab == 0
          ? FloatingActionButton.extended(
              onPressed: () => edit(),
              icon: const Icon(Icons.add),
              label: const Text('Add item'),
            )
          : null,
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : loadError != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(loadError!),
                  FilledButton(onPressed: refresh, child: const Text('Retry'))
                ]))
              : tab == 3
                  ? InventoryDashboard(
                      items: items,
                      movements: movements,
                      onViewInventory: () => openInventory(InventoryFilter.all),
                      onViewLowStock: () => openInventory(InventoryFilter.low),
                      onViewEmpty: () => openInventory(InventoryFilter.empty),
                      onLoad: () => chooseStockItem(true),
                      onUnload: () => chooseStockItem(false),
                      onAddItem: () => edit(),
                      onViewHistory: () => setState(() => tab = 1),
                    )
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
                          ? MovementHistory(movements: movements)
                          : Column(children: [
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 16, 16, 8),
                                child: InventorySearch(
                                  controller: searchController,
                                  filter: stockFilter,
                                  resultCount: visible.length,
                                  onQueryChanged: (value) {
                                    setState(() => search = value);
                                  },
                                  onFilterChanged: (value) {
                                    setState(() => stockFilter = value);
                                  },
                                ),
                              ),
                              Expanded(
                                child: visible.isEmpty
                                    ? Center(
                                        child: SingleChildScrollView(
                                          padding: const EdgeInsets.all(24),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                items.isEmpty
                                                    ? Icons.inventory_2_outlined
                                                    : Icons.search_off,
                                                size: 44,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                              const SizedBox(height: 12),
                                              Text(
                                                items.isEmpty
                                                    ? 'Your ledger is empty'
                                                    : 'No matching stock entries',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium,
                                                textAlign: TextAlign.center,
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                items.isEmpty
                                                    ? 'Add your first item to start tracking stock.'
                                                    : 'Try another name, SKU or stock filter.',
                                                textAlign: TextAlign.center,
                                              ),
                                              if (search.isNotEmpty ||
                                                  stockFilter !=
                                                      InventoryFilter.all) ...[
                                                const SizedBox(height: 12),
                                                TextButton.icon(
                                                  icon: const Icon(
                                                      Icons.restart_alt),
                                                  label: const Text(
                                                      'Reset search'),
                                                  onPressed: () {
                                                    searchController.clear();

                                                    setState(() {
                                                      search = '';
                                                      stockFilter =
                                                          InventoryFilter.all;
                                                    });
                                                  },
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      )
                                    : ListView.builder(
                                        keyboardDismissBehavior:
                                            ScrollViewKeyboardDismissBehavior
                                                .onDrag,
                                        padding:
                                            const EdgeInsets.only(bottom: 90),
                                        itemCount: visible.length,
                                        itemBuilder: (context, index) {
                                          final item = visible[index];

                                          return Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 8,
                                            ),
                                            child: InventoryLedgerCard(
                                              key: ValueKey(item['id']),
                                              name: item['name'] as String,
                                              sku: item['sku'] as String,
                                              category:
                                                  item['category'] as String,
                                              unit: item['unit'] as String,
                                              balance: item['balance'] as int,
                                              minimum: item['minimum'] as int,
                                              onOpen: () =>
                                                  showItemHistory(item),
                                              onLoad: () => move(item, true),
                                              onUnload: () => move(item, false),
                                              onEdit: () => edit(item),
                                              onArchive: () => archive(item),
                                            ),
                                          );
                                        },
                                      ),
                              ),
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
                      ][i]),
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
                decoration: const InputDecoration(labelText: 'Quantity'),
                validator: (v) => (int.tryParse(v ?? '') ?? 0) <= 0
                    ? 'Enter a positive whole number'
                    : null),
            const SizedBox(height: 16),
            TextFormField(
                controller: note,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'Note / reference (optional)')),
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
