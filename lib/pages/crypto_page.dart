import 'package:flutter/material.dart';

class CryptoPage extends StatelessWidget {
  const CryptoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LanX Crypto Procedure'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const <Widget>[
          _InfoCard(
            title: '1. X25519 Key Exchange',
            body:
                'Each chat session generates a fresh ephemeral X25519 key pair. '
                'The two peers exchange public keys and independently compute the same shared secret.',
          ),
          _InfoCard(
            title: '2. HKDF-SHA256',
            body:
                'The raw ECDH shared secret is not used directly. '
                'HKDF-SHA256 derives a clean 256-bit session key for AES-GCM.',
          ),
          _InfoCard(
            title: '3. AES-GCM-256 Encryption',
            body:
                'Text messages are encrypted with AES-GCM using the session key. '
                'AES-GCM provides both confidentiality and integrity.',
          ),
          _InfoCard(
            title: '4. Media Transfer',
            body:
                'Images and videos are sent as encrypted metadata plus encrypted chunks. '
                'Each chunk uses AES-GCM with its own nonce and authenticated chunk context.',
          ),
          _InfoCard(
            title: '5. Timestamp Replay Check',
            body:
                'Each packet includes a timestamp. '
                'The receiver rejects very old, very future-dated, or duplicate timestamps.',
          ),
          _InfoCard(
            title: '6. Local Persistence',
            body:
                'Profile, recents, text history, and received media paths are stored locally. '
                'Past conversations reopen from where the user left off.',
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(body),
          ],
        ),
      ),
    );
  }
}