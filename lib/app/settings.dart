import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// App language: follow the device, or always Japanese / English.
enum AppLanguage {
  system,
  ja,
  en;

  Locale? get locale => switch (this) {
    system => null,
    ja => const Locale('ja'),
    en => const Locale('en'),
  };
}

/// User settings kept on the device (settings.json in app support).
class AppSettings extends ChangeNotifier {
  AppLanguage language = AppLanguage.system;

  /// Developer aid: speed and memory under each answer.
  bool showStats = false;

  File? _file;

  Future<void> load() async {
    final dir = await getApplicationSupportDirectory();
    _file = File('${dir.path}/settings.json');
    try {
      final j = jsonDecode(await _file!.readAsString()) as Map;
      language = AppLanguage.values.firstWhere(
        (l) => l.name == j['language'],
        orElse: () => AppLanguage.system,
      );
      showStats = j['show_stats'] == true;
    } on Object {
      // No file yet, or unreadable: keep defaults.
    }
    notifyListeners();
  }

  Future<void> setLanguage(AppLanguage l) async {
    language = l;
    notifyListeners();
    await _save();
  }

  Future<void> setShowStats(bool v) async {
    showStats = v;
    notifyListeners();
    await _save();
  }

  Future<void> _save() async => _file?.writeAsString(
    jsonEncode({'language': language.name, 'show_stats': showStats}),
  );
}
