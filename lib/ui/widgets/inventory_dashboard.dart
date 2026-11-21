import 'package:flutter/material.dart';

class InventoryDashboard extends StatelessWidget {
  final List<Map<String, Object?>> items;
  final List<Map<String, Object?>> movements;

  final VoidCallback onViewInventory;
  final VoidCallback onViewLowStock;
  final VoidCallback onViewEmpty;
  final VoidCallback onLoad;
  final VoidCallback onUnload;
  final VoidCallback onAddItem;
  final VoidCallback onViewHistory;

  const InventoryDashboard({
    super.key,
    required this.items,
    required this.movements,
    required this.onViewInventory,
    required this.onViewLowStock,
    required this.onViewEmpty,
    required this.onLoad,
    required this.onUnload,
    required this.onAddItem,
    required this.onViewHistory,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    // These definitions match the Inventory search filters.
    final lowCount = items.where((item) {
      final balance = item['balance'] as int;
      return balance > 0 && balance <= (item['minimum'] as int);
    }).length;

    final emptyCount = items.where((item) => item['balance'] == 0).length;

    final hasStock = items.any((item) => (item['balance'] as int) > 0);

    final sorted = [...movements]
      ..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));

    final recent = sorted.take(5).toList();

    Widget stat({
      required String label,
      required int count,
      required IconData icon,
      required VoidCallback onTap,
    }) {
      return Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: colors.primary, size: 22),
                const SizedBox(height: 14),
                Text(
                  '$count',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(label, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Your stock,\nat a glance.',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
            ),
            Tooltip(
              message: 'Inventory is stored on this device',
              child: Chip(
                avatar: Icon(
                  Icons.phone_android,
                  size: 16,
                  color: colors.primary,
                ),
                label: const Text('Offline'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Track what comes in and what goes out.',
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 24),

        // Adapt the cards to available width and text size.
        LayoutBuilder(
          builder: (context, constraints) {
            final largeText = MediaQuery.textScalerOf(context).scale(14) > 19;

            final columns = constraints.maxWidth < 330 || largeText ? 1 : 3;

            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;

            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: width,
                  child: stat(
                    label: 'All items',
                    count: items.length,
                    icon: Icons.inventory_2_outlined,
                    onTap: onViewInventory,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: stat(
                    label: 'Low stock',
                    count: lowCount,
                    icon: Icons.warning_amber_rounded,
                    onTap: onViewLowStock,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: stat(
                    label: 'Out of stock',
                    count: emptyCount,
                    icon: Icons.remove_shopping_cart_outlined,
                    onTap: onViewEmpty,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 28),

        Text(
          'QUICK ENTRY',
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 1.3,
            fontWeight: FontWeight.w700,
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),

        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: items.isEmpty ? null : onLoad,
              icon: const Icon(Icons.add),
              label: const Text('Load stock'),
            ),
            OutlinedButton.icon(
              onPressed: hasStock ? onUnload : null,
              icon: const Icon(Icons.remove),
              label: const Text('Unload stock'),
            ),
            TextButton.icon(
              onPressed: onAddItem,
              icon: const Icon(Icons.add_box_outlined),
              label: const Text('Add item'),
            ),
          ],
        ),

        if (items.isEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Add your first item, then load its opening stock.',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
        ],

        if (lowCount + emptyCount > 0) ...[
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.secondaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  color: colors.onSecondaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '$lowCount low-stock '
                    '${lowCount == 1 ? 'item' : 'items'} and '
                    '$emptyCount out of stock.\n'
                    'Tap a count above to review them.',
                    style: TextStyle(
                      color: colors.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: Text(
                'Recent entries',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              onPressed: onViewHistory,
              child: const Text('View all'),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (recent.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Your latest stock movements will appear here.',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          )
        else
          ...recent.map((movement) {
            final quantity = movement['quantity'] as int;
            final incoming = quantity > 0;

            final date = DateTime.parse(
              movement['occurred_at'] as String,
            ).toLocal();

            final timestamp = '${date.day}/${date.month}/${date.year} · '
                '${date.hour.toString().padLeft(2, '0')}:'
                '${date.minute.toString().padLeft(2, '0')}';

            return Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: onViewHistory,
                  leading: Icon(
                    incoming ? Icons.south_west : Icons.north_east,
                    color: incoming ? colors.primary : colors.onSurfaceVariant,
                  ),
                  title: Text(
                    movement['name'] as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${incoming ? 'Loaded' : 'Unloaded'}\n$timestamp',
                  ),
                  isThreeLine: true,
                  trailing: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 110),
                    child: Text(
                      '${incoming ? '+' : '−'}${quantity.abs()}\n'
                      '${movement['unit']}',
                      textAlign: TextAlign.end,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
              ],
            );
          }),
      ],
    );
  }
}
