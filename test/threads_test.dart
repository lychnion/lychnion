import 'dart:io';

import 'package:lychnion/knowledge/grounded_answer.dart';
import 'package:lychnion/ui/threads.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Thread withQuestion(ThreadStore s, String q) =>
      s.create()..entries.add(GroundedAnswer(q)..text = 'answer');

  test('archived threads leave the recent list, and come back', () {
    final s = ThreadStore();
    final a = withQuestion(s, 'a');
    final b = withQuestion(s, 'b');
    s.create(); // empty threads are never listed
    expect(s.recent, [b, a]);
    s.setArchived(a, true);
    expect(s.recent, [b]);
    expect(s.archived, [a]);
    s.setArchived(a, false);
    expect(s.recent, [b, a]);
  });

  test('a deleted thread can be restored in its place', () {
    final s = ThreadStore();
    final a = withQuestion(s, 'a');
    final b = withQuestion(s, 'b');
    s.delete(a);
    expect(s.recent, [b]);
    s.restore(a);
    expect(s.recent, [b, a]);
  });

  // lychnion/lychnion#65: whether an answer came from the guides is kept
  // per answer, so old answers keep their sources and warnings while the
  // guides reload; a "guides could not be loaded" note is not one.
  test('an answer keeps whether it came from the guides', () async {
    final dir = Directory.systemTemp.createTempSync('threads_guides_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final s = ThreadStore();
    await s.load(dir: dir);
    s.create().entries.addAll([
      GroundedAnswer('a')..text = 'from the guides',
      GroundedAnswer('b')
        ..text = 'the guides could not be loaded'
        ..fromGuides = false,
    ]);
    await s.save();
    final again = ThreadStore();
    await again.load(dir: dir);
    expect(
      [for (final a in again.recent.single.entries) a.fromGuides],
      [true, false],
    );
  });

  test(
    'a base answer keeps its name and whether the base was checked',
    () async {
      final dir = Directory.systemTemp.createTempSync('threads_base_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final s = ThreadStore();
      await s.load(dir: dir);
      s.create().entries.addAll([
        GroundedAnswer('a')
          ..text = 'x'
          ..answeredBy = 'Hall'
          ..baseUnchecked = true,
        GroundedAnswer('b')
          ..text = 'y'
          ..answeredBy = 'Hall',
        GroundedAnswer('c')
          ..text = 'z'
          ..answeredBy = 'Hall'
          ..baseUnsigned = true,
        GroundedAnswer('d')
          ..text = 'w'
          ..baseRefused = true,
      ]);
      await s.save();
      final again = ThreadStore();
      await again.load(dir: dir);
      final e = again.recent.single.entries;
      expect(
        [for (final a in e) (a.answeredBy, a.baseUnchecked, a.baseUnsigned)],
        [
          ('Hall', true, false),
          ('Hall', false, false),
          ('Hall', false, true),
          (null, false, false),
        ],
      );
      expect([for (final a in e) a.baseRefused], [false, false, false, true]);
      // A base answer saved before the check was kept counts as unchecked.
      final file = File('${dir.path}/threads.json');
      file.writeAsStringSync(
        file.readAsStringSync().replaceAll(',"base_unchecked":false', ''),
      );
      final old = ThreadStore();
      await old.load(dir: dir);
      expect(old.recent.single.entries[1].baseUnchecked, isTrue);
    },
  );
}
