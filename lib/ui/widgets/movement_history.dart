import 'package:flutter/material.dart';

enum MovementFilter { all, loaded, unloaded }

class MovementHistory extends StatefulWidget {
  final List<Map<String, Object?>> movements;

  const MovementHistory({
    super.key,
    required this.movements,
  });

  @override
  State<MovementHistory> createState() => _MovementHistoryState();
}

class _MovementHistoryState extends State<MovementHistory> {
  MovementFilter filter = MovementFilter.all;

  String dateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);

    if (day == today) return 'Today';

    if (day == DateTime(today.year, today.month, today.day - 1)) {
      return 'Yesterday';
    }

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String timeLabel(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  void openReceipt(Map<String, Object?> movement) {
    final quantity = movement['quantity'] as int;
    final incoming = quantity > 0;
    final date = DateTime.parse(
      movement['occurred_at'] as String,
    ).toLocal();
    final note = movement['note'] as String;
    final party = (movement['counterparty'] as String? ?? '').trim();

    final reference = (movement['reference'] as String? ?? '').trim();

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        final theme = Theme.of(context);
        final colors = theme.colorScheme;

        Widget detail(String label, String value) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  size: 36,
                  color: colors.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  'Movement receipt',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  'Entry #${movement['id']}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 20),
                Text(
                  '${incoming ? '+' : '−'}${quantity.abs()} '
                  '${movement['unit']}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  incoming ? 'Stock loaded' : 'Stock unloaded',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                const Divider(),
                detail('Item', movement['name'] as String),
                detail('SKU', movement['sku'] as String),
                detail(
                  incoming ? 'Received from' : 'Sent to / Used for',
                  party.isEmpty ? 'Not specified' : party,
                ),
                detail(
                  'Reference',
                  reference.isEmpty ? 'Not specified' : reference,
                ),
                detail('Date', dateLabel(date)),
                detail('Time', timeLabel(date)),
                const Divider(),
                const SizedBox(height: 12),
                Text(
                  'NOTE / REFERENCE',
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.2,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  note.trim().isEmpty ? 'No note added.' : note,
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close receipt'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    // Copy before sorting so we do not modify the parent's list.
    final visible = widget.movements.where((movement) {
      final quantity = movement['quantity'] as int;

      return switch (filter) {
        MovementFilter.all => true,
        MovementFilter.loaded => quantity > 0,
        MovementFilter.unloaded => quantity < 0,
      };
    }).toList()
      ..sort((a, b) {
        final first = DateTime.parse(a['occurred_at'] as String);
        final second = DateTime.parse(b['occurred_at'] as String);

        final byDate = second.compareTo(first);

        return byDate != 0
            ? byDate
            : (b['id'] as int).compareTo(a['id'] as int);
      });

    // Build date headings and movement rows into one list.
    final entries = <Widget>[];
    String? previousDay;

    for (final movement in visible) {
      final date = DateTime.parse(
        movement['occurred_at'] as String,
      ).toLocal();

      final dayKey = '${date.year}-${date.month}-${date.day}';

      if (dayKey != previousDay) {
        entries.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
            child: Text(
              dateLabel(date),
              style: theme.textTheme.labelLarge?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );

        previousDay = dayKey;
      }

      final quantity = movement['quantity'] as int;
      final incoming = quantity > 0;
      final note = movement['note'] as String;
      final party = (movement['counterparty'] as String? ?? '').trim();

      final reference = (movement['reference'] as String? ?? '').trim();

      final partyLabel = incoming ? 'From' : 'To / For';

      entries.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Material(
            color: colors.surface,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              onTap: () => openReceipt(movement),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: incoming
                      ? colors.primaryContainer
                      : colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  incoming ? Icons.south_west : Icons.north_east,
                  color: incoming
                      ? colors.onPrimaryContainer
                      : colors.onSurfaceVariant,
                ),
              ),
              title: Text(
                movement['name'] as String,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                [
                  '${incoming ? 'Loaded' : 'Unloaded'} · ${timeLabel(date)}',
                  '$partyLabel: ${party.isEmpty ? 'Not specified' : party}',
                  if (reference.isNotEmpty) 'Ref: $reference',
                  if (note.isNotEmpty) note,
                ].join('\n'),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${incoming ? '+' : '−'}${quantity.abs()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: incoming ? colors.primary : colors.onSurface,
                      ),
                    ),
                    Text(
                      movement['unit'] as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      entries.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Divider(
            height: 1,
            color: colors.outlineVariant,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Movement ledger',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Every stock entry, in one place.',
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in MovementFilter.values)
                    ChoiceChip(
                      label: Text(
                        switch (option) {
                          MovementFilter.all => 'All entries',
                          MovementFilter.loaded => 'Loaded',
                          MovementFilter.unloaded => 'Unloaded',
                        },
                      ),
                      selected: filter == option,
                      onSelected: (_) {
                        setState(() => filter = option);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '${visible.length} '
                '${visible.length == 1 ? 'entry' : 'entries'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 44,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.movements.isEmpty
                              ? 'No movements yet'
                              : 'No matching entries',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.movements.isEmpty
                              ? 'Load or unload stock to start your ledger.'
                              : 'Try another movement filter.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: entries.length,
                  itemBuilder: (_, index) => entries[index],
                ),
        ),
      ],
    );
  }
}
