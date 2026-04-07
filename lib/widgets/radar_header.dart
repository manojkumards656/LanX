import 'dart:math' as math;

import 'package:flutter/material.dart';

class RadarHeader extends StatefulWidget {
  const RadarHeader({
    super.key,
    required this.name,
    required this.note,
    required this.status,
    required this.peerCount,
    required this.onScan,
    required this.connected,
  });

  final String name;
  final String note;
  final String status;
  final int peerCount;
  final VoidCallback onScan;
  final bool connected;

  @override
  State<RadarHeader> createState() => _RadarHeaderState();
}

class _RadarHeaderState extends State<RadarHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color get _statusColor {
    if (widget.connected) return const Color(0xFF00FFA3);
    if (widget.status.toUpperCase().contains('SCAN')) {
      return const Color(0xFF00D1FF);
    }
    if (widget.status.toUpperCase().contains('FAILED')) {
      return const Color(0xFFFF5A7A);
    }
    return const Color(0xFFFFC857);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: <Widget>[
            SizedBox(
              height: 220,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (BuildContext context, Widget? child) {
                  return CustomPaint(
                    painter: _RadarPainter(
                      sweepAngle: _controller.value * 2 * math.pi,
                      connected: widget.connected,
                      peerCount: widget.peerCount,
                    ),
                    child: const SizedBox.expand(),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.name,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              widget.note,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF8FA9BD),
                  ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: <Widget>[
                _ChipBox(
                  label: widget.status,
                  color: _statusColor,
                ),
                _ChipBox(
                  label: 'NODES ${widget.peerCount}',
                  color: const Color(0xFF00D1FF),
                ),
                FilledButton.icon(
                  onPressed: widget.onScan,
                  icon: const Icon(Icons.radar),
                  label: const Text('Scan'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipBox extends StatelessWidget {
  const _ChipBox({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withAlpha(140)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.sweepAngle,
    required this.connected,
    required this.peerCount,
  });

  final double sweepAngle;
  final bool connected;
  final int peerCount;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = math.min(size.width, size.height) / 2 - 10;

    final Paint ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x3347D9FF);

    for (int i = 1; i <= 4; i++) {
      canvas.drawCircle(center, radius * i / 4, ringPaint);
    }

    final Paint crossPaint = Paint()
      ..color = const Color(0x2247D9FF)
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      crossPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      crossPaint,
    );

    final Rect rect = Rect.fromCircle(center: center, radius: radius);

    final Paint sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: sweepAngle,
        endAngle: sweepAngle + 0.8,
        colors: <Color>[
          Colors.transparent,
          const Color(0x2200D1FF),
          const Color(0xAA00D1FF),
        ],
      ).createShader(rect);

    canvas.drawArc(rect, sweepAngle, 0.8, true, sweepPaint);

    final Paint centerPaint = Paint()
      ..color = connected ? const Color(0xFF00FFA3) : const Color(0xFF00D1FF);

    canvas.drawCircle(center, 6, centerPaint);

    final int dots = peerCount.clamp(0, 6);
    for (int i = 0; i < dots; i++) {
      final double angle = (2 * math.pi / math.max(1, dots)) * i + 0.6;
      final double r = radius * (0.45 + (i % 2) * 0.18);
      final Offset point = Offset(
        center.dx + math.cos(angle) * r,
        center.dy + math.sin(angle) * r,
      );

      final Paint dotPaint = Paint()
        ..color = const Color(0xFF00D1FF);

      canvas.drawCircle(point, 4, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) {
    return oldDelegate.sweepAngle != sweepAngle ||
        oldDelegate.connected != connected ||
        oldDelegate.peerCount != peerCount;
  }
}