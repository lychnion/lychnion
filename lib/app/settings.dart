import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// User settings kept on the device (settings.json in app support).
class AppSettings extends ChangeNotifier {
  /// App language as a code ('ja', 'en', …); null: follow the device.
  String? language;

  Locale? get locale => language == null ? null : Locale(language!);

  /// Developer aid: speed and memory under each answer.
  bool showStats = false;

  /// The shelter computer this phone asks first (from a QR code or typed).
  String? shelterUrl;
  String? shelterName;

  /// The shelter's public key from its QR code; null when typed by hand
  /// (then the key is taken on first connect).
  String? shelterKey;

  /// Shelter computer: answer phones on the local network (desktop), and
  /// the name phones see. Off until the user turns it on.
  bool sharing = false;
  String? sharingName;

  /// Region chosen by hand ('JP-30', 'JP'), or null: from the position.
  String? region;

  /// Notices the user has acknowledged (`app:1`, `pkg:<id>:<hash>`).
  Set<String> acknowledged = {};

  bool hasAcknowledged(String key) => acknowledged.contains(key);

  Future<void> acknowledge(Iterable<String> keys) async {
    acknowledged.addAll(keys);
    notifyListeners();
    await _save();
  }

  File? _file;

  Future<void> load() async {
    final dir = await getApplicationSupportDirectory();
    _file = File('${dir.path}/settings.json');
    try {
      final j = jsonDecode(await _file!.readAsString()) as Map;
      // Older files wrote 'system' for "follow the device".
      final lang = j['language'];
      language = lang is String && lang.isNotEmpty && lang != 'system'
          ? lang
          : null;
      showStats = j['show_stats'] == true;
      shelterUrl = j['shelter_url'] as String?;
      shelterName = j['shelter_name'] as String?;
      shelterKey = j['shelter_key'] as String?;
      sharing = j['sharing'] == true;
      region = j['region'] as String?;
      sharingName = j['sharing_name'] as String?;
      acknowledged = {...?(j['acknowledged'] as List?)?.cast<String>()};
    } on Object {
      // No file yet, or unreadable: keep defaults.
    }
    notifyListeners();
  }

  /// [lang] null: follow the device.
  Future<void> setLanguage(String? lang) async {
    language = lang;
    notifyListeners();
    await _save();
  }

  Future<void> setShowStats(bool v) async {
    showStats = v;
    notifyListeners();
    await _save();
  }

  /// Connects to a shelter computer, or disconnects with null.
  Future<void> setShelter(String? url, {String? name, String? key}) async {
    shelterUrl = url;
    shelterName = url == null ? null : name;
    shelterKey = url == null ? null : key;
    notifyListeners();
    await _save();
  }

  /// Turns sharing on the local network on or off; [name] replaces the
  /// shelter's name when given.
  Future<void> setSharing(bool on, {String? name}) async {
    sharing = on;
    if (name != null) sharingName = name.trim().isEmpty ? null : name.trim();
    notifyListeners();
    await _save();
  }

  /// [code] null: from the position again.
  Future<void> setRegion(String? code) async {
    region = code;
    notifyListeners();
    await _save();
  }

  Future<void> _save() async => _file?.writeAsString(
    jsonEncode({
      'language': ?language,
      'show_stats': showStats,
      'shelter_url': ?shelterUrl,
      'shelter_name': ?shelterName,
      'shelter_key': ?shelterKey,
      'sharing': sharing,
      'sharing_name': ?sharingName,
      'region': ?region,
      'acknowledged': acknowledged.toList()..sort(),
    }),
  );
}
