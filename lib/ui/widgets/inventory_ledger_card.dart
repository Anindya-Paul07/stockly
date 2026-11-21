import 'package:flutter/material.dart';

class InventoryLedgerCard extends StatelessWidget {
  final String name;
  final String sku;
  final String category;
  final String unit;
  final int balance;
  final int minimum;

  final VoidCallback onOpen;
  final VoidCallback onLoad;
  final VoidCallback onUnload;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  const InventoryLedgerCard({
    super.key,
    required this.name,
    required this.sku,
    required this.category,
    required this.unit,
    required this.balance,
    required this.minimum,
    required this.onOpen,
    required this.onLoad,
    required this.onUnload,
    required this.onEdit,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final empty = balance == 0;
    final low = balance <= minimum;

    final status = empty
        ? 'Out of stock'
        : low
            ? 'Low stock'
            : 'In stock';

    final statusBackground =
        low ? colors.errorContainer : colors.secondaryContainer;

    final statusForeground =
        low ? colors.onErrorContainer : colors.onSecondaryContainer;

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: colors.outlineVariant),
    );

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colors.surface,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Ledger heading
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            color: colors.surfaceContainerHighest,
            child: Row(
              children: [
                Icon(
                  Icons.menu_book_outlined,
                  size: 18,
                  color: colors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'STOCK LEDGER',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Item options',
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        onEdit();
                        break;
                      case 'archive':
                        onArchive();
                        break;
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text('Edit item'),
                    ),
                    PopupMenuItem(
                      value: 'archive',
                      child: Text('Archive item'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Tappable item information
          InkWell(
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.chevron_right,
                        color: colors.onSurfaceVariant,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'SKU: $sku',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  if (category.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      category,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // Ledger balance section
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: colors.outlineVariant),
                        bottom: BorderSide(color: colors.outlineVariant),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'BALANCE ON HAND',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                            letterSpacing: 1.1,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '$balance',
                              style: theme.textTheme.headlineLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: colors.onSurface,
                              ),
                            ),
                            Text(
                              unit,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: statusBackground,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          status,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: statusForeground,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        'Minimum: $minimum $unit',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Explicit stock actions
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: onLoad,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Load'),
                ),
                OutlinedButton.icon(
                  onPressed: empty ? null : onUnload,
                  icon: const Icon(Icons.remove, size: 18),
                  label: const Text('Unload'),
                ),
                TextButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.history, size: 18),
                  label: const Text('History'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
