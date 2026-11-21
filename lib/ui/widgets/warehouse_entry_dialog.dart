import 'package:flutter/material.dart';

import '../../data/inventory_store.dart' hide Row;

enum WarehouseEntryMode { receive, dispatch, addItem }

enum WarehouseEntryResult { movementSaved, itemAdded }

class WarehouseEntryDialog extends StatefulWidget {
  final InventoryStore store;
  final WarehouseEntryMode mode;
  final VoidCallback onSaveError;

  const WarehouseEntryDialog({
    super.key,
    required this.store,
    required this.mode,
    required this.onSaveError,
  });

  @override
  State<WarehouseEntryDialog> createState() => _WarehouseEntryDialogState();
}

class _WarehouseEntryDialogState extends State<WarehouseEntryDialog> {
  final quantity = TextEditingController();
  final party = TextEditingController();
  final reference = TextEditingController();
  final note = TextEditingController();

  final name = TextEditingController();
  final sku = TextEditingController();
  final category = TextEditingController();
  final unit = TextEditingController(text: 'pcs');
  final minimum = TextEditingController(text: '0');

  List<Map<String, Object?>> items = [];
  int? selectedId;

  bool loading = true;
  bool saving = false;
  late bool addingItem;

  String? error;

  bool get receiving => widget.mode == WarehouseEntryMode.receive;

  Map<String, Object?>? get selectedItem {
    for (final item in items) {
      if (item['id'] == selectedId) return item;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    addingItem = widget.mode == WarehouseEntryMode.addItem;
    loadItems();
  }

  @override
  void dispose() {
    for (final controller in [
      quantity,
      party,
      reference,
      note,
      name,
      sku,
      category,
      unit,
      minimum,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> loadItems({int? selectId}) async {
    try {
      final rows = await widget.store.items();

      if (!mounted) return;

      setState(() {
        items = rows;
        if (selectId != null) selectedId = selectId;
        loading = false;
        error = null;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        loading = false;
        error = 'Could not load inventory. Close and try again.';
      });
    }
  }

  // Pop after rebuilding PopScope with saving=false.
  void closeWithResult(WarehouseEntryResult result) {
    if (!mounted) return;

    setState(() => saving = false);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(result);
    });
  }

  Future<void> saveItem() async {
    if (saving) return;

    final min = int.tryParse(minimum.text.trim());

    if (name.text.trim().isEmpty ||
        sku.text.trim().isEmpty ||
        unit.text.trim().isEmpty ||
        min == null ||
        min < 0) {
      setState(() {
        error = 'Enter a name, unique SKU, unit and valid minimum.';
      });
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      saving = true;
      error = null;
    });

    late final int id;

    try {
      id = await widget.store.saveItem(
        name: name.text,
        sku: sku.text,
        category: category.text,
        unit: unit.text,
        minimum: min,
      );
    } catch (_) {
      if (!mounted) return;

      setState(() {
        saving = false;
        error = 'Could not add item. Check that the SKU is unique.';
      });
      widget.onSaveError();
      return;
    }

    if (!mounted) return;

    if (widget.mode == WarehouseEntryMode.addItem) {
      closeWithResult(WarehouseEntryResult.itemAdded);
      return;
    }

    // Item was created from the receiving form.
    // Keep the window open and select the new item.
    await loadItems(selectId: id);

    if (!mounted) return;

    setState(() {
      addingItem = false;
      saving = false;
    });
  }

  Future<void> saveMovement() async {
    if (saving) return;

    final item = selectedItem;
    final amount = int.tryParse(quantity.text.trim());

    if (item == null || amount == null || amount <= 0) {
      setState(() {
        error = 'Choose an item and enter a positive whole quantity.';
      });
      return;
    }

    if (!receiving && amount > (item['balance'] as int)) {
      setState(() {
        error = 'Only ${item['balance']} ${item['unit']} available.';
      });
      widget.onSaveError();
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      saving = true;
      error = null;
    });

    try {
      await widget.store.move(
        item['id'] as int,
        receiving ? amount : -amount,
        note.text,
        counterparty: party.text,
        reference: reference.text,
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        saving = false;
        error = e is StateError
            ? e.message.toString()
            : 'Could not save this entry. Please try again.';
      });
      widget.onSaveError();
      return;
    }

    // The movement is already committed. Animation never saves it again.
    closeWithResult(WarehouseEntryResult.movementSaved);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    final surface = dark ? const Color(0xFF182B36) : const Color(0xFFF8F1E6);
    final ink = dark ? const Color(0xFFF8F1E6) : const Color(0xFF182B36);
    final muted = dark ? const Color(0xFFB5C2C8) : const Color(0xFF5C6E77);
    final field = dark ? const Color(0xFF243B48) : const Color(0xFFECE3D4);
    const amber = Color(0xFFFFB343);

