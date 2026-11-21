import 'package:flutter/material.dart';

enum InventoryFilter {
  all,
  low,
  empty,
}

class InventorySearch extends StatelessWidget {
  final TextEditingController controller;
  final InventoryFilter filter;
  final int resultCount;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<InventoryFilter> onFilterChanged;

  const InventorySearch({
    super.key,
    required this.controller,
    required this.filter,
    required this.resultCount,
    required this.onQueryChanged,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'FIND A STOCK ENTRY',
          style: theme.textTheme.labelSmall?.copyWith(
            color: colors.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.3,
          ),
        ),
        const SizedBox(height: 10),
        SearchBar(
          controller: controller,
          hintText: 'Search name, SKU or category',
          leading: const Padding(
            padding: EdgeInsets.only(left: 8),
            child: Icon(Icons.search),
          ),
          trailing: [
            if (controller.text.isNotEmpty)
              IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close),
                onPressed: () {
                  controller.clear();
                  onQueryChanged('');
                },
              ),
          ],
          onChanged: onQueryChanged,
          onSubmitted: (_) => FocusScope.of(context).unfocus(),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in InventoryFilter.values)
              ChoiceChip(
                selected: filter == option,
                label: Text(
                  switch (option) {
                    InventoryFilter.all => 'All items',
                    InventoryFilter.low => 'Low stock',
                    InventoryFilter.empty => 'Out of stock',
                  },
                ),
                onSelected: (_) => onFilterChanged(option),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '$resultCount ${resultCount == 1 ? 'item' : 'items'} found',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
