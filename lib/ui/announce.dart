import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

/// Has TalkBack or VoiceOver say [message] now, for changes people can't
/// see (an answer arrived, a guided-tour step moved on).
void announce(BuildContext context, String message) {
  if (message.isEmpty) return;
  unawaited(
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.maybeOf(context) ?? TextDirection.ltr,
    ),
  );
}

/// Announces [message] once, when [when] turns from false to true (not
/// when the widget is first shown already true, e.g. an old answer).
class AnnounceWhen extends StatefulWidget {
  const AnnounceWhen({
    super.key,
    required this.when,
    required this.message,
    required this.child,
  });

  final bool when;
  final String Function(BuildContext) message;
  final Widget child;

  @override
  State<AnnounceWhen> createState() => _AnnounceWhenState();
}

class _AnnounceWhenState extends State<AnnounceWhen> {
  @override
  void didUpdateWidget(AnnounceWhen old) {
    super.didUpdateWidget(old);
    if (widget.when && !old.when) announce(context, widget.message(context));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
