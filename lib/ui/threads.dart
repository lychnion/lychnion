import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../knowledge/grounded_answer.dart';
import '../shelter/shelter_protocol.dart';

/// One conversation: questions and answers in the order asked.
///
/// Each question is still answered on its own from the guides; the model
/// does not see the earlier questions of the thread.
class Thread {
  Thread(this.id, this.created, [List<GroundedAnswer>? entries])
    : entries = entries ?? [];

  final String id;
  final DateTime created;
  final List<GroundedAnswer> entries;

  /// Archived threads leave the home list but stay on the device.
  bool archived = false;

  String get title => entries.isEmpty ? '' : entries.first.question;
  DateTime get updated => created; // good enough for ordering
}

/// Threads kept on the device (threads.json in app support).
class ThreadStore extends ChangeNotifier {
  final List<Thread> threads = [];
  File? _file;

  /// Newest first, without empty or archived threads.
  List<Thread> get recent => [
    for (final t in threads.reversed)
      if (t.entries.isNotEmpty && !t.archived) t,
  ];

  /// Archived threads, newest first.
  List<Thread> get archived => [
    for (final t in threads.reversed)
      if (t.entries.isNotEmpty && t.archived) t,
  ];

  void setArchived(Thread t, bool archived) {
    t.archived = archived;
    notifyListeners();
    save();
  }

  /// Puts a deleted thread back (undo).
  void restore(Thread t) {
    if (threads.contains(t)) return;
    threads
      ..add(t)
      ..sort((a, b) => a.created.compareTo(b.created));
    notifyListeners();
    save();
  }

  Future<void> load() async {
    final dir = await getApplicationSupportDirectory();
    _file = File('${dir.path}/threads.json');
    try {
      final j = jsonDecode(await _file!.readAsString()) as List;
      for (final t in j.cast<Map<String, dynamic>>()) {
        threads.add(
          Thread(t['id'] as String, DateTime.parse(t['created'] as String), [
            for (final e in (t['entries'] as List).cast<Map<String, dynamic>>())
              answerFromWire(e['answer'] as Map<String, dynamic>)
                ..answeredBy = e['answered_by'] as String?,
          ])..archived = t['archived'] == true,
        );
      }
    } on Object catch (e) {
      // No file yet, or an older format: start empty.
      if (await _file!.exists()) debugPrint('threads not loaded: $e');
    }
    notifyListeners();
  }

  Thread create() {
    final now = DateTime.now();
    final t = Thread('${now.microsecondsSinceEpoch}', now);
    threads.add(t);
    notifyListeners();
    return t;
  }

  void delete(Thread t) {
    threads.remove(t);
    notifyListeners();
    save();
  }

  /// Saves finished answers (call after an answer is complete).
  Future<void> save() async {
    final file = _file;
    if (file == null) return;
    await file.writeAsString(
      jsonEncode([
        for (final t in threads)
          if (t.entries.isNotEmpty)
            {
              'id': t.id,
              'created': t.created.toUtc().toIso8601String(),
              if (t.archived) 'archived': true,
              'entries': [
                for (final e in t.entries)
                  {'answer': answerToWire(e), 'answered_by': e.answeredBy},
              ],
            },
      ]),
    );
  }
}
