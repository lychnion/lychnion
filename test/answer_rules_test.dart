// The model alone never answers (lychnion/lychnion#65): when the guides
// or the search model fail after the chat model loaded, the phone does
// not answer by itself, so no answer without sources or safety line.
import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/ask/answer_rules.dart';
import 'package:lychnion/ui/ask_view.dart' show AskPhase;

void main() {
  test('the model and the guides loaded: the device answers', () {
    expect(answersOnDevice(modelLoaded: true, guidesLoaded: true), isTrue);
  });

  test('the model loaded but not the guides: it does not', () {
    expect(
      answersOnDevice(modelLoaded: true, guidesLoaded: false, bare: false),
      isFalse,
    );
  });

  test('no model: never', () {
    expect(
      answersOnDevice(modelLoaded: false, guidesLoaded: true, bare: true),
      isFalse,
    );
  });

  test('only the BARE dev flag lets the model answer alone', () {
    expect(
      answersOnDevice(modelLoaded: true, guidesLoaded: false, bare: true),
      isTrue,
    );
  });

  group('the phase without a base', () {
    AskPhase phase({
      bool loading = false,
      bool model = false,
      bool guides = false,
      bool bare = false,
    }) => ownPhase(
      loading: loading,
      modelLoaded: model,
      guidesLoaded: guides,
      bare: bare,
    );

    test('loading, ready, failed and no model', () {
      expect(phase(loading: true, model: true), AskPhase.loading);
      expect(phase(model: true, guides: true), AskPhase.ready);
      // The model loaded but not the guides: not "ready" (#65).
      expect(phase(model: true), AskPhase.failed);
      expect(phase(), AskPhase.noModel);
      expect(phase(guides: true), AskPhase.noModel);
    });

    test('with BARE the model alone is ready', () {
      expect(phase(model: true, bare: true), AskPhase.ready);
    });
  });
}
