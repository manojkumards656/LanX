import 'dart:io';

import 'package:flutter/material.dart';

import 'pages/home_page.dart';
import 'services/app_controller.dart';
import 'services/crypto_service.dart';
import 'services/network_service.dart';
import 'services/storage_service.dart';

class LanxApp extends StatefulWidget {
  const LanxApp({super.key});

  @override
  State<LanxApp> createState() => _LanxAppState();
}

class _LanxAppState extends State<LanxApp> {
  late final AppController _controller;
  late final Future<void> _initializeFuture;

  @override
  void initState() {
    super.initState();

    final String defaultName =
        Platform.localHostname.isNotEmpty ? Platform.localHostname : 'Device';

    _controller = AppController(
      storageService: StorageService(),
      networkService: NetworkService(
        localName: defaultName,
        cryptoService: CryptoService(),
      ),
      defaultName: defaultName,
    );

    _initializeFuture = _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LanX Radar',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF081018),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00D1FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        cardTheme: CardThemeData(
          color: const Color(0xFF132235),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(
              color: Color(0x3323D7FF),
            ),
          ),
        ),
      ),
      home: FutureBuilder<void>(
        future: _initializeFuture,
        builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          return HomePage(controller: _controller);
        },
      ),
    );
  }
}