    Widget input(
      TextEditingController controller,
      String label, {
      String? hint,
      bool number = false,
      int lines = 1,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextField(
          controller: controller,
          enabled: !saving,
          maxLines: lines,
          keyboardType: number
              ? TextInputType.number
              : lines > 1
                  ? TextInputType.multiline
                  : TextInputType.text,
          style: TextStyle(
            color: ink,
            fontWeight: FontWeight.w600,
          ),
          onChanged: (_) => setState(() => error = null),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            labelStyle: TextStyle(color: muted),
            hintStyle: TextStyle(color: muted),
            filled: true,
            fillColor: field,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      );
    }

    final item = selectedItem;
    final amount = int.tryParse(quantity.text.trim()) ?? 0;
    final balance = item?['balance'] as int? ?? 0;
    final after = balance + (receiving ? amount : -amount);

    final title = addingItem
        ? 'NEW\nSTOCK ITEM.'
        : receiving
            ? 'BRING\nSTOCK IN.'
            : 'SEND\nSTOCK OUT.';

    return PopScope(
      canPop: !saving,
      child: Dialog(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 24,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: BorderSide(
            color: ink.withOpacity(0.12),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 460,
            maxHeight: MediaQuery.sizeOf(context).height * 0.84,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: amber,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'STOCKLY / NEW ENTRY',
                        style: TextStyle(
                          color: muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: saving ? null : () => Navigator.pop(context),
                      icon: Icon(Icons.close, color: ink),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: ink,
                    fontSize: 34,
                    height: 0.98,
                    letterSpacing: -1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 24),
                if (addingItem) ...[
                  input(name, 'Item name'),
                  input(sku, 'Unique SKU'),
                  input(category, 'Category · optional'),
                  input(unit, 'Unit', hint: 'pcs, boxes, bags'),
                  input(minimum, 'Low-stock minimum', number: true),
                  Text(
                    'Starts at zero. Receive stock to add its opening quantity.',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ] else ...[
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    DropdownButtonFormField<int>(
                      value: selectedId,
                      isExpanded: true,
                      dropdownColor: surface,
                      style: TextStyle(
                        color: ink,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Choose item',
                        labelStyle: TextStyle(color: muted),
                        filled: true,
                        fillColor: field,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      items: [
                        for (final row in items)
                          DropdownMenuItem<int>(
                            value: row['id'] as int,
                            child: Text(
                              '${row['name']} · ${row['balance']} '
                              '${row['unit']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: saving
                          ? null
                          : (value) => setState(() {
                                selectedId = value;
                                error = null;
                              }),
                    ),
                  if (receiving)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: saving
                            ? null
                            : () => setState(() {
                                  addingItem = true;
                                  error = null;
                                }),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Create new item'),
                        style: TextButton.styleFrom(
                          foregroundColor: ink,
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 14),
                  input(quantity, 'Quantity', number: true),
                  if (item != null) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: field,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'BALANCE PREVIEW',
                            style: TextStyle(
                              color: muted,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$balance → $after ${item['unit']}',
                            style: TextStyle(
                              color: after < 0 ? const Color(0xFFDE5548) : ink,
                              fontSize: 25,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  input(
                    party,
                    receiving ? 'Received from' : 'Sent to / Used for',
                    hint: 'Optional person, supplier, place or project',
                  ),
                  input(reference, 'Reference · optional'),
                  input(note, 'Note · optional', lines: 2),
                ],
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    error!,
                    style: const TextStyle(
                      color: Color(0xFFDE5548),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: amber,
                    foregroundColor: const Color(0xFF182B36),
                    minimumSize: const Size(double.infinity, 54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: saving || (!addingItem && loading)
                      ? null
                      : addingItem
                          ? saveItem
                          : saveMovement,
                  child: Text(
                    saving
                        ? 'SAVING…'
                        : addingItem
                            ? 'CREATE ITEM'
                            : receiving
                                ? 'CONFIRM RECEIPT'
                                : 'CONFIRM DISPATCH',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                if (addingItem && widget.mode != WarehouseEntryMode.addItem)
                  TextButton(
                    onPressed: saving
                        ? null
                        : () => setState(() {
                              addingItem = false;
                              error = null;
                            }),
                    style: TextButton.styleFrom(foregroundColor: ink),
                    child: const Text('Back to stock entry'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
