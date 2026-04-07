import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';

import '../models/chat_message.dart';
import '../models/peer_device.dart';
import '../models/transfer_progress.dart';
import 'crypto_service.dart';

class NetworkService {
  NetworkService({
    required this.localName,
    CryptoService? cryptoService,
  }) : _cryptoService = cryptoService ?? CryptoService();

  final CryptoService _cryptoService;
  final int port = 4040;
  static const int _mediaChunkSize = 12 * 1024;

  String localName;

  ServerSocket? _server;
  Socket? _activeSocket;
  StreamSubscription<String>? _activeSubscription;

  KeyPair? _localEphemeralKeyPair;
  SecretKey? _sessionKey;

  String? connectedPeerName;
  String? connectedPeerIp;

  final Set<int> _seenTimestamps = <int>{};
  final Map<String, _IncomingMediaTransfer> _incomingTransfers =
      <String, _IncomingMediaTransfer>{};

  Future<void> _incomingQueue = Future<void>.value();

  final StreamController<ChatMessage> _messagesController =
      StreamController<ChatMessage>.broadcast();
  final StreamController<List<PeerDevice>> _peersController =
      StreamController<List<PeerDevice>>.broadcast();
  final StreamController<String> _statusController =
      StreamController<String>.broadcast();
  final StreamController<TransferProgress> _progressController =
      StreamController<TransferProgress>.broadcast();

  Stream<ChatMessage> get messagesStream => _messagesController.stream;
  Stream<List<PeerDevice>> get peersStream => _peersController.stream;
  Stream<String> get statusStream => _statusController.stream;
  Stream<TransferProgress> get progressStream => _progressController.stream;

  bool get isSecureConnected =>
      _activeSocket != null && _sessionKey != null && connectedPeerIp != null;

  Future<void> startListening() async {
    if (_server != null) return;

    _server = await ServerSocket.bind(
      InternetAddress.anyIPv4,
      port,
      shared: true,
    );

    final String? ip = await getLocalPrivateIp();
    _statusController.add('LISTENING • ${ip ?? "unknown-ip"}:$port');

    _server!.listen(_handleIncomingSocket);
  }

  Future<void> dispose() async {
    await disconnect(silent: true);
    await _server?.close();
    await _messagesController.close();
    await _peersController.close();
    await _statusController.close();
    await _progressController.close();
  }

  Future<void> disconnect({bool silent = false}) async {
    final Socket? oldSocket = _activeSocket;
    final String? oldPeerIp = connectedPeerIp;
    final String oldPeerName = connectedPeerName ?? 'Peer';

    _activeSocket = null;
    connectedPeerName = null;
    connectedPeerIp = null;
    _sessionKey = null;
    _localEphemeralKeyPair = null;
    _seenTimestamps.clear();
    _incomingQueue = Future<void>.value();

    await _activeSubscription?.cancel();
    _activeSubscription = null;

    await _clearIncomingTransfers(deleteFiles: true);

    try {
      await oldSocket?.flush();
    } catch (_) {}

    try {
      await oldSocket?.close();
    } catch (_) {}

    if (oldPeerIp != null) {
      _emitProgress(
        TransferProgress(
          chatId: oldPeerIp,
          direction: 'receiving',
          mediaType: 'media',
          fileName: '',
          progress: 0,
          active: false,
        ),
      );
      _emitProgress(
        TransferProgress(
          chatId: oldPeerIp,
          direction: 'sending',
          mediaType: 'media',
          fileName: '',
          progress: 0,
          active: false,
        ),
      );
    }

    if (!silent) {
      if (oldPeerIp != null) {
        _messagesController.add(
          ChatMessage.system(
            chatId: oldPeerIp,
            peerName: oldPeerName,
            peerIp: oldPeerIp,
            text: 'Disconnected',
          ),
        );
      }

      final String? ip = await getLocalPrivateIp();
      _statusController.add('LISTENING • ${ip ?? "unknown-ip"}:$port');
    }
  }

