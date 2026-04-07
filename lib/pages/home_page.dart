import 'package:flutter/material.dart';

import '../models/chat_session.dart';
import '../models/peer_device.dart';
import '../services/app_controller.dart';
import '../widgets/peer_card.dart';
import '../widgets/radar_header.dart';
import 'chat_page.dart';
import 'crypto_page.dart';
import 'profile_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.controller,
  });

  final AppController controller;

  Future<void> _openPeerChat(BuildContext context, PeerDevice peer) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ChatPage(
          controller: controller,
          peer: peer,
        ),
      ),
    );
  }

  Future<void> _openRecentChat(
    BuildContext context,
    ChatSession session,
  ) async {
    await _openPeerChat(context, controller.peerFromSession(session));
  }

  Future<void> _openProfile(BuildContext context) async {
  await Navigator.of(context).push(
    MaterialPageRoute<bool>(
      builder: (BuildContext context) => ProfilePage(controller: controller),
    ),
  );

  await controller.refreshPeers();
}

  Future<void> _openCrypto(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const CryptoPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('LANX Radar'),
            actions: <Widget>[
              IconButton(
                tooltip: 'Crypto',
                onPressed: () => _openCrypto(context),
                icon: const Icon(Icons.shield_moon_outlined),
              ),
              IconButton(
                tooltip: 'Profile',
                onPressed: () => _openProfile(context),
                icon: const Icon(Icons.person_outline_rounded),
              ),
            ],
          ),
          body: Column(
            children: <Widget>[
              RadarHeader(
                name: controller.profile.name,
                note: controller.profile.note,
                status: controller.status,
                peerCount: controller.peers.length,
                connected: controller.isConnected,
                onScan: controller.refreshPeers,
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 18),
                  children: <Widget>[
                    const _SectionTitle(
                      title: 'Detected Nodes',
                      icon: Icons.radar_rounded,
                    ),
                    SizedBox(
                      height: 190,
                      child: controller.peers.isEmpty
                          ? const _EmptyCard(
                              text:
                                  'No nodes found yet.\nOpen this app on another phone and tap Scan.',
                            )
                          : ListView.separated(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              scrollDirection: Axis.horizontal,
                              itemCount: controller.peers.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (BuildContext context, int index) {
                                final PeerDevice peer = controller.peers[index];
                                return PeerCard(
                                  peer: peer,
                                  onTap: () => _openPeerChat(context, peer),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 10),
                    const _SectionTitle(
                      title: 'Recent Chats',
                      icon: Icons.history_rounded,
                    ),
                    if (controller.sessions.isEmpty)
                      const _EmptyCard(
                        text: 'No saved chats yet.',
                      )
                    else
                      ...controller.sessions.map(
                        (ChatSession session) => Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                          child: Card(
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(22),
                              ),
                              onTap: () => _openRecentChat(context, session),
                              leading: CircleAvatar(
                                backgroundColor:
                                    const Color(0x2200D1FF),
                                child: Icon(
                                  controller.isPeerOnline(session.chatId)
                                      ? Icons.wifi_tethering_rounded
                                      : Icons.history_toggle_off_rounded,
                                  color: controller.isPeerOnline(session.chatId)
                                      ? const Color(0xFF00FFA3)
                                      : const Color(0xFF8FA9BD),
                                ),
                              ),
                              title: Text(session.peerName),
                              subtitle: Text(
                                session.lastMessage,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  Text(
                                    _formatTime(session.time),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  if (session.unreadCount > 0)
                                    Container(
                                      margin: const EdgeInsets.only(top: 6),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF00D1FF),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '${session.unreadCount}',
                                        style: const TextStyle(
                                          color: Colors.black,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatTime(DateTime time) {
    final DateTime now = DateTime.now();
    if (now.year == time.year &&
        now.month == time.month &&
        now.day == time.day) {
      final String h = time.hour.toString().padLeft(2, '0');
      final String m = time.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    return '${time.day}/${time.month}';
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.icon,
  });

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
      child: Row(
        children: <Widget>[
          Icon(icon, color: const Color(0xFF00D1FF)),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.text,
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Text(
              text,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}