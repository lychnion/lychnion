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
