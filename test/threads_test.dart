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
}
