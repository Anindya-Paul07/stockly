import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/inventory_store.dart' hide Row;
import '../services/excel_report.dart';

typedef WarehouseRecord = Map<String, Object?>;

class WarehouseInsideScreen extends StatefulWidget {
  final InventoryStore store;

  const WarehouseInsideScreen({
    super.key,
    required this.store,
  });

  @override
  State<WarehouseInsideScreen> createState() => _WarehouseInsideScreenState();
}

class _WarehouseInsideScreenState extends State<WarehouseInsideScreen>
    with TickerProviderStateMixin {
  late final AnimationController _ambient;
  late final AnimationController _printer;

  Timer? _timer;

  List<WarehouseRecord> _items = [];
  List<WarehouseRecord> _movements = [];

  bool _loading = true;
  bool _reading = false;
  bool _exporting = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    );

    _printer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    _refresh();

    // Refresh the previews from SQLite, not from animation frames.
    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refresh(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (MediaQuery.of(context).disableAnimations) {
      _ambient.stop();
    } else if (!_ambient.isAnimating) {
      _ambient.repeat();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ambient.dispose();
    _printer.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_reading) return;
    _reading = true;

    try {
      final snapshot = await widget.store.snapshot();

      final movements = [...snapshot.movements]..sort(
          (a, b) => (b['id'] as int).compareTo(a['id'] as int),
        );

      if (!mounted) return;

      setState(() {
        _items = snapshot.items.where((item) => item['archived'] == 0).toList();
        _movements = movements;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = 'Could not refresh warehouse data.';
      });
    } finally {
      _reading = false;
    }
  }

  void _message(String value) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value)),
    );
  }

  String _date(Object? value) {
    final date = DateTime.parse(value as String).toLocal();

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}  '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  Map<String, int> get _unitTotals {
    final totals = <String, int>{};

    for (final item in _items) {
      final unit = item['unit'] as String;
      totals[unit] = (totals[unit] ?? 0) + (item['balance'] as int);
    }

    return totals;
  }

  WarehouseRecord? _latest(bool incoming) {
    for (final movement in _movements) {
      if (((movement['quantity'] as int) > 0) == incoming) {
        return movement;
      }
    }

    return null;
  }

  Future<void> _paper(
    String title,
    List<Widget> children,
  ) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close paper',
      barrierColor: Colors.black.withOpacity(0.3),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (context, animation, secondaryAnimation) {
        return BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 9, sigmaY: 9),
          child: Dialog(
            backgroundColor: const Color(0xFF8D603D),
            surfaceTintColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 600,
                maxHeight: MediaQuery.sizeOf(context).height * 0.84,
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ColoredBox(
                  color: const Color(0xFFFFF5D9),
                  child: CustomPaint(
                    painter: const _RuledPaperPainter(),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 16, 20, 24),
                      child: DefaultTextStyle(
                        style: const TextStyle(
                          color: Color(0xFF27343B),
                          fontSize: 15,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    style: const TextStyle(
                                      fontFamily: 'Caveat',
                                      fontWeight: FontWeight.w700,
                                      fontSize: 34,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Close paper',
                                  onPressed: () => Navigator.pop(context),
                                  icon: const Icon(
                                    Icons.close,
                                    color: Color(0xFF27343B),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            ...children,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );

        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(
              begin: 0.90,
              end: 1,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Widget _fact(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_box_outlined,
            size: 21,
            color: Color(0xFF557563),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    letterSpacing: 1,
                    color: Color(0xFF68726D),
                  ),
                ),
                const SizedBox(height: 3),
                SelectableText(
                  value,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openMovement(WarehouseRecord movement) async {
    final q = movement['quantity'] as int;
    final incoming = q > 0;
    final party = (movement['counterparty'] as String? ?? '').trim();
    final reference = (movement['reference'] as String? ?? '').trim();
    final note = (movement['note'] as String? ?? '').trim();

    await _paper('Movement #${movement['id']}', [
      Text(
        '${incoming ? '+' : '−'}${q.abs()} ${movement['unit']}',
        style: const TextStyle(
          fontFamily: 'Caveat',
          fontWeight: FontWeight.w700,
          fontSize: 44,
        ),
      ),
      const SizedBox(height: 20),
      _fact('Movement', incoming ? 'Received' : 'Dispatched / used'),
      _fact('Item', movement['name'] as String),
      _fact('SKU', movement['sku'] as String),
      _fact('Recorded at', _date(movement['occurred_at'])),
      _fact(
        incoming ? 'Received from' : 'Sent to / Used for',
        party.isEmpty ? 'Not specified' : party,
      ),
      _fact('Reference', reference.isEmpty ? 'Not specified' : reference),
      _fact('Note', note.isEmpty ? 'No note added' : note),
      const Text(
        'Recorded stock movement — these details are read-only.',
        style: TextStyle(fontSize: 12),
      ),
    ]);
  }

  Future<void> _openHistory() async {
    WarehouseRecord? selected;

    await _paper('Movement noticeboard', [
      if (_movements.isEmpty)
        const Text(
          'No movements pinned yet.',
          style: TextStyle(
            fontFamily: 'Caveat',
            fontWeight: FontWeight.w700,
            fontSize: 28,
          ),
        ),
      for (final movement in _movements)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            (movement['quantity'] as int) > 0
                ? Icons.south_west
                : Icons.north_east,
            color: const Color(0xFF27343B),
          ),
          title: Text(
            '${movement['name']}',
            style: const TextStyle(
              fontFamily: 'Caveat',
              fontWeight: FontWeight.w700,
              fontSize: 28,
              color: Color(0xFF27343B),
            ),
          ),
          subtitle: Text(
            '${movement['quantity']} ${movement['unit']}\n'
            '${_date(movement['occurred_at'])}',
            style: const TextStyle(color: Color(0xFF58645F)),
          ),
          onTap: () {
            selected = movement;
            Navigator.pop(context);
          },
        ),
    ]);

    if (!mounted || selected == null) return;

    await _openMovement(selected!);
  }

  Future<void> _openStock() async {
    final totals = _unitTotals;

    await _paper('Stock overview', [
      _fact('Active item types', '${_items.length}'),
      for (final total in totals.entries)
        _fact('Stock on hand · ${total.key}', '${total.value}'),
      const Divider(color: Color(0xFFC5B99A)),
      const SizedBox(height: 12),
      for (final item in _items)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(
            '${item['name']}\n'
            '${item['sku']} · ${item['balance']} ${item['unit']}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      if (_items.isEmpty)
        const Text('No active items yet. Add an item outside the warehouse.'),
    ]);
  }

  Future<void> _export() async {
    if (_exporting) return;

    setState(() => _exporting = true);

    try {
      final snapshot = await widget.store.snapshot();
      final bytes = ExcelReport.build(
        snapshot.items,
        snapshot.movements,
      );

      final directory = await getApplicationDocumentsDirectory();
      final reports = await Directory(
        '${directory.path}/reports',
      ).create(recursive: true);

      final file = File(
        '${reports.path}/stockly_${DateTime.now().microsecondsSinceEpoch}.xlsx',
      );

      await file.writeAsBytes(bytes, flush: true);

      if (!mounted) return;

      if (MediaQuery.of(context).disableAnimations) {
        _printer.value = 1;
      } else {
        await _printer.forward(from: 0).orCancel;
      }

      if (!mounted) return;

      _message('Excel report saved. Choose where to share or keep it.');

      final renderBox = context.findRenderObject() as RenderBox?;

      await Share.shareXFiles(
        [
          XFile(
            file.path,
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ],
        subject: 'Stockly warehouse report',
        sharePositionOrigin: renderBox == null
            ? null
            : renderBox.localToGlobal(Offset.zero) & renderBox.size,
      );
    } on TickerCanceled {
      // The screen was closed during its printer animation.
    } catch (_) {
      _message('Export or sharing failed. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  Widget _latestContent(bool incoming) {
    final movement = _latest(incoming);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          incoming ? 'LATEST IN' : 'LATEST OUT',
          style: const TextStyle(
            color: Color(0xFF9AE6B4),
            fontSize: 19,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          movement == null
              ? '—'
              : '${incoming ? '+' : '−'}'
                  '${(movement['quantity'] as int).abs()}',
          style: const TextStyle(
            color: Color(0xFFF2F7EF),
            fontSize: 48,
            height: 1,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          movement == null
              ? 'No entry yet'
              : '${movement['name']} · ${movement['unit']}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFFCEE0D7),
            fontSize: 20,
          ),
        ),
      ],
    );
  }

  Widget _monitor({
    required Widget child,
    required VoidCallback onTap,
    required String label,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: Column(
        children: [
          Expanded(
            child: Material(
              color: const Color(0xFF172D34),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(
                  color: Color(0xFF435963),
                  width: 12,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(26),
                      child: child,
                    ),
                    IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _ambient,
                        builder: (context, _) {
                          return Align(
                            alignment: Alignment(
                              0,
                              -1 + _ambient.value * 2,
                            ),
                            child: Container(
                              height: 3,
                              color: const Color(0x185DE3B0),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            width: 25,
            height: 20,
            color: const Color(0xFF435963),
          ),
          Container(
            width: 100,
            height: 10,
            decoration: BoxDecoration(
              color: const Color(0xFF435963),
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    final background = dark ? const Color(0xFF101D2A) : const Color(0xFFF3EBDD);
    final ink = dark ? const Color(0xFFF3EBDD) : const Color(0xFF182B36);

    final low = _items.where((item) {
      final balance = item['balance'] as int;
      return balance > 0 && balance <= (item['minimum'] as int);
    }).length;

    final empty = _items.where((item) => item['balance'] == 0).length;
    final notes = _movements.take(3).toList();

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: const Text('INSIDE THE WAREHOUSE'),
        backgroundColor: background,
        foregroundColor: ink,
        titleTextStyle: TextStyle(
          color: ink,
          fontWeight: FontWeight.w900,
          fontSize: 17,
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh warehouse',
            onPressed: () => _refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : InteractiveViewer(
                      minScale: 1,
                      maxScale: 2.5,
                      child: SizedBox.expand(
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: SizedBox(
                            width: 1000,
                            height: 1100,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _WarehouseRoomPainter(dark),
                                  ),
                                ),

                                // Main stock monitor.
                                Positioned(
                                  left: 40,
                                  top: 150,
                                  width: 470,
                                  height: 310,
                                  child: _monitor(
                                    label: 'Open stock overview',
                                    onTap: _openStock,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'WAREHOUSE STOCK',
                                          style: TextStyle(
                                            color: Color(0xFF9AE6B4),
                                            fontSize: 22,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        TweenAnimationBuilder<double>(
                                          tween: Tween<double>(
                                            begin: 0,
                                            end: _items.length.toDouble(),
                                          ),
                                          duration: MediaQuery.of(context)
                                                  .disableAnimations
                                              ? Duration.zero
                                              : const Duration(
                                                  milliseconds: 600,
                                                ),
                                          builder: (_, value, __) => Text(
                                            '${value.round()}',
                                            style: const TextStyle(
                                              color: Color(0xFFF3F8EC),
                                              fontSize: 102,
                                              height: 1.05,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                        const Text(
                                          'ACTIVE ITEM TYPES',
                                          style: TextStyle(
                                            color: Color(0xFFCEE0D7),
                                            fontSize: 20,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 14),
                                        Text(
                                          '$low LOW  /  $empty EMPTY',
                                          style: const TextStyle(
                                            color: Color(0xFFFFCB80),
                                            fontSize: 22,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                // Latest received monitor.
                                Positioned(
                                  left: 40,
                                  top: 495,
                                  width: 225,
                                  height: 245,
                                  child: _monitor(
                                    label: 'Latest received movement',
                                    onTap: () {
                                      final movement = _latest(true);
                                      if (movement != null) {
                                        _openMovement(movement);
                                      }
                                    },
                                    child: _latestContent(true),
                                  ),
                                ),

                                // Latest dispatched monitor.
                                Positioned(
                                  left: 285,
                                  top: 495,
                                  width: 225,
                                  height: 245,
                                  child: _monitor(
                                    label: 'Latest dispatched movement',
                                    onTap: () {
                                      final movement = _latest(false);
                                      if (movement != null) {
                                        _openMovement(movement);
                                      }
                                    },
                                    child: _latestContent(false),
                                  ),
                                ),

                                // Cork noticeboard.
                                Positioned(
                                  left: 560,
                                  top: 125,
                                  width: 390,
                                  height: 615,
                                  child: Material(
                                    color: const Color(0xFFB78450),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: const BorderSide(
                                        color: Color(0xFF725034),
                                        width: 15,
                                      ),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: InkWell(
                                      onTap: _openHistory,
                                      child: Padding(
                                        padding: const EdgeInsets.all(28),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            const Text(
                                              'Movement notices',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: Color(0xFF302B21),
                                                fontFamily: 'Caveat',
                                                fontWeight: FontWeight.w700,
                                                fontSize: 43,
                                              ),
                                            ),
                                            const SizedBox(height: 18),
                                            if (notes.isEmpty)
                                              const Text(
                                                'Nothing pinned yet.\n'
                                                'Your next movement\n'
                                                'will appear here.',
                                                style: TextStyle(
                                                  fontFamily: 'Caveat',
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 32,
                                                  color: Color(0xFF302B21),
                                                ),
                                              ),
                                            for (var i = 0;
                                                i < notes.length;
                                                i++)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 17,
                                                ),
                                                child: Transform.rotate(
                                                  angle:
                                                      i.isEven ? -0.025 : 0.025,
                                                  child: Material(
                                                    color: i.isEven
                                                        ? const Color(
                                                            0xFFFFF1BF)
                                                        : const Color(
                                                            0xFFE0EDCB),
                                                    elevation: 3,
                                                    child: InkWell(
                                                      onTap: () =>
                                                          _openMovement(
                                                        notes[i],
                                                      ),
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .all(14),
                                                        child: Text(
                                                          '${(notes[i]['quantity'] as int) > 0 ? 'Received' : 'Sent / used'}\n'
                                                          '${notes[i]['name']}\n'
                                                          '${notes[i]['quantity']} ${notes[i]['unit']}',
                                                          maxLines: 4,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                            fontFamily:
                                                                'Caveat',
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            fontSize: 30,
                                                            height: 1.05,
                                                            color: Color(
                                                              0xFF302B21,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            const Spacer(),
                                            const Text(
                                              'Tap board for all entries',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontFamily: 'Caveat',
                                                fontWeight: FontWeight.w700,
                                                fontSize: 27,
                                                color: Color(0xFF302B21),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                                // Large printer.
                                Positioned(
                                  left: 155,
                                  top: 790,
                                  width: 360,
                                  height: 250,
                                  child: Semantics(
                                    label: 'Export Excel report',
                                    button: true,
                                    child: GestureDetector(
                                      onTap: _exporting ? null : _export,
                                      child: AnimatedBuilder(
                                        animation: _printer,
                                        builder: (context, _) => CustomPaint(
                                          painter: _PrinterPainter(
                                            progress: _printer.value,
                                            busy: _exporting,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: _openStock,
                    icon: const Icon(Icons.monitor),
                    label: const Text('Stock'),
                  ),
                  TextButton.icon(
                    onPressed: _openHistory,
                    icon: const Icon(Icons.push_pin_outlined),
                    label: const Text('History'),
                  ),
                  TextButton.icon(
                    onPressed: _exporting ? null : _export,
                    icon: const Icon(Icons.print_outlined),
                    label: Text(_exporting ? 'Exporting…' : 'Excel'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WarehouseRoomPainter extends CustomPainter {
  final bool dark;

  const _WarehouseRoomPainter(this.dark);

  @override
  void paint(Canvas canvas, Size size) {
    final wall = dark ? const Color(0xFF263B49) : const Color(0xFFDED4BF);
    final floor = dark ? const Color(0xFF172C38) : const Color(0xFFC5B79B);

    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = wall,
    );

    canvas.drawRect(
      Rect.fromLTWH(0, 770, size.width, size.height - 770),
      Paint()..color = floor,
    );

    final lines = Paint()
      ..color = dark ? const Color(0xFF344B59) : const Color(0xFFCCBFA5)
      ..strokeWidth = 2;

    for (var y = 90.0; y < 770; y += 95) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        lines,
      );
    }

    // Ceiling beam.
    canvas.drawRect(
      Rect.fromLTWH(0, 30, size.width, 28),
      Paint()..color = const Color(0xFF6A6456),
    );

    // Desk beneath the monitor bank.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(15, 745, 525, 30),
        const Radius.circular(8),
      ),
      Paint()..color = const Color(0xFF8F6544),
    );

    canvas.drawRect(
      const Rect.fromLTWH(45, 775, 25, 230),
      Paint()..color = const Color(0xFF725034),
    );

    canvas.drawRect(
      const Rect.fromLTWH(485, 775, 25, 230),
      Paint()..color = const Color(0xFF725034),
    );

    // Lamp and warm light.
    canvas.drawLine(
      const Offset(780, 58),
      const Offset(780, 90),
      Paint()
        ..color = const Color(0xFF6A6456)
        ..strokeWidth = 7,
    );

    canvas.drawOval(
      const Rect.fromLTWH(725, 85, 110, 28),
      Paint()..color = const Color(0xFFFFCB80),
    );

    // Decorative storage crates.
    for (var i = 0; i < 3; i++) {
      final rect = Rect.fromLTWH(650 + i * 75, 900, 66, 80);

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(5)),
        Paint()..color = const Color(0xFFC38B50),
      );

      canvas.drawRect(
        Rect.fromLTWH(rect.left + 27, rect.top, 12, rect.height),
        Paint()..color = const Color(0xFFEAC593),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WarehouseRoomPainter oldDelegate) =>
      oldDelegate.dark != dark;
}

class _RuledPaperPainter extends CustomPainter {
  const _RuledPaperPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x228A9B9D)
      ..strokeWidth = 1;

    for (var y = 50.0; y < size.height; y += 32) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint,
      );
    }

    canvas.drawLine(
      const Offset(14, 0),
      Offset(14, size.height),
      Paint()
        ..color = const Color(0x44D97067)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _RuledPaperPainter oldDelegate) => false;
}

class _PrinterPainter extends CustomPainter {
  final double progress;
  final bool busy;

  const _PrinterPainter({
    required this.progress,
    required this.busy,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 360, size.height / 250);

    void rect(Rect bounds, Color color, [double radius = 0]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(bounds, Radius.circular(radius)),
        Paint()..color = color,
      );
    }

    // Printer chassis.
    rect(
      const Rect.fromLTWH(15, 80, 330, 135),
      const Color(0xFF405763),
      20,
    );

    rect(
      const Rect.fromLTWH(40, 58, 280, 50),
      const Color(0xFF6B838D),
      10,
    );

    rect(
      const Rect.fromLTWH(55, 114, 250, 15),
      const Color(0xFF172D34),
      5,
    );

    // Paper grows out of the output slot.
    final paperHeight = 30 + progress * 72;

    rect(
      Rect.fromLTWH(80, 126, 200, paperHeight),
      const Color(0xFFFFF5D9),
      2,
    );

    for (var i = 0; i < 4; i++) {
      final y = 140 + i * 14.0;
      if (y < 126 + paperHeight - 6) {
        canvas.drawLine(
          Offset(98, y),
          Offset(258, y),
          Paint()
            ..color = const Color(0xFFB7B5A4)
            ..strokeWidth = 3,
        );
      }
    }

    canvas.drawCircle(
      const Offset(310, 100),
      6,
      Paint()..color = busy ? const Color(0xFFFFB343) : const Color(0xFF8CE3B2),
    );

    final text = TextPainter(
      text: const TextSpan(
        text: 'EXPORT EXCEL',
        style: TextStyle(
          color: Color(0xFFF4EBD8),
          fontSize: 20,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    text.paint(canvas, const Offset(90, 218));

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PrinterPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.busy != busy;
}
