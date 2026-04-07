import 'package:flutter/material.dart';

import '../models/peer_device.dart';

class PeerCard extends StatelessWidget {
  const PeerCard({
    super.key,
    required this.peer,
    required this.onTap,
  });

  final PeerDevice peer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Row(
                  children: <Widget>[
                    Icon(Icons.devices_rounded, color: Color(0xFF00D1FF)),
                    SizedBox(width: 8),
                    Text(
                      'AVAILABLE',
                      style: TextStyle(
                        color: Color(0xFF00FFA3),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  peer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  peer.ip,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF8FA9BD),
                      ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onTap,
                    icon: const Icon(Icons.lock_open_rounded),
                    label: const Text('Open chat'),
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