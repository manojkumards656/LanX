# LanX

LanX is a Flutter-based LAN secure messaging application that allows two devices on the same local network or mobile hotspot to discover each other and communicate directly using encrypted peer-to-peer messaging.

The project focuses on:
- secure key exchange
- authenticated encryption
- real-time messaging over TCP sockets
- local profile and chat persistence
- LAN radar-style discovery UI

## Features

- Peer-to-peer messaging over LAN using TCP sockets
- Device discovery on the same subnet / hotspot
- Real-time text chat
- Local profile with saved name and short note
- Recent chats and local chat history
- Dedicated full-screen chat page
- Radar-style home screen UI
- Encrypted communication using modern cryptography
- Local persistence of chats and profile data

## Security Design

LanX uses a custom secure messaging flow built from standard cryptographic primitives.

### Cryptographic components used

- **X25519** for elliptic-curve Diffie-Hellman key exchange
- **HKDF-SHA256** for session key derivation
- **AES-GCM-256** for authenticated encryption
- **Random nonce per message**
- **Timestamp validation** for basic replay protection

### Protocol flow

1. Two devices discover each other on the local network.
2. One device connects to the other using TCP sockets.
3. Both devices generate fresh ephemeral X25519 key pairs.
4. Public keys are exchanged.
5. Both sides compute the same shared secret using ECDH.
6. HKDF-SHA256 derives a 256-bit AES session key.
7. Messages are encrypted using AES-GCM before being sent.
8. The receiver verifies and decrypts the message.

### Security properties

- **Confidentiality**: message content is encrypted
- **Integrity**: tampering is detected by AES-GCM
- **Session-based keys**: a new session derives a fresh key
- **Replay mitigation**: timestamps are checked before accepting data

## Important Limitation

This project encrypts communication but does **not yet implement strong peer identity authentication** such as certificates, signed public keys, or fingerprint verification.

That means:
- it protects well against passive eavesdropping on the LAN
- but it is **not fully resistant to man-in-the-middle attacks**

## Tech Stack

- **Flutter**
- **Dart**
- **dart:io** for TCP sockets
- **cryptography**
- **cryptography_flutter**
- **shared_preferences**
- **path_provider**
- **image_picker** (media support / in progress)
- **video_player** (media preview / in progress)

## Project Structure

```text
lib/
  main.dart
  app.dart

  models/
    user_profile.dart
    chat_message.dart
    chat_session.dart
    peer_device.dart
    transfer_progress.dart

  services/
    crypto_service.dart
    network_service.dart
    storage_service.dart
    app_controller.dart

  pages/
    home_page.dart
    chat_page.dart
    profile_page.dart
    crypto_page.dart
    media_viewer_page.dart

  widgets/
    radar_header.dart
    peer_card.dart
    message_bubble.dart
    session_status_bar.dart
