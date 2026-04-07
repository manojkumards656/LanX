import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/chat_message.dart';

class MediaViewerPage extends StatefulWidget {
  const MediaViewerPage({
    super.key,
    required this.message,
  });

  final ChatMessage message;

  @override
  State<MediaViewerPage> createState() => _MediaViewerPageState();
}

class _MediaViewerPageState extends State<MediaViewerPage> {
  VideoPlayerController? _videoController;
  Future<void>? _initializeVideoFuture;

  @override
  void initState() {
    super.initState();

    if (widget.message.messageType == 'video' &&
        widget.message.localMediaPath != null) {
      _videoController = VideoPlayerController.file(
        File(widget.message.localMediaPath!),
      );
      _initializeVideoFuture = _videoController!.initialize().then((_) {
        _videoController!.setLooping(false);
      });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String title = widget.message.fileName ??
        (widget.message.messageType == 'image' ? 'Image' : 'Video');

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      backgroundColor: Colors.black,
      body: widget.message.messageType == 'image'
          ? _buildImageView()
          : _buildVideoView(),
    );
  }

  Widget _buildImageView() {
    final String? path = widget.message.localMediaPath;
    if (path == null || !File(path).existsSync()) {
      return const Center(
        child: Text('Image not found'),
      );
    }

    return Center(
      child: InteractiveViewer(
        child: Image.file(File(path)),
      ),
    );
  }

  Widget _buildVideoView() {
    if (_videoController == null || _initializeVideoFuture == null) {
      return const Center(
        child: Text('Video not found'),
      );
    }

    return FutureBuilder<void>(
      future: _initializeVideoFuture,
      builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              AspectRatio(
                aspectRatio: _videoController!.value.aspectRatio == 0
                    ? 16 / 9
                    : _videoController!.value.aspectRatio,
                child: VideoPlayer(_videoController!),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  setState(() {
                    if (_videoController!.value.isPlaying) {
                      _videoController!.pause();
                    } else {
                      _videoController!.play();
                    }
                  });
                },
                icon: Icon(
                  _videoController!.value.isPlaying
                      ? Icons.pause
                      : Icons.play_arrow,
                ),
                label: Text(
                  _videoController!.value.isPlaying ? 'Pause' : 'Play',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}