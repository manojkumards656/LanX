import 'package:flutter/material.dart';

class SessionStatusBar extends StatelessWidget {
  const SessionStatusBar({
    super.key,
    required this.connected,
    required this.peerName,
  });

  final bool connected;
  final String peerName;

  @override
  Widget build(BuildContext context) {
    final Color statusColor =
        connected ? const Color(0xFF00FFA3) : const Color(0xFFFFC857);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _StatusChip(
              label: connected ? 'SESSION ACTIVE' : 'OFFLINE HISTORY',
              color: statusColor,
            ),
            const _StatusChip(
              label: 'X25519',
              color: Color(0xFF00D1FF),
            ),
            const _StatusChip(
              label: 'AES-GCM-256',
              color: Color(0xFF00D1FF),
            ),
            const _StatusChip(
              label: 'REPLAY CHECK',
              color: Color(0xFF00D1FF),
            ),
            _StatusChip(
              label: peerName,
              color: const Color(0xFF8FA9BD),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withAlpha(120),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}