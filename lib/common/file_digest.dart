import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

/// Keep hashing Core and Helper binaries off the Flutter UI isolate.
Future<String> fileSha256(String path) => Isolate.run(() async {
      final digest = await sha256.bind(File(path).openRead()).first;
      return digest.toString();
    });
