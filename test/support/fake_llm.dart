import 'package:lychnion/llm/local_llm.dart';

/// Answers without a model. Each [ask] gives the next of [replies] (the last
/// one again when they run out) and records what it was asked.
class FakeLlm extends LocalLlm {
  FakeLlm([this.replies = const ['OK']]);

  final List<String> replies;
  final instructions = <String>[];
  final prompts = <String>[];

  String? get prompt => prompts.isEmpty ? null : prompts.last;

  @override
  Future<void> newChat({
    required String systemInstruction,
    int maxOutputTokens = 512,
  }) async => instructions.add(systemInstruction);

  @override
  Stream<String> ask(String prompt, {void Function(AnswerStats)? onDone}) {
    final reply = replies[prompts.length.clamp(0, replies.length - 1)];
    prompts.add(prompt);
    return Stream.value(reply);
  }
}
