import 'package:flutter/material.dart';

import 'ask_view.dart';

/// One thread: questions and answers, with the question bar at the bottom.
class ConversationPage extends StatefulWidget {
  const ConversationPage({
    super.key,
    required this.title,
    required this.en,
    required this.itemCount,
    required this.itemBuilder,
    required this.bar,
    this.actions = const [],
  });

  /// Menu in the app bar (archive, delete).
  final List<Widget> actions;

  final String title;
  final bool en;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final QuestionBar bar;

  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage> {
  final _scroll = ScrollController();
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    _lastCount = widget.itemCount;
    _toEnd();
  }

  @override
  void didUpdateWidget(ConversationPage old) {
    super.didUpdateWidget(old);
    if (widget.itemCount != _lastCount) {
      _lastCount = widget.itemCount;
      _toEnd(); // a new question: bring it into view
    }
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  });

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      // The question itself is the first bubble; no need to repeat it.
      title: Text(widget.en ? 'Conversation' : '会話'),
      actions: widget.actions,
    ),
    body: Column(
      children: [
        Expanded(
          child: ListView.separated(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            itemCount: widget.itemCount,
            separatorBuilder: (_, _) => const SizedBox(height: 24),
            itemBuilder: widget.itemBuilder,
          ),
        ),
        widget.bar,
      ],
    ),
  );
}
