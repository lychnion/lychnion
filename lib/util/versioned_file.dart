import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Files the app saves carry a format number, `"format": n`. A file
/// without one is format 0 (written before format numbers existed).
///
/// Reading never crashes the app and never loses data without a copy:
///
/// - missing file: nothing (the caller uses its defaults);
/// - unreadable file: copied to `<name>.broken`, then nothing;
/// - format newer than this build knows (a newer build wrote it): copied
///   to `<name>.newer`, then nothing. The caller's next save replaces the
///   file, the copy stays. If the copy fails, saves must not replace the
///   file in this run: writers check [mayReplace].
///
/// Older formats are given to the caller to read; its next save writes
/// the current format.
int formatOf(Object? json) => switch (json) {
  {'format': final int f} => f,
  _ => 0,
};

/// Files kept aside in this run (`<name>.broken`, `<name>.newer`), for a
/// line in Settings.
final keptAside = ValueNotifier<List<String>>(const []);

/// Copies made in this run (only finished ones), and copies under way.
final _asideDone = <String>{};
final _asidePending = <String, Future<File?>>{};

/// Files whose copy failed: the app must not write over them in this
/// run, or the only copy of their data would be lost (see [mayReplace]).
final _mustKeep = <String>{};

/// Copies [file] to `<name>.[why]` once per run and notes it in
/// [keptAside]. Returns the copy, or null when nothing could be copied:
/// then [mayReplace] is false for [file] for the rest of the run.
Future<File?> keepAside(File file, String why) {
  final to = '${file.path}.$why';
  if (_asideDone.contains(to)) return Future.value(File(to));
  return _asidePending[to] ??= () async {
    try {
      final copy = await file.copy(to);
      _done(file, why);
      return copy;
    } on Object catch (e) {
      _failed(file, e);
      return null;
    } finally {
      // A failed copy is tried again next time. (This runs after the
      // first await, so after the entry was stored.)
      _asidePending.removeWhere((k, _) => k == to);
    }
  }();
}

/// [keepAside] for code that cannot wait. A copy under way elsewhere
/// counts as not made yet.
File? keepAsideSync(File file, String why) {
  final to = '${file.path}.$why';
  if (_asideDone.contains(to)) return File(to);
  try {
    final copy = file.copySync(to);
    _done(file, why);
    return copy;
  } on Object catch (e) {
    _failed(file, e);
    return null;
  }
}

/// False while [file] holds data that could not be copied aside: a save
/// must then leave it as it is.
bool mayReplace(File file) => !_mustKeep.contains(file.path);

void _done(File file, String why) {
  _asideDone.add('${file.path}.$why');
  _mustKeep.remove(file.path);
  _note(file, why);
}

void _failed(File file, Object e) {
  _mustKeep.add(file.path);
  debugPrint('could not keep ${file.path} aside, not writing over it: $e');
}

void _note(File file, String why) {
  debugPrint('kept ${file.path} aside as .$why');
  final name = '${file.uri.pathSegments.last}.$why';
  if (!keptAside.value.contains(name)) {
    keptAside.value = [...keptAside.value, name];
  }
}

/// Forgets what was kept aside (tests).
@visibleForTesting
void resetKeptAside() {
  _asideDone.clear();
  _asidePending.clear();
  _mustKeep.clear();
  keptAside.value = const [];
}

/// Reads [file] as JSON and gives it with its format to [parse], see the
/// top of this file. [parse] may throw for a file it cannot read: the
/// file then counts as unreadable.
Future<T?> readVersioned<T>(
  File file,
  int current,
  T Function(Object? json, int format) parse,
) async {
  if (!await file.exists()) return null;
  String? text;
  try {
    text = await file.readAsString();
  } on Object {
    text = null;
  }
  final r = _read(file.path, text, current, parse);
  if (r.aside != null) await keepAside(file, r.aside!);
  return r.value;
}

/// [readVersioned] for code that cannot wait.
T? readVersionedSync<T>(
  File file,
  int current,
  T Function(Object? json, int format) parse,
) {
  if (!file.existsSync()) return null;
  String? text;
  try {
    text = file.readAsStringSync();
  } on Object {
    text = null;
  }
  final r = _read(file.path, text, current, parse);
  if (r.aside != null) keepAsideSync(file, r.aside!);
  return r.value;
}

({T? value, String? aside}) _read<T>(
  String path,
  String? text,
  int current,
  T Function(Object? json, int format) parse,
) {
  final Object? json;
  try {
    json = jsonDecode(text!);
  } on Object {
    return (value: null, aside: 'broken');
  }
  // A format that is not a number is not a file this app wrote.
  if (json is Map && json.containsKey('format') && json['format'] is! int) {
    return (value: null, aside: 'broken');
  }
  final f = formatOf(json);
  if (f > current) return (value: null, aside: 'newer');
  try {
    return (value: parse(json, f), aside: null);
  } on Object catch (e) {
    debugPrint('$path not read: $e');
    return (value: null, aside: 'broken');
  }
}
