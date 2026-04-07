import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../models/user_profile.dart';

class StorageService {
  static const String _profileNameKey = 'profile_name';
  static const String _profileNoteKey = 'profile_note';

  Future<UserProfile> loadProfile(String defaultName) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? name = prefs.getString(_profileNameKey);
    final String? note = prefs.getString(_profileNoteKey);

    return UserProfile(
      name: (name?.trim().isNotEmpty == true) ? name! : defaultName,
      note: note ?? 'Secure local node',
    );
  }

  Future<void> saveProfile(UserProfile profile) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileNameKey, profile.name);
    await prefs.setString(_profileNoteKey, profile.note);
  }

  Future<List<ChatSession>> loadSessions() async {
    final File file = await _sessionsFile();
    if (!await file.exists()) return <ChatSession>[];

    final String content = await file.readAsString();
    if (content.trim().isEmpty) return <ChatSession>[];

    final List<dynamic> jsonList = jsonDecode(content) as List<dynamic>;

    return jsonList
        .map((dynamic item) =>
            ChatSession.fromJson(item as Map<String, dynamic>))
        .toList()
      ..sort((ChatSession a, ChatSession b) =>
          b.lastTimestampMs.compareTo(a.lastTimestampMs));
  }

  Future<void> saveSessions(List<ChatSession> sessions) async {
    final File file = await _sessionsFile();
    final String content = jsonEncode(
      sessions.map((ChatSession session) => session.toJson()).toList(),
    );
    await file.writeAsString(content, flush: true);
  }

  Future<List<ChatMessage>> loadMessages(String chatId) async {
    final File file = await _messagesFile(chatId);
    if (!await file.exists()) return <ChatMessage>[];

    final String content = await file.readAsString();
    if (content.trim().isEmpty) return <ChatMessage>[];

    final List<dynamic> jsonList = jsonDecode(content) as List<dynamic>;
    return jsonList
        .map((dynamic item) =>
            ChatMessage.fromJson(item as Map<String, dynamic>))
        .toList()
      ..sort((ChatMessage a, ChatMessage b) =>
          a.timestampMs.compareTo(b.timestampMs));
  }

  Future<void> saveMessages(String chatId, List<ChatMessage> messages) async {
    final File file = await _messagesFile(chatId);
    final String content = jsonEncode(
      messages.map((ChatMessage message) => message.toJson()).toList(),
    );
    await file.writeAsString(content, flush: true);
  }

  Future<String> importOutgoingMedia({
    required String chatId,
    required String sourcePath,
  }) async {
    final Directory dir = await _chatMediaDir(chatId);
    final String extension = _extensionFromPath(sourcePath);
    final String targetPath =
        '${dir.path}${Platform.pathSeparator}${DateTime.now().millisecondsSinceEpoch}_out$extension';

    if (sourcePath == targetPath) {
      return sourcePath;
    }

    final File source = File(sourcePath);
    await source.copy(targetPath);
    return targetPath;
  }

  Future<String> prepareIncomingMediaPath(
    String chatId,
    String originalFileName,
  ) async {
    final Directory dir = await _chatMediaDir(chatId);
    final String extension = _extensionFromPath(originalFileName);
    final String base = _basenameWithoutExtension(originalFileName);
    final String safeBase = _safeFileName(base);

    return '${dir.path}${Platform.pathSeparator}${DateTime.now().millisecondsSinceEpoch}_in_$safeBase$extension';
  }

  Future<Directory> _appDir() async {
    final Directory directory = await getApplicationDocumentsDirectory();
    final Directory lanxDir =
        Directory('${directory.path}${Platform.pathSeparator}lanx_data');

    if (!await lanxDir.exists()) {
      await lanxDir.create(recursive: true);
    }

    return lanxDir;
  }

  Future<File> _sessionsFile() async {
    final Directory dir = await _appDir();
    return File('${dir.path}${Platform.pathSeparator}sessions.json');
  }

  Future<File> _messagesFile(String chatId) async {
    final Directory dir = await _appDir();
    final Directory chatsDir =
        Directory('${dir.path}${Platform.pathSeparator}chats');

    if (!await chatsDir.exists()) {
      await chatsDir.create(recursive: true);
    }

    final String safeName = _safeFileName(chatId);
    return File('${chatsDir.path}${Platform.pathSeparator}$safeName.json');
  }

  Future<Directory> _chatMediaDir(String chatId) async {
    final Directory dir = await _appDir();
    final Directory mediaDir = Directory(
      '${dir.path}${Platform.pathSeparator}media${Platform.pathSeparator}${_safeFileName(chatId)}',
    );

    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }

    return mediaDir;
  }

  String _safeFileName(String value) {
    return value.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }

  String _extensionFromPath(String path) {
    final int index = path.lastIndexOf('.');
    if (index == -1) return '';
    return path.substring(index);
  }

  String _basenameWithoutExtension(String path) {
    final String normalized = path.replaceAll('\\', '/');
    final String name =
        normalized.substring(normalized.lastIndexOf('/') + 1);
    final int dotIndex = name.lastIndexOf('.');
    if (dotIndex == -1) return name;
    return name.substring(0, dotIndex);
  }
}