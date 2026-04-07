class ChatMessage {
  final String chatId;
  final String peerName;
  final String peerIp;
  final String sender;
  final String text;
  final int timestampMs;
  final bool isMine;
  final bool isSystem;
  final String messageType; // text, image, video
  final String? localMediaPath;
  final String? fileName;
  final int? fileSizeBytes;

  const ChatMessage({
    required this.chatId,
    required this.peerName,
    required this.peerIp,
    required this.sender,
    required this.text,
    required this.timestampMs,
    required this.isMine,
    this.isSystem = false,
    this.messageType = 'text',
    this.localMediaPath,
    this.fileName,
    this.fileSizeBytes,
  });

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(timestampMs);

  bool get isMedia => messageType == 'image' || messageType == 'video';

  String get summaryText {
    if (isSystem) return text;
    if (messageType == 'image') {
      return text.trim().isEmpty ? '[Image]' : '📷 ${text.trim()}';
    }
    if (messageType == 'video') {
      return text.trim().isEmpty ? '[Video]' : '🎥 ${text.trim()}';
    }
    return text;
  }

  factory ChatMessage.system({
    required String chatId,
    required String peerName,
    required String peerIp,
    required String text,
  }) {
    return ChatMessage(
      chatId: chatId,
      peerName: peerName,
      peerIp: peerIp,
      sender: 'system',
      text: text,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      isMine: false,
      isSystem: true,
      messageType: 'text',
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'chatId': chatId,
      'peerName': peerName,
      'peerIp': peerIp,
      'sender': sender,
      'text': text,
      'timestampMs': timestampMs,
      'isMine': isMine,
      'isSystem': isSystem,
      'messageType': messageType,
      'localMediaPath': localMediaPath,
      'fileName': fileName,
      'fileSizeBytes': fileSizeBytes,
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      chatId: json['chatId'] as String,
      peerName: (json['peerName'] as String?) ?? '',
      peerIp: (json['peerIp'] as String?) ?? '',
      sender: json['sender'] as String,
      text: json['text'] as String,
      timestampMs: json['timestampMs'] as int,
      isMine: json['isMine'] as bool,
      isSystem: (json['isSystem'] as bool?) ?? false,
      messageType: (json['messageType'] as String?) ?? 'text',
      localMediaPath: json['localMediaPath'] as String?,
      fileName: json['fileName'] as String?,
      fileSizeBytes: json['fileSizeBytes'] as int?,
    );
  }
}