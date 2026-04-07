class TransferProgress {
  final String chatId;
  final String direction; // sending / receiving
  final String mediaType; // image / video
  final String fileName;
  final double progress; // 0.0 to 1.0
  final bool active;
  final bool completed;

  const TransferProgress({
    required this.chatId,
    required this.direction,
    required this.mediaType,
    required this.fileName,
    required this.progress,
    required this.active,
    this.completed = false,
  });
}