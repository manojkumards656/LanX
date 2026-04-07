class ChatSession {
  final String chatId;
  final String peerName;
  final String peerIp;
  final String lastMessage;
  final int lastTimestampMs;
  final int unreadCount;

  const ChatSession({
    required this.chatId,
    required this.peerName,
    required this.peerIp,
    required this.lastMessage,
    required this.lastTimestampMs,
    required this.unreadCount,
  });

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(lastTimestampMs);

  ChatSession copyWith({
    String? chatId,
    String? peerName,
    String? peerIp,
    String? lastMessage,
    int? lastTimestampMs,
    int? unreadCount,
  }) {
    return ChatSession(
      chatId: chatId ?? this.chatId,
      peerName: peerName ?? this.peerName,
      peerIp: peerIp ?? this.peerIp,
      lastMessage: lastMessage ?? this.lastMessage,
      lastTimestampMs: lastTimestampMs ?? this.lastTimestampMs,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'chatId': chatId,
      'peerName': peerName,
      'peerIp': peerIp,
      'lastMessage': lastMessage,
      'lastTimestampMs': lastTimestampMs,
      'unreadCount': unreadCount,
    };
  }

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    return ChatSession(
      chatId: json['chatId'] as String,
      peerName: json['peerName'] as String,
      peerIp: json['peerIp'] as String,
      lastMessage: json['lastMessage'] as String,
      lastTimestampMs: json['lastTimestampMs'] as int,
      unreadCount: json['unreadCount'] as int,
    );
  }
}