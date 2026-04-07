import 'dart:convert';

import 'package:cryptography/cryptography.dart';

class EncryptedPayload {
  final String cipherTextBase64;
  final String nonceBase64;
  final String macBase64;
  final int timestamp;

  const EncryptedPayload({
    required this.cipherTextBase64,
    required this.nonceBase64,
    required this.macBase64,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'ciphertext': cipherTextBase64,
      'nonce': nonceBase64,
      'mac': macBase64,
      'timestamp': timestamp,
    };
  }

  factory EncryptedPayload.fromJson(Map<String, dynamic> json) {
    return EncryptedPayload(
      cipherTextBase64: json['ciphertext'] as String,
      nonceBase64: json['nonce'] as String,
      macBase64: json['mac'] as String,
      timestamp: json['timestamp'] as int,
    );
  }
}

class CryptoService {
  final X25519 _x25519 = X25519();
  final Hkdf _hkdf = Hkdf(
    hmac: Hmac.sha256(),
    outputLength: 32,
  );
  final AesGcm _aesGcm = AesGcm.with256bits();

  Future<KeyPair> generateSessionKeyPair() async {
    return _x25519.newKeyPair();
  }

  Future<String> exportPublicKeyBase64(KeyPair keyPair) async {
    final PublicKey publicKey = await keyPair.extractPublicKey();
    final SimplePublicKey simplePublicKey = publicKey as SimplePublicKey;
    return base64Encode(simplePublicKey.bytes);
  }

  Future<SecretKey> deriveSharedKey({
    required KeyPair myKeyPair,
    required String peerPublicKeyBase64,
  }) async {
    final SimplePublicKey peerPublicKey = SimplePublicKey(
      base64Decode(peerPublicKeyBase64),
      type: KeyPairType.x25519,
    );

    final SecretKey sharedSecret = await _x25519.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: peerPublicKey,
    );

    final PublicKey myPublicKeyRaw = await myKeyPair.extractPublicKey();
    final SimplePublicKey myPublicKey = myPublicKeyRaw as SimplePublicKey;

    final List<int> info = _buildSessionInfo(
      myPublicKey.bytes,
      peerPublicKey.bytes,
    );

    return _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: utf8.encode('lanx-secure-chat-v1'),
      info: info,
    );
  }

  Future<EncryptedPayload> encryptMessage({
    required SecretKey sessionKey,
    required String plainText,
    required int timestamp,
    List<int>? aad,
  }) async {
    return encryptBytes(
      sessionKey: sessionKey,
      plainBytes: utf8.encode(plainText),
      timestamp: timestamp,
      aad: aad,
    );
  }

  Future<String> decryptMessage({
    required SecretKey sessionKey,
    required EncryptedPayload payload,
    List<int>? aad,
  }) async {
    final List<int> clearBytes = await decryptBytes(
      sessionKey: sessionKey,
      payload: payload,
      aad: aad,
    );

    return utf8.decode(clearBytes);
  }

  Future<EncryptedPayload> encryptBytes({
    required SecretKey sessionKey,
    required List<int> plainBytes,
    required int timestamp,
    List<int>? aad,
  }) async {
    final List<int> resolvedAad = aad ?? utf8.encode(timestamp.toString());

    final SecretBox secretBox = await _aesGcm.encrypt(
      plainBytes,
      secretKey: sessionKey,
      aad: resolvedAad,
    );

    return EncryptedPayload(
      cipherTextBase64: base64Encode(secretBox.cipherText),
      nonceBase64: base64Encode(secretBox.nonce),
      macBase64: base64Encode(secretBox.mac.bytes),
      timestamp: timestamp,
    );
  }

  Future<List<int>> decryptBytes({
    required SecretKey sessionKey,
    required EncryptedPayload payload,
    List<int>? aad,
  }) async {
    final List<int> resolvedAad = aad ?? utf8.encode(payload.timestamp.toString());

    final SecretBox secretBox = SecretBox(
      base64Decode(payload.cipherTextBase64),
      nonce: base64Decode(payload.nonceBase64),
      mac: Mac(base64Decode(payload.macBase64)),
    );

    return _aesGcm.decrypt(
      secretBox,
      secretKey: sessionKey,
      aad: resolvedAad,
    );
  }

  List<int> _buildSessionInfo(List<int> a, List<int> b) {
    final bool firstComesFirst = _compareBytes(a, b) <= 0;
    final List<int> first = firstComesFirst ? a : b;
    final List<int> second = firstComesFirst ? b : a;

    return <int>[
      ...utf8.encode('x25519-hkdf-aesgcm'),
      ...first,
      ...second,
    ];
  }

  int _compareBytes(List<int> a, List<int> b) {
    final int minLen = a.length < b.length ? a.length : b.length;
    for (int i = 0; i < minLen; i++) {
      if (a[i] != b[i]) {
        return a[i] - b[i];
      }
    }
    return a.length - b.length;
  }
}