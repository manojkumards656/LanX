import 'package:flutter/material.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterCryptography.enable();
  runApp(const LanxApp());
}