  Future<String?> getLocalPrivateIp() async {
    final List<NetworkInterface> interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );

    for (final NetworkInterface interface in interfaces) {
      for (final InternetAddress address in interface.addresses) {
        if (_isPrivateIpv4(address.address)) {
          return address.address;
        }
      }
    }
    return null;
  }

  Future<void> discoverPeers() async {
    final String? localIp = await getLocalPrivateIp();
    if (localIp == null) {
      _peersController.add(const <PeerDevice>[]);
      _statusController.add('NO LOCAL LAN IP');
      return;
    }

    final List<String> parts = localIp.split('.');
    if (parts.length != 4) {
      _peersController.add(const <PeerDevice>[]);
      _statusController.add('BAD LAN ADDRESS FORMAT');
      return;
    }

    final String subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
    final List<String> candidates = <String>[
      for (int i = 1; i <= 254; i++) '$subnet.$i',
    ]..remove(localIp);

    final List<PeerDevice> found = <PeerDevice>[];
    const int batchSize = 24;

    _statusController.add('SCANNING • $localIp');

    for (int i = 0; i < candidates.length; i += batchSize) {
      final Iterable<String> batch = candidates.skip(i).take(batchSize);
      final List<PeerDevice?> results =
          await Future.wait(batch.map(_probePeer).toList());

      for (final PeerDevice? result in results) {
        if (result != null) {
          found.add(result);
        }
      }
    }

    found.sort((PeerDevice a, PeerDevice b) => a.name.compareTo(b.name));
    _peersController.add(found);

    if (isSecureConnected) {
      _statusController.add('CONNECTED • $connectedPeerName');
    } else {
      _statusController.add('SCAN COMPLETE • ${found.length} NODE(S)');
    }
  }

  Future<void> connectToPeer(PeerDevice peer) async {
    if (connectedPeerIp == peer.ip && isSecureConnected) {
      return;
    }

    await disconnect(silent: true);

    try {
      final Socket socket = await Socket.connect(
        peer.ip,
        port,
        timeout: const Duration(seconds: 2),
      );

      _activeSocket = socket;
      connectedPeerName = peer.name;
      connectedPeerIp = peer.ip;
      _incomingQueue = Future<void>.value();

      _activeSubscription = socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (String line) {
          _enqueueIncomingLine(socket, line);
        },
        onDone: () async {
          if (socket == _activeSocket) {
            await disconnect();
          }
        },
        onError: (_) async {
          if (socket == _activeSocket) {
            await disconnect();
          }
        },
      );

      _localEphemeralKeyPair = await _cryptoService.generateSessionKeyPair();
      final String myPublicKeyBase64 =
          await _cryptoService.exportPublicKeyBase64(
        _localEphemeralKeyPair!,
      );

      final Map<String, dynamic> handshake = <String, dynamic>{
        'type': 'handshake',
        'phase': 'init',
        'name': localName,
        'publicKey': myPublicKeyBase64,
      };

      socket.writeln(jsonEncode(handshake));
      await socket.flush();

      _statusController.add('HANDSHAKE • ${peer.name}');
    } catch (_) {
      _statusController.add('CONNECT FAILED • ${peer.ip}');
      rethrow;
    }
  }

  Future<void> sendTextMessage(String text) async {
    if (_activeSocket == null || _sessionKey == null || connectedPeerIp == null) {
      throw Exception('Not connected');
    }

    final Socket socket = _activeSocket!;
    final SecretKey sessionKey = _sessionKey!;
    final String peerIp = connectedPeerIp!;
    final String peerName = connectedPeerName ?? peerIp;

    final String trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final int timestamp = DateTime.now().millisecondsSinceEpoch;

    final EncryptedPayload payload = await _cryptoService.encryptMessage(
      sessionKey: sessionKey,
      plainText: trimmed,
      timestamp: timestamp,
    );

    final Map<String, dynamic> packet = <String, dynamic>{
      'type': 'message',
      ...payload.toJson(),
    };

    socket.writeln(jsonEncode(packet));
    await socket.flush();

    _messagesController.add(
      ChatMessage(
        chatId: peerIp,
        peerName: peerName,
        peerIp: peerIp,
        sender: localName,
        text: trimmed,
        timestampMs: timestamp,
        isMine: true,
      ),
    );
  }

  Future<void> sendMediaFile({
    required String filePath,
    required String mediaType,
    String caption = '',
  }) async {
    if (_activeSocket == null || _sessionKey == null || connectedPeerIp == null) {
      throw Exception('Not connected');
    }

    if (mediaType != 'image' && mediaType != 'video') {
      throw Exception('Unsupported media type');
    }

    final File sourceFile = File(filePath);
    if (!await sourceFile.exists()) {
      throw Exception('File not found');
    }

    final int totalBytes = await sourceFile.length();
    if (totalBytes <= 0) {
      throw Exception('Empty file');
    }

    final Socket socket = _activeSocket!;
    final SecretKey sessionKey = _sessionKey!;
    final String peerIp = connectedPeerIp!;
    final String peerName = connectedPeerName ?? peerIp;
    final String originalFileName = _fileNameFromPath(filePath);

    final int baseTimestamp = DateTime.now().millisecondsSinceEpoch;
    final String fileId =
        '${baseTimestamp}_${DateTime.now().microsecondsSinceEpoch}';
    final int totalChunks = (totalBytes / _mediaChunkSize).ceil();

    final File storedFile = await _copyOutgoingMediaToAppStorage(
      sourcePath: filePath,
      fileId: fileId,
      fileName: originalFileName,
    );

    _emitProgress(
      TransferProgress(
        chatId: peerIp,
        direction: 'sending',
        mediaType: mediaType,
        fileName: originalFileName,
        progress: 0,
        active: true,
      ),
    );

    final Map<String, dynamic> meta = <String, dynamic>{
      'fileId': fileId,
      'mediaType': mediaType,
      'fileName': originalFileName,
      'caption': caption,
      'timestamp': baseTimestamp,
      'totalBytes': totalBytes,
      'totalChunks': totalChunks,
    };

    final EncryptedPayload metaPayload = await _cryptoService.encryptMessage(
      sessionKey: sessionKey,
      plainText: jsonEncode(meta),
      timestamp: baseTimestamp,
    );

    socket.writeln(jsonEncode(<String, dynamic>{
      'type': 'media_meta',
      ...metaPayload.toJson(),
    }));
    await socket.flush();

    final RandomAccessFile raf = await storedFile.open(mode: FileMode.read);

    try {
      int chunkIndex = 0;
      while (true) {
        final List<int> chunk = await raf.read(_mediaChunkSize);
        if (chunk.isEmpty) break;

        final int packetTimestamp = baseTimestamp + chunkIndex + 1;

        final EncryptedPayload payload = await _cryptoService.encryptBytes(
          sessionKey: sessionKey,
          plainBytes: chunk,
          timestamp: packetTimestamp,
          aad: _mediaChunkAad(
            fileId: fileId,
            chunkIndex: chunkIndex,
            totalChunks: totalChunks,
            timestamp: packetTimestamp,
          ),
        );

        socket.writeln(jsonEncode(<String, dynamic>{
          'type': 'media_chunk',
          'fileId': fileId,
          'chunkIndex': chunkIndex,
          'totalChunks': totalChunks,
          ...payload.toJson(),
        }));
        await socket.flush();

        chunkIndex++;

        _emitProgress(
          TransferProgress(
            chatId: peerIp,
            direction: 'sending',
            mediaType: mediaType,
            fileName: originalFileName,
            progress: chunkIndex / totalChunks,
            active: true,
          ),
        );
      }
    } finally {
      await raf.close();
    }

    final int doneTimestamp = baseTimestamp + totalChunks + 2;

    final EncryptedPayload donePayload = await _cryptoService.encryptMessage(
      sessionKey: sessionKey,
      plainText: jsonEncode(<String, dynamic>{'fileId': fileId}),
      timestamp: doneTimestamp,
    );

    socket.writeln(jsonEncode(<String, dynamic>{
      'type': 'media_done',
      ...donePayload.toJson(),
    }));
    await socket.flush();

    _emitProgress(
      TransferProgress(
        chatId: peerIp,
        direction: 'sending',
        mediaType: mediaType,
        fileName: originalFileName,
        progress: 1,
        active: false,
        completed: true,
      ),
    );

    _messagesController.add(
      ChatMessage(
        chatId: peerIp,
        peerName: peerName,
        peerIp: peerIp,
        sender: localName,
        text: caption,
        timestampMs: baseTimestamp,
        isMine: true,
        messageType: mediaType,
        localMediaPath: storedFile.path,
        fileName: originalFileName,
        fileSizeBytes: totalBytes,
      ),
    );
  }

  void _handleIncomingSocket(Socket socket) {
    late StreamSubscription<String> sub;

    sub = socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (String line) {
        _enqueueIncomingLine(socket, line, sub: sub);
      },
      onDone: () async {
        if (socket == _activeSocket) {
          await disconnect();
        }
      },
      onError: (_) async {
        if (socket == _activeSocket) {
          await disconnect();
        }
      },
    );
  }

  void _enqueueIncomingLine(
    Socket socket,
    String line, {
    StreamSubscription<String>? sub,
  }) {
    _incomingQueue = _incomingQueue.then((_) async {
      try {
        await _processLine(socket, line, sub: sub);
      } catch (_) {}
    });
  }

  Future<void> _processLine(
    Socket socket,
    String line, {
    StreamSubscription<String>? sub,
  }) async {
    Map<String, dynamic> json;

    try {
      json = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final dynamic type = json['type'];

    if (type == 'discovery') {
      socket.writeln(jsonEncode(<String, dynamic>{
        'type': 'discoveryAck',
        'name': localName,
      }));
      await socket.flush();
      await socket.close();
      await sub?.cancel();
      return;
    }

    if (type == 'busy') {
      _statusController.add('PEER BUSY');
      await disconnect(silent: true);
      return;
    }

    if (type == 'handshake') {
      final String phase = (json['phase'] as String?) ?? '';
      final String remoteName = (json['name'] ?? 'Unknown').toString();
      final String remotePublicKey = (json['publicKey'] ?? '').toString();

      if (phase == 'init') {
        if (_activeSocket != null && _activeSocket != socket) {
          socket.writeln(jsonEncode(<String, dynamic>{'type': 'busy'}));
          await socket.flush();
          await socket.close();
          await sub?.cancel();
          return;
        }

        _activeSocket = socket;
        _activeSubscription = sub;
        connectedPeerName = remoteName;
        connectedPeerIp = socket.remoteAddress.address;
        _incomingQueue = Future<void>.value();

        _localEphemeralKeyPair =
            await _cryptoService.generateSessionKeyPair();

        _sessionKey = await _cryptoService.deriveSharedKey(
          myKeyPair: _localEphemeralKeyPair!,
          peerPublicKeyBase64: remotePublicKey,
        );

        final String myPublicKeyBase64 =
            await _cryptoService.exportPublicKeyBase64(
          _localEphemeralKeyPair!,
        );

        socket.writeln(jsonEncode(<String, dynamic>{
          'type': 'handshake',
          'phase': 'ack',
          'name': localName,
          'publicKey': myPublicKeyBase64,
        }));
        await socket.flush();

        _seenTimestamps.clear();

        _messagesController.add(
          ChatMessage.system(
            chatId: connectedPeerIp!,
            peerName: remoteName,
            peerIp: connectedPeerIp!,
            text: 'Secure session established',
          ),
        );

        _statusController.add('CONNECTED • $remoteName');
        return;
      }

      if (phase == 'ack' &&
          socket == _activeSocket &&
          _localEphemeralKeyPair != null) {
        _sessionKey = await _cryptoService.deriveSharedKey(
          myKeyPair: _localEphemeralKeyPair!,
          peerPublicKeyBase64: remotePublicKey,
        );

        connectedPeerName = remoteName;
        connectedPeerIp = socket.remoteAddress.address;
        _seenTimestamps.clear();

        _messagesController.add(
          ChatMessage.system(
            chatId: connectedPeerIp!,
            peerName: remoteName,
            peerIp: connectedPeerIp!,
            text: 'Secure session established',
          ),
        );

        _statusController.add('CONNECTED • $remoteName');
        return;
      }
    }

    if (type == 'message' && socket == _activeSocket && _sessionKey != null) {
      try {
        final EncryptedPayload payload = EncryptedPayload.fromJson(json);
        final int now = DateTime.now().millisecondsSinceEpoch;

        if ((now - payload.timestamp).abs() > 2 * 60 * 1000) {
          _statusController.add('DROPPED • INVALID TIMESTAMP');
          return;
        }

        if (_seenTimestamps.contains(payload.timestamp)) {
          _statusController.add('DROPPED • REPLAY DETECTED');
          return;
        }

        _seenTimestamps.add(payload.timestamp);

        final String text = await _cryptoService.decryptMessage(
          sessionKey: _sessionKey!,
          payload: payload,
        );

        final String peerIp = connectedPeerIp ?? socket.remoteAddress.address;
        final String peerName = connectedPeerName ?? socket.remoteAddress.address;

        _messagesController.add(
          ChatMessage(
            chatId: peerIp,
            peerName: peerName,
            peerIp: peerIp,
            sender: peerName,
            text: text,
            timestampMs: payload.timestamp,
            isMine: false,
          ),
        );
      } catch (_) {
        _statusController.add('DECRYPT FAILED');
      }
      return;
    }

    if (type == 'media_meta' && socket == _activeSocket && _sessionKey != null) {
      try {
        final EncryptedPayload payload = EncryptedPayload.fromJson(json);
        final String metaJson = await _cryptoService.decryptMessage(
          sessionKey: _sessionKey!,
          payload: payload,
        );

        final Map<String, dynamic> meta =
            jsonDecode(metaJson) as Map<String, dynamic>;

        final String fileId = meta['fileId'] as String;
        final String mediaType = meta['mediaType'] as String;
        final String fileName = meta['fileName'] as String;
        final String caption = (meta['caption'] as String?) ?? '';
        final int timestamp = meta['timestamp'] as int;
        final int totalBytes = meta['totalBytes'] as int;
        final int totalChunks = meta['totalChunks'] as int;

        if (_incomingTransfers.containsKey(fileId)) {
          await _incomingTransfers[fileId]!.dispose(deleteFile: true);
          _incomingTransfers.remove(fileId);
        }

        final File targetFile = await _createIncomingMediaFile(
          fileId: fileId,
          fileName: fileName,
        );

        final IOSink sink = targetFile.openWrite(mode: FileMode.writeOnly);

        final String peerIp = connectedPeerIp ?? socket.remoteAddress.address;
        final String peerName = connectedPeerName ?? socket.remoteAddress.address;

        _incomingTransfers[fileId] = _IncomingMediaTransfer(
          fileId: fileId,
          mediaType: mediaType,
          fileName: fileName,
          caption: caption,
          timestampMs: timestamp,
          totalBytes: totalBytes,
          totalChunks: totalChunks,
          peerIp: peerIp,
          peerName: peerName,
          file: targetFile,
          sink: sink,
        );

        _emitProgress(
          TransferProgress(
            chatId: peerIp,
            direction: 'receiving',
            mediaType: mediaType,
            fileName: fileName,
            progress: 0,
            active: true,
          ),
        );

        _statusController.add('RECEIVING ${mediaType.toUpperCase()} • $peerName');
      } catch (_) {
        _statusController.add('MEDIA META FAILED');
      }
      return;
    }

    if (type == 'media_chunk' && socket == _activeSocket && _sessionKey != null) {
      try {
        final String fileId = json['fileId'] as String;
        final int chunkIndex = json['chunkIndex'] as int;
        final int totalChunks = json['totalChunks'] as int;

        final _IncomingMediaTransfer? transfer = _incomingTransfers[fileId];
        if (transfer == null) return;

        if (transfer.receivedChunks != chunkIndex) {
          _statusController.add('MEDIA CHUNK ORDER ERROR');
          return;
        }

        final EncryptedPayload payload = EncryptedPayload.fromJson(json);

        final List<int> bytes = await _cryptoService.decryptBytes(
          sessionKey: _sessionKey!,
          payload: payload,
          aad: _mediaChunkAad(
            fileId: fileId,
            chunkIndex: chunkIndex,
            totalChunks: totalChunks,
            timestamp: payload.timestamp,
          ),
        );

        transfer.sink.add(bytes);
        transfer.receivedChunks += 1;

        _emitProgress(
          TransferProgress(
            chatId: transfer.peerIp,
            direction: 'receiving',
            mediaType: transfer.mediaType,
            fileName: transfer.fileName,
            progress: transfer.receivedChunks / transfer.totalChunks,
            active: true,
          ),
        );
      } catch (_) {
        _statusController.add('MEDIA CHUNK FAILED');
      }
      return;
    }

    if (type == 'media_done' && socket == _activeSocket && _sessionKey != null) {
      try {
        final EncryptedPayload payload = EncryptedPayload.fromJson(json);
        final String doneJson = await _cryptoService.decryptMessage(
          sessionKey: _sessionKey!,
          payload: payload,
        );

        final Map<String, dynamic> done =
            jsonDecode(doneJson) as Map<String, dynamic>;

        final String fileId = done['fileId'] as String;
        final _IncomingMediaTransfer? transfer = _incomingTransfers.remove(fileId);
        if (transfer == null) return;

        await transfer.sink.flush();
        await transfer.sink.close();

        if (transfer.receivedChunks != transfer.totalChunks) {
          try {
            await transfer.file.delete();
          } catch (_) {}

          _statusController.add('MEDIA INCOMPLETE');

          _emitProgress(
            TransferProgress(
              chatId: transfer.peerIp,
              direction: 'receiving',
              mediaType: transfer.mediaType,
              fileName: transfer.fileName,
              progress: 0,
              active: false,
              completed: false,
            ),
          );
          return;
        }

        _messagesController.add(
          ChatMessage(
            chatId: transfer.peerIp,
            peerName: transfer.peerName,
            peerIp: transfer.peerIp,
            sender: transfer.peerName,
            text: transfer.caption,
            timestampMs: transfer.timestampMs,
            isMine: false,
            messageType: transfer.mediaType,
            localMediaPath: transfer.file.path,
            fileName: transfer.fileName,
            fileSizeBytes: transfer.totalBytes,
          ),
        );

        _emitProgress(
          TransferProgress(
            chatId: transfer.peerIp,
            direction: 'receiving',
            mediaType: transfer.mediaType,
            fileName: transfer.fileName,
            progress: 1,
            active: false,
            completed: true,
          ),
        );

        _statusController.add('MEDIA RECEIVED • ${transfer.peerName}');
      } catch (_) {
        _statusController.add('MEDIA FINALIZE FAILED');
      }
    }
  }

  Future<PeerDevice?> _probePeer(String ip) async {
    try {
      final Socket socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(milliseconds: 180),
      );

      socket.writeln(jsonEncode(<String, dynamic>{
        'type': 'discovery',
        'name': localName,
      }));
      await socket.flush();

      final String line = await socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(milliseconds: 250));

      final Map<String, dynamic> json =
          jsonDecode(line) as Map<String, dynamic>;

      try {
        await socket.close();
      } catch (_) {}

      if (json['type'] == 'discoveryAck') {
        return PeerDevice(
          name: (json['name'] ?? ip).toString(),
          ip: ip,
        );
      }
    } catch (_) {}

    return null;
  }

  void _emitProgress(TransferProgress progress) {
    if (!_progressController.isClosed) {
      _progressController.add(progress);
    }
  }

  List<int> _mediaChunkAad({
    required String fileId,
    required int chunkIndex,
    required int totalChunks,
    required int timestamp,
  }) {
    return utf8.encode('$fileId:$chunkIndex:$totalChunks:$timestamp');
  }

  Future<File> _copyOutgoingMediaToAppStorage({
    required String sourcePath,
    required String fileId,
    required String fileName,
  }) async {
    final Directory root = await _mediaRootDir();
    final Directory outDir =
        Directory('${root.path}${Platform.pathSeparator}sent');

    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }

    final String safeName =
        '${fileId}_${_sanitizeFileName(fileName.isEmpty ? 'media.bin' : fileName)}';

    final String targetPath = '${outDir.path}${Platform.pathSeparator}$safeName';
    return File(sourcePath).copy(targetPath);
  }

  Future<File> _createIncomingMediaFile({
    required String fileId,
    required String fileName,
  }) async {
    final Directory root = await _mediaRootDir();
    final Directory inDir =
        Directory('${root.path}${Platform.pathSeparator}received');

    if (!await inDir.exists()) {
      await inDir.create(recursive: true);
    }

    final String safeName =
        '${fileId}_${_sanitizeFileName(fileName.isEmpty ? 'media.bin' : fileName)}';

    return File('${inDir.path}${Platform.pathSeparator}$safeName');
  }

  Future<Directory> _mediaRootDir() async {
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory root =
        Directory('${docs.path}${Platform.pathSeparator}lanx_media');

    if (!await root.exists()) {
      await root.create(recursive: true);
    }

    return root;
  }

  Future<void> _clearIncomingTransfers({required bool deleteFiles}) async {
    final List<_IncomingMediaTransfer> items =
        _incomingTransfers.values.toList(growable: false);

    _incomingTransfers.clear();

    for (final _IncomingMediaTransfer transfer in items) {
      await transfer.dispose(deleteFile: deleteFiles);
    }
  }

  String _fileNameFromPath(String path) {
    final String normalized = path.replaceAll('\\', '/');
    final List<String> parts = normalized.split('/');
    return parts.isEmpty ? 'media.bin' : parts.last;
  }

  String _sanitizeFileName(String value) {
    return value.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }

  bool _isPrivateIpv4(String ip) {
    final List<String> parts = ip.split('.');
    if (parts.length != 4) return false;

    final int a = int.tryParse(parts[0]) ?? -1;
    final int b = int.tryParse(parts[1]) ?? -1;

    if (a == 10) return true;
    if (a == 192 && b == 168) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    return false;
  }
}

class _IncomingMediaTransfer {
  _IncomingMediaTransfer({
    required this.fileId,
    required this.mediaType,
    required this.fileName,
    required this.caption,
    required this.timestampMs,
    required this.totalBytes,
    required this.totalChunks,
    required this.peerIp,
    required this.peerName,
    required this.file,
    required this.sink,
  });

  final String fileId;
  final String mediaType;
  final String fileName;
  final String caption;
  final int timestampMs;
  final int totalBytes;
  final int totalChunks;
  final String peerIp;
  final String peerName;
  final File file;
  final IOSink sink;

  int receivedChunks = 0;

  Future<void> dispose({required bool deleteFile}) async {
    try {
      await sink.flush();
    } catch (_) {}

    try {
      await sink.close();
    } catch (_) {}

    if (deleteFile) {
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
  }
}