import 'dart:math' as math;
import 'dart:ui' as ui;

import '../data/inventory_store.dart' hide Row;
import 'widgets/warehouse_entry_dialog.dart';

import 'package:flutter/material.dart';
import 'warehouse_inside_screen.dart';

enum WarehouseAction { receive, dispatch }

enum WarehousePhase {
  ready,
  arriving,
  unloading,
  loading,
  departing,
  success,
  error,
}

class WarehousePreviewScreen extends StatefulWidget {
  final InventoryStore store;

  const WarehousePreviewScreen({
    super.key,
    required this.store,
  });

  @override
  State<WarehousePreviewScreen> createState() => _WarehousePreviewScreenState();
}

class _WarehousePreviewScreenState extends State<WarehousePreviewScreen>
    with TickerProviderStateMixin {
  late final AnimationController _controller;

  WarehousePhase _phase = WarehousePhase.ready;
  WarehouseAction _lastAction = WarehouseAction.receive;

  bool _busy = false;
  int _runId = 0;

  // 0 = parked. 1.3 = outside the screen.
  double _vanPosition = 1.3;
  double _from = 1.3;
  double _to = 0;
  late final AnimationController _entry;
  bool _entering = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _entry = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
  }

  @override
  void dispose() {
    _runId++;
    _controller.dispose();
    _entry.dispose();
    super.dispose();
  }

  double get _currentPosition {
    if (_phase == WarehousePhase.arriving ||
        _phase == WarehousePhase.departing) {
      final t = Curves.easeInOutCubic.transform(_controller.value);
      return _from + (_to - _from) * t;
    }

    return _vanPosition;
  }

  String get _headline => switch (_phase) {
        WarehousePhase.ready => 'LET’S MOVE\nYOUR STOCK.',
        WarehousePhase.arriving => 'VAN\nARRIVING.',
        WarehousePhase.unloading => 'STOCK\nCOMING IN.',
        WarehousePhase.loading => 'LOAD IT.\nSEND IT.',
        WarehousePhase.departing => 'ON THE\nMOVE.',
        WarehousePhase.success => _lastAction == WarehouseAction.receive
            ? 'RECEIVED.\nALL SET.'
            : 'DISPATCHED.\nALL SET.',
        WarehousePhase.error => 'HOLD ON.\nCHECK ENTRY.',
      };

  String get _subtitle => switch (_phase) {
        WarehousePhase.ready => 'Your warehouse. Everything in motion.',
        WarehousePhase.arriving => 'Making room at the loading bay.',
        WarehousePhase.unloading => 'Unloading the van into your warehouse.',
        WarehousePhase.loading => 'Moving your items into the delivery van.',
        WarehousePhase.departing => 'Doors closed. Leaving the loading bay.',
        WarehousePhase.success =>
          'Animation complete. Your preview is ready to replay.',
        WarehousePhase.error =>
          'The movement stopped. Review the details and retry.',
      };

  Future<void> _enterWarehouse() async {
    if (_busy || _entering) return;

    setState(() => _entering = true);

    final reduced = MediaQuery.of(context).disableAnimations;

    try {
      if (!reduced) {
        await _entry.forward(from: 0).orCancel;
      }

      if (!mounted) return;

      await Navigator.of(context).push(
        PageRouteBuilder<void>(
          transitionDuration:
              reduced ? Duration.zero : const Duration(milliseconds: 320),
          reverseTransitionDuration:
              reduced ? Duration.zero : const Duration(milliseconds: 250),
          pageBuilder: (_, animation, secondaryAnimation) =>
              WarehouseInsideScreen(store: widget.store),
          transitionsBuilder: (
            context,
            animation,
            secondaryAnimation,
            child,
          ) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );

            return FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(
                  begin: 0.94,
                  end: 1,
                ).animate(curved),
                child: child,
              ),
            );
          },
        ),
      );

      if (!mounted) return;

      if (!reduced) {
        await _entry.reverse().orCancel;
      } else {
        _entry.reset();
      }
    } on TickerCanceled {
      // The exterior was closed during its camera animation.
    } finally {
      if (mounted) setState(() => _entering = false);
    }
  }

  Future<bool> _play(
    WarehousePhase phase,
    int milliseconds,
    int token,
  ) async {
    if (!mounted || token != _runId) return false;

    _controller.reset();

    setState(() => _phase = phase);

    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1;
      return mounted && token == _runId;
    }

    _controller.duration = Duration(milliseconds: milliseconds);

    try {
      await _controller.forward().orCancel;
    } on TickerCanceled {
      return false;
    }

    return mounted && token == _runId;
  }

  Future<void> _openEntry(WarehouseEntryMode mode) async {
    if (_busy || _entering) return;

    final addOnly = mode == WarehouseEntryMode.addItem;
    final action = mode == WarehouseEntryMode.receive
        ? WarehouseAction.receive
        : WarehouseAction.dispatch;

    final token = ++_runId;

    _controller.stop(canceled: true);

    setState(() {
      _busy = true;

      if (!addOnly) {
        _lastAction = action;
        _vanPosition = 1.3;
        _from = 1.3;
        _to = 0;
      }
    });

    // Park the van before opening the entry window.
    if (!addOnly) {
      if (!await _play(WarehousePhase.arriving, 900, token)) return;
      _vanPosition = 0;
    }

    if (!mounted || token != _runId) return;

    setState(() {
      _phase = WarehousePhase.ready;
    });

    final result = await showGeneralDialog<WarehouseEntryResult>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Stock entry',
      barrierColor: Colors.black.withOpacity(0.10),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: WarehouseEntryDialog(
            store: widget.store,
            mode: mode,
            onSaveError: () {
              // Visual feedback only. No database operation here.
              _showError();
            },
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
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );

    if (!mounted) return;

    if (result == WarehouseEntryResult.movementSaved) {
      // SQLite has ALREADY saved successfully.
      // Only play the visual sequence now.
      await _finishSavedMovement(action);
    } else {
      _reset();

      if (result == WarehouseEntryResult.itemAdded) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item created successfully.')),
        );
      }
    }
  }

  Future<void> _finishSavedMovement(WarehouseAction action) async {
    final token = ++_runId;
    _controller.stop(canceled: true);

    setState(() {
      _busy = true;
      _lastAction = action;
      _vanPosition = 0;
    });

    if (!await _play(
      action == WarehouseAction.receive
          ? WarehousePhase.unloading
          : WarehousePhase.loading,
      1800,
      token,
    )) {
      return;
    }

    _from = 0;
    _to = 1.3;

    if (!await _play(WarehousePhase.departing, 900, token)) return;

    if (!mounted || token != _runId) return;

    setState(() {
      _vanPosition = 1.3;
      _busy = false;
      _phase = WarehousePhase.success;
    });
  }

  Future<void> _showError() async {
    if (_phase == WarehousePhase.error) return;

    final position = _currentPosition;
    final token = ++_runId;

    _controller.stop(canceled: true);

    setState(() {
      _busy = true;

      // Bring the van into view if the simulation was triggered
      // before arrival or after departure.
      _vanPosition = position > 0.5 ? 0 : position;
    });

    if (!await _play(WarehousePhase.error, 750, token)) return;

    setState(() => _busy = false);
  }

  void _reset() {
    _runId++;
    _controller.stop(canceled: true);
    _controller.reset();

    setState(() {
      _phase = WarehousePhase.ready;
      _busy = false;
      _vanPosition = 1.3;
      _from = 1.3;
      _to = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final error = _phase == WarehousePhase.error;

    final background = dark ? const Color(0xFF101D2A) : const Color(0xFFF3EBDD);

    final foreground = dark ? const Color(0xFFF7F0E5) : const Color(0xFF182B36);

    final accent = error ? const Color(0xFFDE5548) : const Color(0xFFFFB343);

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 650;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  child: Row(
                    children: [
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'STOCKLY',
                          style: TextStyle(
                            color: foreground,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Illustration and headline share the same stage.
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AnimatedBuilder(
                        animation: Listenable.merge([_controller, _entry]),
                        builder: (context, _) {
                          return LayoutBuilder(
                            builder: (context, constraints) {
                              final scale = constraints.maxWidth / 430;
                              final height = constraints.maxHeight / scale;

                              // Matches the warehouse coordinates in the exterior painter.
                              final warehouseY = height * 0.79 - 246;

                              final warehouseBounds = Rect.fromLTWH(
                                17 * scale,
                                (warehouseY - 52) * scale,
                                363 * scale,
                                210 * scale,
                              );

                              final camera = Curves.easeInOutCubic.transform(
                                _entry.value,
                              );

                              final targetY =
                                  ((warehouseY + 55) / height * 2 - 1)
                                      .clamp(-1.0, 1.0)
                                      .toDouble();

                              return ClipRect(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTapUp: (details) {
                                    if (warehouseBounds
                                        .contains(details.localPosition)) {
                                      _enterWarehouse();
                                    }
                                  },
                                  child: Transform.scale(
                                    scale: 1 + camera * 2.2,
                                    alignment: Alignment(-0.08, targetY),
                                    child: CustomPaint(
                                      painter: _FullWarehousePainter(
                                        phase: _phase,
                                        progress: _controller.value,
                                        vanPosition: _currentPosition,
                                        dark: dark,
                                        accent: accent,
                                      ),
                                      child: const SizedBox.expand(),
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                      Positioned(
                        left: 70,
                        right: 24,
                        bottom: 260,
                        child: Center(
                          child: TextButton.icon(
                            onPressed:
                                _busy || _entering ? null : _enterWarehouse,
                            icon: const Icon(Icons.door_front_door_outlined),
                            label: const Text('ENTER WAREHOUSE'),
                            style: TextButton.styleFrom(
                              foregroundColor: foreground,
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: compact ? 4 : 16,
                        left: 24,
                        right: 24,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: Align(
                            key: ValueKey(_headline),
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _headline,
                              style: TextStyle(
                                color: error ? accent : foreground,
                                fontSize: compact ? 34 : 46,
                                fontWeight: FontWeight.w900,
                                height: 0.98,
                                letterSpacing: -1.6,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 24,
                        right: 24,
                        bottom: 4,
                        child: Text(
                          _subtitle,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: foreground,
                            fontSize: compact ? 13 : 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: const Color(0xFF182B36),
                            minimumSize: const Size(0, 54),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: _busy
                              ? null
                              : () => _openEntry(WarehouseEntryMode.receive),
                          icon: const Icon(Icons.south_west, size: 18),
                          label: const Text('Receive'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: foreground,
                            side: BorderSide(color: foreground),
                            minimumSize: const Size(0, 54),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: _busy
                              ? null
                              : () => _openEntry(WarehouseEntryMode.dispatch),
                          icon: const Icon(Icons.north_east, size: 18),
                          label: const Text('Dispatch'),
                        ),
                      ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _openEntry(WarehouseEntryMode.addItem),
                        icon: const Icon(Icons.add_box_outlined),
                        label: const Text('ADD ITEM'),
                        style: TextButton.styleFrom(
                          foregroundColor: foreground,
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FullWarehousePainter extends CustomPainter {
  final WarehousePhase phase;
  final double progress;
  final double vanPosition;
  final bool dark;
  final Color accent;

  _FullWarehousePainter({
    required this.phase,
    required this.progress,
    required this.vanPosition,
    required this.dark,
    required this.accent,
  });

  bool get transferring =>
      phase == WarehousePhase.loading || phase == WarehousePhase.unloading;

  bool get driving =>
      phase == WarehousePhase.arriving || phase == WarehousePhase.departing;

  bool get error => phase == WarehousePhase.error;

  void box(
    Canvas canvas,
    Rect rect,
    Color color, [
    double radius = 0,
  ]) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      Paint()..color = color,
    );
  }

  void line(
    Canvas canvas,
    Offset start,
    Offset end,
    Color color, [
    double width = 3,
  ]) {
    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  void text(
    Canvas canvas,
    String value,
    Offset offset,
    double size,
    Color color,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    painter.paint(canvas, offset);
  }

  void parcel(Canvas canvas, Offset point, [double size = 25]) {
    box(
      canvas,
      Rect.fromLTWH(point.dx, point.dy, size, size),
      const Color(0xFFCE9254),
      3,
    );

    box(
      canvas,
      Rect.fromLTWH(
        point.dx + size * 0.43,
        point.dy,
        size * 0.15,
        size,
      ),
      const Color(0xFFFFDDA9),
    );

    line(
      canvas,
      Offset(point.dx + 5, point.dy + size - 6),
      Offset(point.dx + 11, point.dy + size - 6),
      const Color(0xFF855626),
      2,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Uniform scaling keeps the van proportional.
    final scale = size.width / 430;
    final height = size.height / scale;

    canvas.save();
    canvas.scale(scale);

    // Reserve room for the headline and bottom caption.
    final roadY = height * 0.79;
    final vanY = roadY - 126;
    final warehouseY = vanY - 120;

    final ink = dark ? const Color(0xFFF7F0E5) : const Color(0xFF182B36);

    // Ground spans the screen rather than sitting inside a card.
    box(
      canvas,
      Rect.fromLTWH(0, roadY + 3, 430, height - roadY),
      dark ? const Color(0xFF1B2C39) : const Color(0xFFE5D9C5),
    );

    line(
      canvas,
      Offset(0, roadY + 3),
      Offset(430, roadY + 3),
      dark ? const Color(0xFF405260) : const Color(0xFFC8B99E),
      2,
    );

    for (var i = 0; i < 6; i++) {
      box(
        canvas,
        Rect.fromLTWH(i * 85 - 15, roadY + 27, 42, 4),
        dark ? const Color(0xFF687782) : const Color(0xFFFAF5EB),
        2,
      );
    }

    // Large warehouse in the background.
    box(
      canvas,
      Rect.fromLTWH(31, warehouseY, 333, 158),
      dark ? const Color(0xFF344958) : const Color(0xFFB8C7C8),
      8,
    );

    final roof = Path()
      ..moveTo(17, warehouseY + 3)
      ..lineTo(193, warehouseY - 52)
      ..lineTo(380, warehouseY + 3)
      ..close();

    canvas.drawPath(
      roof,
      Paint()..color = dark ? const Color(0xFF526A78) : const Color(0xFF6C858D),
    );

    box(
      canvas,
      Rect.fromLTWH(106, warehouseY + 12, 183, 26),
      dark ? const Color(0xFF182B36) : const Color(0xFFF6F1E7),
      4,
    );

    text(
      canvas,
      'STOCKLY WAREHOUSE',
      Offset(117, warehouseY + 20),
      11,
      ink,
    );

    // Dock doorway.
    box(
      canvas,
      Rect.fromLTWH(49, warehouseY + 53, 118, 104),
      const Color(0xFF223743),
      3,
    );

    // Raised shutter.
    box(
      canvas,
      Rect.fromLTWH(49, warehouseY + 53, 118, 26),
      const Color(0xFF718C96),
    );

    for (var i = 0; i < 3; i++) {
      line(
        canvas,
        Offset(51, warehouseY + 59 + i * 7),
        Offset(165, warehouseY + 59 + i * 7),
        const Color(0xFF4C6874),
        2,
      );
    }

    parcel(canvas, Offset(72, warehouseY + 128), 26);
    parcel(canvas, Offset(101, warehouseY + 128), 26);
    parcel(canvas, Offset(87, warehouseY + 99), 26);

    // Window.
    box(
      canvas,
      Rect.fromLTWH(226, warehouseY + 57, 96, 55),
      dark ? const Color(0xFFFFCE80) : const Color(0xFFDDF0EC),
      4,
    );

    line(
      canvas,
      Offset(274, warehouseY + 57),
      Offset(274, warehouseY + 112),
      const Color(0xFF6B858D),
    );

    // Dock status light.
    canvas.drawCircle(
      Offset(185, warehouseY + 62),
      6,
      Paint()
        ..color = error ? const Color(0xFFFF6559) : const Color(0xFF79CF9B),
    );

    if (dark) {
      final glow = Path()
        ..moveTo(185, warehouseY + 68)
        ..lineTo(160, warehouseY + 157)
        ..lineTo(207, warehouseY + 157)
        ..close();

      canvas.drawPath(
        glow,
        Paint()..color = const Color(0x18FFD387),
      );
    }

    // The van occupies almost the full screen width.
    final vanX = 24 + vanPosition * 430;

    final shake =
        error ? math.sin(progress * math.pi * 10) * 6 * (1 - progress) : 0.0;

    final bounce = driving ? math.sin(progress * math.pi * 12) * 1.2 : 0.0;

    canvas.drawOval(
      Rect.fromLTWH(vanX - 2, roadY - 6, 378, 17),
      Paint()..color = dark ? const Color(0x55000000) : const Color(0x22000000),
    );

    canvas.save();
    canvas.translate(vanX + shake, vanY + bounce);

    // Main cargo body.
    box(
      canvas,
      const Rect.fromLTWH(0, 0, 249, 105),
      dark ? const Color(0xFFDAE1DF) : const Color(0xFFFCFCF6),
      13,
    );

    // Strong coloured lower panel.
    box(
      canvas,
      const Rect.fromLTWH(0, 73, 249, 32),
      accent,
      5,
    );

    // Cab.
    final cab = Path()
      ..moveTo(250, 25)
      ..lineTo(299, 25)
      ..quadraticBezierTo(311, 25, 318, 39)
      ..lineTo(346, 72)
      ..lineTo(368, 83)
      ..lineTo(368, 106)
      ..lineTo(250, 106)
      ..close();

    canvas.drawPath(cab, Paint()..color = accent);

    // Windscreen.
    final window = Path()
      ..moveTo(263, 38)
      ..lineTo(299, 38)
      ..lineTo(326, 70)
      ..lineTo(263, 70)
      ..close();

    canvas.drawPath(
      window,
      Paint()..color = const Color(0xFF203642),
    );

    line(
      canvas,
      const Offset(270, 44),
      const Offset(292, 44),
      const Color(0xFF7299A9),
      3,
    );

    // Branding is inside the illustrated van.
    text(
      canvas,
      'STOCKLY',
      const Offset(54, 24),
      27,
      const Color(0xFF203642),
    );

    text(
      canvas,
      phase == WarehousePhase.loading
          ? 'OUTBOUND'
          : phase == WarehousePhase.unloading
              ? 'INBOUND'
              : error
                  ? 'ON HOLD'
                  : 'GOODS IN MOTION',
      const Offset(57, 56),
      9,
      const Color(0xFF526773),
    );

    // Rear doors.
    if (transferring) {
      box(
        canvas,
        const Rect.fromLTWH(0, 12, 28, 78),
        const Color(0xFF263C47),
        2,
      );

      line(
        canvas,
        const Offset(0, 12),
        const Offset(-19, 27),
        const Color(0xFFB1C2C7),
        6,
      );
    } else {
      line(
        canvas,
        const Offset(9, 11),
        const Offset(9, 90),
        const Color(0xFFA8B9BE),
        2,
      );
    }

    // Door handle and bumper.
    box(
      canvas,
      const Rect.fromLTWH(265, 80, 16, 4),
      const Color(0xFFF6F2E7),
      2,
    );

    box(
      canvas,
      const Rect.fromLTWH(-3, 101, 376, 11),
      const Color(0xFF314650),
      4,
    );

    final wheelAngle = driving
        ? progress * math.pi * (phase == WarehousePhase.arriving ? -5 : 5)
        : 0.0;

    for (final wheelX in [61.0, 309.0]) {
      canvas.save();
      canvas.translate(wheelX, 112);
      canvas.rotate(wheelAngle);

      canvas.drawCircle(
        Offset.zero,
        24,
        Paint()..color = const Color(0xFF152832),
      );

      canvas.drawCircle(
        Offset.zero,
        13,
        Paint()..color = const Color(0xFFB0BDC1),
      );

      line(
        canvas,
        const Offset(-9, 0),
        const Offset(9, 0),
        const Color(0xFF526A75),
        3,
      );

      line(
        canvas,
        const Offset(0, -9),
        const Offset(0, 9),
        const Color(0xFF526A75),
        3,
      );

      canvas.restore();
    }

    final hazard = error && (progress == 1 || (progress * 6).floor().isEven);

    box(
      canvas,
      const Rect.fromLTWH(355, 83, 12, 11),
      hazard ? const Color(0xFFFFA63E) : const Color(0xFFFFE3A3),
      3,
    );

    box(
      canvas,
      const Rect.fromLTWH(0, 84, 7, 12),
      hazard ? const Color(0xFFFFA63E) : const Color(0xFFDA6356),
      2,
    );

    if (dark && driving) {
      final beam = Path()
        ..moveTo(368, 86)
        ..lineTo(428, 67)
        ..lineTo(428, 115)
        ..close();

      canvas.drawPath(
        beam,
        Paint()..color = const Color(0x25FFD999),
      );
    }

    canvas.restore();

    // Parcels travel between the rear of the van and the dock.
    if (transferring) {
      final receiving = phase == WarehousePhase.unloading;

      final vanPoint = Offset(vanX - 3, vanY + 46);
      final dockPoint = Offset(111, warehouseY + 112);

      final start = receiving ? vanPoint : dockPoint;
      final end = receiving ? dockPoint : vanPoint;

      for (var i = 0; i < 3; i++) {
        final local = ((progress - i * 0.16) / 0.68).clamp(0.0, 1.0).toDouble();

        if (local <= 0 || local >= 1) continue;

        final t = Curves.easeInOutCubic.transform(local);

        final point = Offset(
          start.dx + (end.dx - start.dx) * t,
          start.dy + (end.dy - start.dy) * t - math.sin(t * math.pi) * 35,
        );

        canvas.save();
        canvas.translate(point.dx, point.dy);
        canvas.rotate(math.sin(t * math.pi * 2) * 0.08);

        parcel(canvas, const Offset(-12, -12), 24);

        canvas.restore();
      }
    }

    // Error badge above the stopped van.
    if (error) {
      final center = Offset(vanX + 190, vanY - 25);

      canvas.drawCircle(
        center,
        24,
        Paint()..color = const Color(0xFFFFD7CE),
      );

      canvas.drawCircle(
        center,
        18,
        Paint()..color = const Color(0xFFCB453D),
      );

      line(
        canvas,
        center + const Offset(0, -9),
        center + const Offset(0, 1),
        Colors.white,
        4,
      );

      canvas.drawCircle(
        center + const Offset(0, 8),
        2,
        Paint()..color = Colors.white,
      );
    }

    if (phase == WarehousePhase.success) {
      text(
        canvas,
        '✓  MOVEMENT COMPLETE',
        Offset(105, roadY - 45),
        17,
        ink,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FullWarehousePainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.progress != progress ||
        oldDelegate.vanPosition != vanPosition ||
        oldDelegate.dark != dark ||
        oldDelegate.accent != accent;
  }
}
