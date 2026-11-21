import 'package:flutter/material.dart';

import '../../data/inventory_store.dart' hide Row;

class StockEntrySheet extends StatefulWidget {
  final InventoryStore store;
  final int itemId;
  final String name;
  final String sku;
  final String unit;
  final int available;
  final bool incoming;

  const StockEntrySheet({
    super.key,
    required this.store,
    required this.itemId,
    required this.name,
    required this.sku,
    required this.unit,
    required this.available,
    required this.incoming,
  });

  @override
  State<StockEntrySheet> createState() => _StockEntrySheetState();
}

class _StockEntrySheetState extends State<StockEntrySheet> {
  final quantityController = TextEditingController();
  final noteController = TextEditingController();
  final referenceController = TextEditingController();

  String counterparty = '';
  List<String> savedNames = [];
  String? namesWarning;

  bool saving = false;
  String? error;

  int? get quantity => int.tryParse(quantityController.text.trim());

  bool get insufficient =>
      !widget.incoming && quantity != null && quantity! > widget.available;

  bool get valid => quantity != null && quantity! > 0 && !insufficient;

  int get afterBalance {
    final value = quantity;

    if (value == null || value <= 0) return widget.available;

    return widget.available + (widget.incoming ? value : -value);
  }

  @override
  void initState() {
    super.initState();
    loadSavedNames();
  }

  @override
  void dispose() {
    quantityController.dispose();
    noteController.dispose();
    referenceController.dispose();
    super.dispose();
  }

  void selectQuantity(int value) {
    quantityController.value = TextEditingValue(
      text: '$value',
      selection: TextSelection.collapsed(
        offset: '$value'.length,
      ),
    );

    setState(() => error = null);
  }

  Future<void> loadSavedNames() async {
    try {
      final names = await widget.store.savedCounterparties();

      if (!mounted) return;

      setState(() {
        savedNames = names;
        namesWarning = null;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        namesWarning =
            'Saved suggestions are unavailable. You can still type a name.';
      });
    }
  }

  Future<void> save() async {
    if (saving || !valid) return;

    // Capture values before starting the database operation.
    final amount = quantity!;
    final note = noteController.text.trim();
    final party = counterparty.trim();
    final reference = referenceController.text.trim();

    FocusScope.of(context).unfocus();

    setState(() {
      saving = true;
      error = null;
    });

    try {
      // The database checks stock again inside its transaction.
      await widget.store.move(
        widget.itemId,
        widget.incoming ? amount : -amount,
        note,
        counterparty: party,
        reference: reference,
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        saving = false;
        error = e is StateError
            ? e.message.toString()
            : 'Could not save this movement. Please try again.';
      });

      return;
    }

    if (!mounted) return;

    // Allow PopScope to rebuild before closing the sheet.
    setState(() => saving = false);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final action = widget.incoming ? 'Load' : 'Unload';

    final typed = quantityController.text.trim();
    final invalidNumber =
        typed.isNotEmpty && (quantity == null || quantity! <= 0);

    final String? quantityError = insufficient
        ? 'Only ${widget.available} ${widget.unit} available.'
        : invalidNumber
            ? 'Enter a positive whole number.'
            : null;

    return PopScope(
      canPop: !saving,
      child: SafeArea(
        top: false,
        child: Padding(
          // Move the sheet content above the keyboard.
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        widget.incoming ? Icons.south_west : Icons.north_east,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$action stock',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            widget.name,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: saving ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'SKU: ${widget.sku}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),

                TextField(
                  controller: quantityController,
                  enabled: !saving,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Quantity',
                    hintText: '0',
                    suffixText: widget.unit,
                    errorText: quantityError,
                  ),
                  onChanged: (_) => setState(() => error = null),
                ),
                const SizedBox(height: 10),

                // Each shortcut SETS the quantity.
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final value in [1, 5, 10])
                      ChoiceChip(
                        label: Text('$value'),
                        selected: quantity == value,
                        onSelected: saving ||
                                (!widget.incoming && value > widget.available)
                            ? null
                            : (_) => selectQuantity(value),
                      ),
                    if (!widget.incoming && widget.available > 0)
                      ActionChip(
                        label: const Text('All available'),
                        onPressed: saving
                            ? null
                            : () => selectQuantity(widget.available),
                      ),
                  ],
                ),
                const SizedBox(height: 20),

                // Ledger-style balance preview
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: insufficient
                        ? colors.errorContainer
                        : colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'BALANCE PREVIEW',
                        style: theme.textTheme.labelSmall?.copyWith(
                          letterSpacing: 1.2,
                          color: insufficient
                              ? colors.onErrorContainer
                              : colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '${widget.available}',
                            style: theme.textTheme.headlineSmall,
                          ),
                          Icon(
                            Icons.arrow_forward,
                            color: insufficient
                                ? colors.onErrorContainer
                                : colors.primary,
                          ),
                          Text(
                            '$afterBalance ${widget.unit}',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: insufficient
                                  ? colors.onErrorContainer
                                  : colors.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        insufficient
                            ? 'Not enough stock for this withdrawal.'
                            : 'Available now → after this entry',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: insufficient
                              ? colors.onErrorContainer
                              : colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                Autocomplete<String>(
                  optionsBuilder: (value) {
                    final query = value.text.trim().toLowerCase();

                    return savedNames
                        .where((name) => name.toLowerCase().contains(query))
                        .take(8);
                  },
                  onSelected: (value) {
                    counterparty = value;
                  },
                  fieldViewBuilder: (
                    context,
                    controller,
                    focusNode,
                    onFieldSubmitted,
                  ) {
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      enabled: !saving,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      onChanged: (value) {
                        counterparty = value;
                      },
                      decoration: InputDecoration(
                        labelText: widget.incoming
                            ? 'Received from'
                            : 'Sent to / Used for',
                        hintText: widget.incoming
                            ? 'Supplier, person or location'
                            : 'Customer, project, location or purpose',
                        helperText: namesWarning ??
                            'Select a saved name or type a new one. Optional.',
                        helperMaxLines: 3,
                        prefixIcon: Icon(
                          widget.incoming
                              ? Icons.call_received
                              : Icons.call_made,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: referenceController,
                  enabled: !saving,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Reference number',
                    hintText: 'Invoice, delivery or project reference',
                    helperText: 'Optional',
                    prefixIcon: Icon(Icons.receipt_long_outlined),
                  ),
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: noteController,
                  enabled: !saving,
                  minLines: 2,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Note / reference',
                    hintText: 'Optional: delivery, usage or correction',
                    alignLabelWithHint: true,
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error!,
                    style: TextStyle(color: colors.error),
                  ),
                ],
                const SizedBox(height: 24),

                FilledButton.icon(
                  onPressed: saving || !valid ? null : save,
                  icon: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : Icon(
                          widget.incoming ? Icons.add : Icons.remove,
                        ),
                  label: Text(
                    saving
                        ? 'Saving entry…'
                        : valid
                            ? '$action $quantity ${widget.unit}'
                            : '$action stock',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
