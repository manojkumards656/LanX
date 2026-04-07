import 'dart:io';

import 'package:flutter/material.dart';

import '../models/chat_message.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.onTap,
  });

  final ChatMessage message;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (message.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0x221ECBE1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              '> ${message.text}',
              style: const TextStyle(
                color: Color(0xFF8FA9BD),
                fontSize: 12,
              ),
            ),
          ),
        ),
      );
    }

    final Alignment alignment =
        message.isMine ? Alignment.centerRight : Alignment.centerLeft;

    final Color background =
        message.isMine ? const Color(0x3300D1FF) : const Color(0x221C3247);

    final Color border =
        message.isMine ? const Color(0x5500D1FF) : const Color(0x44274A63);

    Widget child = Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.all(12),
      constraints: const BoxConstraints(maxWidth: 300),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (!message.isMine)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                message.sender,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00D1FF),
                  fontSize: 12,
                ),
              ),
            ),
          _buildBody(),
          const SizedBox(height: 6),
          Text(
            _formatTime(message.time),
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF8FA9BD),
            ),
          ),
        ],
      ),
    );

    if (onTap != null) {
      child = GestureDetector(
        onTap: onTap,
        child: child,
      );
    }

    return Align(
      alignment: alignment,
      child: child,
    );
  }

  Widget _buildBody() {
    if (message.messageType == 'image') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildImagePreview(),
          if (message.text.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(message.text),
          ],
        ],
      );
    }

    if (message.messageType == 'video') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildVideoPreview(),
          if (message.text.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(message.text),
          ],
        ],
      );
    }

    return Text(message.text);
  }

  Widget _buildImagePreview() {
    final String? path = message.localMediaPath;
    if (path == null || !File(path).existsSync()) {
      return Container(
        height: 160,
        width: 220,
        decoration: BoxDecoration(
          color: const Color(0x221C3247),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Icon(Icons.broken_image_outlined, size: 40),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.file(
        File(path),
        height: 180,
        width: 220,
        fit: BoxFit.cover,
      ),
    );
  }

  Widget _buildVideoPreview() {
    return Container(
      height: 140,
      width: 220,
      decoration: BoxDecoration(
        color: const Color(0x221C3247),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x44274A63)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(
            Icons.play_circle_fill_rounded,
            size: 48,
            color: Color(0xFF00D1FF),
          ),
          const SizedBox(height: 8),
          Text(
            message.fileName ?? 'Video',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final String h = time.hour.toString().padLeft(2, '0');
    final String m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}