import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Which answer engines this device can run. Read once at start ([init]).
abstract final class Engines {
  static const _channel = MethodChannel('lychnion/device');

  /// The Android API level (30 = Android 11); null elsewhere or if it
  /// could not be read.
  static int? androidSdk;

  /// Whether LiteRT-LM answer models run here: only on Android 11 (API 30)
  /// or newer. The app runs from Android 9; older phones, iPhones and
  /// computers answer with llama.cpp. An Android version that cannot be
  /// read counts as too old. Tests may set it.
  static bool liteRt = false;

  /// Reads the Android version from the platform.
  static Future<void> init() async {
    if (!Platform.isAndroid) return;
    try {
      androidSdk = await _channel.invokeMethod<int>('sdkInt');
    } on Object catch (e) {
      debugPrint(
        'LYCHNION ${jsonEncode({'event': 'android_sdk_unknown', 'error': '$e'})}',
      );
    }
    liteRt = (androidSdk ?? 0) >= 30;
  }
}

/// Whether [fileName] is a LiteRT-LM model.
bool isLiteRtFile(String fileName) =>
    fileName.toLowerCase().endsWith('.litertlm');
