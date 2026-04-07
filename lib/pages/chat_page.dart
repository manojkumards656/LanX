import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/chat_message.dart';
import '../models/peer_device.dart';
import '../models/transfer_progress.dart';
import '../services/app_controller.dart';
import '../widgets/message_bubble.dart';
import '../widgets/session_status_bar.dart';
import 'media_viewer_page.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.controller,
    required this.peer,
  });

  final AppController controller;
  final PeerDevice peer;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();

  bool _busy = false;
  late final ValueListenable<List<ChatMessage>> _messagesListenable;

  @override
  void initState() {
    super.initState();
    _messagesListenable = widget.controller.messagesListenable(widget.peer.ip);
    _open();
    _messagesListenable.addListener(_scrollToBottomSoon);
  }

  Future<void> _open() async {
    await widget.controller.openChat(widget.peer);

    try {
      await widget.controller.ensureConnected(widget.peer);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not connect right now. Showing local history.'),
        ),
      );
    }

    _scrollToBottomSoon();
  }

  @override
  void dispose() {
    widget.controller.closeChat(widget.peer.ip);
    _messagesListenable.removeListener(_scrollToBottomSoon);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendText() async {
    final String text = _messageController.text.trim();
    if (text.isEmpty || _busy) return;

    setState(() {
      _busy = true;
    });

    try {
      await widget.controller.sendMessage(
        peer: widget.peer,
        text: text,
      );
      _messageController.clear();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message not sent. Connection failed.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _showAttachmentSheet() async {
    if (_busy) return;

    final String? action = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('Send image'),
                onTap: () {
                  Navigator.of(sheetContext).pop('image');
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: const Text('Send video'),
                onTap: () {
                  Navigator.of(sheetContext).pop('video');
                },
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;

    await Future<void>.delayed(const Duration(milliseconds: 180));

    if (action == 'image') {
      await _pickAndSendImage();
    } else if (action == 'video') {
      await _pickAndSendVideo();
    }
  }

  Future<void> _pickAndSendImage() async {
    final XFile? picked = await _picker.pickImage(
      source: ImageSource.gallery,
    );
    if (picked == null) return;

    await _sendMedia(
      filePath: picked.path,
      mediaType: 'image',
    );
  }

  Future<void> _pickAndSendVideo() async {
    final XFile? picked = await _picker.pickVideo(
      source: ImageSource.gallery,
    );
    if (picked == null) return;

    await _sendMedia(
      filePath: picked.path,
      mediaType: 'video',
    );
  }

  Future<void> _sendMedia({
    required String filePath,
    required String mediaType,
  }) async {
    if (_busy) return;

    final String caption = _messageController.text.trim();

    setState(() {
      _busy = true;
    });

    try {
      await widget.controller.sendMedia(
        peer: widget.peer,
        filePath: filePath,
        mediaType: mediaType,
        caption: caption,
      );
      _messageController.clear();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mediaType == 'image' ? 'Image not sent.' : 'Video not sent.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  bool get _connectedToThisPeer =>
      widget.controller.connectedPeerIp == widget.peer.ip &&
      widget.controller.isConnected;

  void _openMedia(ChatMessage message) {
    if (!message.isMedia || message.localMediaPath == null) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => MediaViewerPage(message: message),
      ),
    );
  }

  Widget _buildProgressBar() {
    final TransferProgress? progress =
        widget.controller.transferProgressFor(widget.peer.ip);

    if (progress == null) {
      return const SizedBox.shrink();
    }

    final String percent = '${(progress.progress * 100).toStringAsFixed(0)}%';
    final String label = progress.direction == 'sending'
        ? 'Sending ${progress.mediaType}'
        : 'Receiving ${progress.mediaType}';

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              progress.fileName.isEmpty ? label : '$label • ${progress.fileName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress.completed ? 1 : progress.progress.clamp(0, 1),
            ),
            const SizedBox(height: 6),
            Text(
              progress.completed ? 'Completed' : percent,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (BuildContext context, Widget? child) {
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(widget.peer.name),
                Text(
                  widget.peer.ip,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            actions: <Widget>[
              IconButton(
                onPressed: () => widget.controller.ensureConnected(widget.peer),
                icon: const Icon(Icons.wifi_tethering_rounded),
              ),
            ],
          ),
          body: Column(
            children: <Widget>[
              SessionStatusBar(
                connected: _connectedToThisPeer,
                peerName: widget.peer.name,
              ),
              _buildProgressBar(),
              Expanded(
                child: ValueListenableBuilder<List<ChatMessage>>(
                  valueListenable: _messagesListenable,
                  builder: (
                    BuildContext context,
                    List<ChatMessage> messages,
                    Widget? child,
                  ) {
                    if (messages.isEmpty) {
                      return const Center(
                        child: Text('No messages yet'),
                      );
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: messages.length,
                      itemBuilder: (BuildContext context, int index) {
                        final ChatMessage message = messages[index];
                        return MessageBubble(
                          message: message,
                          onTap: message.isMedia
                              ? () => _openMedia(message)
                              : null,
                        );
                      },
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                  child: Row(
                    children: <Widget>[
                      IconButton(
                        onPressed: _busy ? null : _showAttachmentSheet,
                        icon: const Icon(Icons.attach_file_rounded),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          decoration: const InputDecoration(
                            hintText: 'Type a message or caption...',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _sendText(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: _busy ? null : _sendText,
                        child: Text(_busy ? '...' : 'Send'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}