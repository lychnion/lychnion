import 'dart:io';

/// Whether Google's LiteRT-LM engine can run on this device.
///
/// It needs Android 11 (API 30) or newer; the app itself runs from
/// Android 9, where answer models stay on llama.cpp. Other platforms are
/// not gated here (their catalog records say which platforms a model is
/// for). An Android version that cannot be read counts as too old.
final bool liteRtRunsHere = !Platform.isAndroid || (androidSdk() ?? 0) >= 30;

/// The Android API level (30 = Android 11), or null if not Android or
/// unreadable. Read once from the system property.
int? androidSdk() => _sdk ??= _readSdk();
int? _sdk;

int? _readSdk() {
  if (!Platform.isAndroid) return null;
  try {
    final r = Process.runSync('getprop', ['ro.build.version.sdk']);
    return int.tryParse('${r.stdout}'.trim());
  } on Object {
    return null;
  }
}

/// Whether [fileName] is a LiteRT-LM model.
bool isLiteRtFile(String fileName) =>
    fileName.toLowerCase().endsWith('.litertlm');
