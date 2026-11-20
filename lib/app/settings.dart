import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import '../util/versioned_file.dart';

/// User settings kept on the device (settings.json in app support).
class AppSettings extends ChangeNotifier {
  /// App language as a code ('ja', 'en', …); null: follow the device.
  String? language;

  Locale? get locale => language == null ? null : Locale(language!);

  /// Developer aid: speed and memory under each answer.
  bool showStats = false;

  /// Map: draw contour lines where the area has them. On until the user
  /// turns them off.
  bool showContours = true;

  /// The base computer this phone asks first (from a QR code or typed).
  String? baseUrl;
  String? baseName;

  /// The base's public key from its QR code; null when typed by hand
  /// (then the key is taken on first connect).
  String? baseKey;

  /// The QR key whose base has signed an answer, or whose QR code says
  /// it signs (`s=1` in the link): from then on the phone
  /// takes no unsigned answer from it (someone on the Wi-Fi could take
  /// the signature off). Forgotten when the base is disconnected or
  /// another key is pinned, not when the same key is pinned again.
  String? baseSignedKey;

  /// Base computer: answer phones on the local network (desktop), and
  /// the name phones see. Off until the user turns it on.
  bool sharing = false;
  String? sharingName;

  /// Region chosen by hand ('JP-30', 'JP'), or null: from the position.
  String? region;

  /// Notices the user has acknowledged (`app:1`, `pkg:<id>:<hash>`).
  Set<String> acknowledged = {};

  bool hasAcknowledged(String key) => acknowledged.contains(key);

  /// First steps on Home: `site` (the map was opened with an area),
  /// `hidden` (the user chose "Later").
  Set<String> firstSteps = {};

  Future<void> markFirstStep(String key, {bool on = true}) async {
    if (firstSteps.contains(key) == on) return;
    on ? firstSteps.add(key) : firstSteps.remove(key);
    notifyListeners();
    await _save();
  }

  Future<void> acknowledge(Iterable<String> keys) async {
    acknowledged.addAll(keys);
    notifyListeners();
    await _save();
  }

  File? _file;

  /// Format of settings.json (see versioned_file.dart). 0: before format
  /// numbers, same fields.
  static const format = 1;

  /// Reads settings.json from app support, or from [dir] (tests).
  Future<void> load({Directory? dir}) => _loading = _load(dir);

  /// The running or finished load: saves wait for it.
  Future<void>? _loading;

  Future<void> _load(Directory? dir) async {
    dir ??= await getApplicationSupportDirectory();
    // Saves start once the file was read (and kept as a copy if needed).
    final file = File('${dir.path}/settings.json');
    await readVersioned(file, format, (json, _) {
      final j = json! as Map;
      // Older files wrote 'system' for "follow the device".
      final lang = j['language'];
      language = lang is String && lang.isNotEmpty && lang != 'system'
          ? lang
          : null;
      showStats = j['show_stats'] == true;
      showContours = j['show_contours'] != false;
      // Older files wrote shelter_url, shelter_name and shelter_key.
      baseUrl = (j['base_url'] ?? j['shelter_url']) as String?;
      baseName = (j['base_name'] ?? j['shelter_name']) as String?;
      baseKey = (j['base_key'] ?? j['shelter_key']) as String?;
      baseSignedKey = j['base_signed_key'] as String?;
      sharing = j['sharing'] == true;
      region = j['region'] as String?;
      sharingName = j['sharing_name'] as String?;
      acknowledged = {...?(j['acknowledged'] as List?)?.cast<String>()};
      firstSteps = {...?(j['first_steps'] as List?)?.cast<String>()};
    });
    _file = file;
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

  Future<void> setShowContours(bool v) async {
    if (showContours == v) return;
    showContours = v;
    notifyListeners();
    await _save();
  }

  /// Connects to a base computer, or disconnects with null. [signs]: the
  /// QR code says the base signs its answers with [key].
  Future<void> setBase(
    String? url, {
    String? name,
    String? key,
    bool signs = false,
  }) async {
    baseUrl = url;
    baseName = url == null ? null : name;
    final newKey = url == null ? null : key;
    // Kept for the same key (the base got a new address): forgetting it
    // would let someone take the signature off again.
    if (newKey != baseKey) baseSignedKey = null;
    // The link says the base signs: no unsigned answer is taken, not even
    // the first. (A link from a web page can only make this stricter.)
    if (signs && newKey != null) baseSignedKey = newKey;
    baseKey = newKey;
    notifyListeners();
    await _save();
  }

  /// The base with QR key [key] signed an answer (see [baseSignedKey]).
  /// Ignored unless [key] is still the pinned one: a late answer from the
  /// base before must not stand for the one connected now.
  Future<void> setBaseSigned(String key) async {
    if (key != baseKey || baseSignedKey == key) return;
    baseSignedKey = key;
    notifyListeners();
    await _save();
  }

  /// Turns sharing on the local network on or off; [name] replaces the
  /// base's name when given.
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

  Future<void> _save() async {
    await _loading;
    final f = _file;
    if (f == null || !mayReplace(f)) return;
    await f.writeAsString(
      jsonEncode({
        'format': format,
        'language': ?language,
        'show_stats': showStats,
        'show_contours': showContours,
        'base_url': ?baseUrl,
        'base_name': ?baseName,
        'base_key': ?baseKey,
        'base_signed_key': ?baseSignedKey,
        'sharing': sharing,
        'sharing_name': ?sharingName,
        'region': ?region,
        'acknowledged': acknowledged.toList()..sort(),
        'first_steps': firstSteps.toList()..sort(),
      }),
    );
  }
}
