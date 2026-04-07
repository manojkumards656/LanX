import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../models/peer_device.dart';
import '../models/transfer_progress.dart';
import '../models/user_profile.dart';
import 'network_service.dart';
import 'storage_service.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this.storageService,
    required this.networkService,
    required this.defaultName,
  });

  final StorageService storageService;
  final NetworkService networkService;
  final String defaultName;

  UserProfile _profile = const UserProfile(name: 'Device', note: '');
  List<PeerDevice> _peers = <PeerDevice>[];
  List<ChatSession> _sessions = <ChatSession>[];
  String _status = 'BOOTING';

  final Map<String, List<ChatMessage>> _messagesCache =
      <String, List<ChatMessage>>{};
  final Map<String, ValueNotifier<List<ChatMessage>>> _messageNotifiers =
      <String, ValueNotifier<List<ChatMessage>>>{};
  final Map<String, TransferProgress> _progressByChat =
      <String, TransferProgress>{};

  StreamSubscription<ChatMessage>? _messageSub;
  StreamSubscription<List<PeerDevice>>? _peersSub;
  StreamSubscription<String>? _statusSub;
  StreamSubscription<TransferProgress>? _progressSub;

  String? _activeChatId;

  UserProfile get profile => _profile;
  List<PeerDevice> get peers => List<PeerDevice>.unmodifiable(_peers);
  List<ChatSession> get sessions => List<ChatSession>.unmodifiable(_sessions);
  String get status => _status;
  String? get activeChatId => _activeChatId;

  bool get isConnected => networkService.isSecureConnected;
  String? get connectedPeerIp => networkService.connectedPeerIp;
  String? get connectedPeerName => networkService.connectedPeerName;

  Future<void> initialize() async {
    _profile = await storageService.loadProfile(defaultName);
    _sessions = await storageService.loadSessions();
    networkService.localName = _profile.name;

    _messageSub = networkService.messagesStream.listen(_handleNetworkMessage);
    _peersSub = networkService.peersStream.listen((List<PeerDevice> peers) {
      _peers = peers;
      notifyListeners();
    });
    _statusSub = networkService.statusStream.listen((String status) {
      _status = status;
      notifyListeners();
    });
    _progressSub =
        networkService.progressStream.listen(_handleTransferProgress);

    await networkService.startListening();
    await networkService.discoverPeers();

    notifyListeners();
  }

  Future<void> refreshPeers() async {
    await networkService.discoverPeers();
  }

  Future<void> saveProfile({
    required String name,
    required String note,
  }) async {
    _profile = UserProfile(
      name: name.trim().isEmpty ? defaultName : name.trim(),
      note: note.trim(),
    );

    networkService.localName = _profile.name;
    await storageService.saveProfile(_profile);
    notifyListeners();
  }

  Future<void> openChat(PeerDevice peer) async {
    _activeChatId = peer.ip;
    await loadMessages(peer.ip);
    await markChatRead(peer.ip);
    notifyListeners();
  }

  Future<void> closeChat(String chatId) async {
    if (_activeChatId == chatId) {
      _activeChatId = null;
      notifyListeners();
    }
  }

  Future<void> ensureConnected(PeerDevice peer) async {
    if (connectedPeerIp == peer.ip && isConnected) {
      return;
    }

    await networkService.connectToPeer(peer);
  }

  Future<void> disconnect() async {
    await networkService.disconnect();
    notifyListeners();
  }

  Future<void> sendMessage({
    required PeerDevice peer,
    required String text,
  }) async {
    await ensureConnected(peer);
    await networkService.sendTextMessage(text);
  }

  Future<void> sendMedia({
    required PeerDevice peer,
    required String filePath,
    required String mediaType,
    String caption = '',
  }) async {
    await ensureConnected(peer);
    await networkService.sendMediaFile(
      filePath: filePath,
      mediaType: mediaType,
      caption: caption,
    );
  }

  Future<List<ChatMessage>> loadMessages(String chatId) async {
    if (_messagesCache.containsKey(chatId)) {
      return _messagesCache[chatId]!;
    }

    final List<ChatMessage> messages = await storageService.loadMessages(chatId);
    _messagesCache[chatId] = messages;
    _ensureNotifier(chatId).value = List<ChatMessage>.from(messages);
    return messages;
  }

  ValueListenable<List<ChatMessage>> messagesListenable(String chatId) {
    return _ensureNotifier(chatId);
  }

  TransferProgress? transferProgressFor(String chatId) {
    return _progressByChat[chatId];
  }

  PeerDevice peerFromSession(ChatSession session) {
    return PeerDevice(
      name: session.peerName,
      ip: session.peerIp,
    );
  }

  bool isPeerOnline(String chatId) {
    return _peers.any((PeerDevice peer) => peer.ip == chatId);
  }

  Future<void> markChatRead(String chatId) async {
    bool changed = false;

    _sessions = _sessions.map((ChatSession session) {
      if (session.chatId == chatId && session.unreadCount != 0) {
        changed = true;
        return session.copyWith(unreadCount: 0);
      }
      return session;
    }).toList();

    if (changed) {
      await storageService.saveSessions(_sessions);
      notifyListeners();
    }
  }

  Future<void> _handleNetworkMessage(ChatMessage message) async {
    final String chatId = message.chatId;
    if (chatId.isEmpty) return;

    final List<ChatMessage> current =
        List<ChatMessage>.from(_messagesCache[chatId] ?? <ChatMessage>[]);
    current.add(message);
    current.sort(
      (ChatMessage a, ChatMessage b) => a.timestampMs.compareTo(b.timestampMs),
    );

    _messagesCache[chatId] = current;
    _ensureNotifier(chatId).value = List<ChatMessage>.from(current);

    await storageService.saveMessages(chatId, current);

    if (!message.isSystem) {
      await _upsertSession(message);
    }

    notifyListeners();
  }

  Future<void> _upsertSession(ChatMessage message) async {
    final int index =
        _sessions.indexWhere((ChatSession session) => session.chatId == message.chatId);

    final bool shouldIncrementUnread =
        !message.isMine && _activeChatId != message.chatId;

    if (index == -1) {
      _sessions.add(
        ChatSession(
          chatId: message.chatId,
          peerName: message.peerName,
          peerIp: message.peerIp,
          lastMessage: message.summaryText,
          lastTimestampMs: message.timestampMs,
          unreadCount: shouldIncrementUnread ? 1 : 0,
        ),
      );
    } else {
      final ChatSession current = _sessions[index];
      _sessions[index] = current.copyWith(
        peerName: message.peerName.isNotEmpty ? message.peerName : current.peerName,
        peerIp: message.peerIp.isNotEmpty ? message.peerIp : current.peerIp,
        lastMessage: message.summaryText,
        lastTimestampMs: message.timestampMs,
        unreadCount: shouldIncrementUnread
            ? current.unreadCount + 1
            : (_activeChatId == message.chatId ? 0 : current.unreadCount),
      );
    }

    _sessions.sort(
      (ChatSession a, ChatSession b) =>
          b.lastTimestampMs.compareTo(a.lastTimestampMs),
    );

    await storageService.saveSessions(_sessions);
  }

  void _handleTransferProgress(TransferProgress progress) {
    _progressByChat[progress.chatId] = progress;
    notifyListeners();

    if (!progress.active) {
      Future<void>.delayed(const Duration(seconds: 1), () {
        final TransferProgress? current = _progressByChat[progress.chatId];
        if (identical(current, progress)) {
          _progressByChat.remove(progress.chatId);
          notifyListeners();
        }
      });
    }
  }

  ValueNotifier<List<ChatMessage>> _ensureNotifier(String chatId) {
    return _messageNotifiers.putIfAbsent(
      chatId,
      () => ValueNotifier<List<ChatMessage>>(
        List<ChatMessage>.from(_messagesCache[chatId] ?? <ChatMessage>[]),
      ),
    );
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _peersSub?.cancel();
    _statusSub?.cancel();
    _progressSub?.cancel();

    for (final ValueNotifier<List<ChatMessage>> notifier
        in _messageNotifiers.values) {
      notifier.dispose();
    }

    networkService.dispose();
    super.dispose();
  }
}