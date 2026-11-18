part of 'ask_page.dart';

/// The first steps card and the guided tour on the home screen.
mixin _FirstStepsHookup on _AskPageBase {
  /// The guided tour starts by itself once, after the first steps.
  bool _tourStarted = false;

  void _startTour() {
    final keys = widget.tourKeys;
    final settings = widget.settings;
    if (keys == null || !mounted) return;
    _tourStarted = true;
    showGuidedTour(
      context,
      tourStops(context, keys),
      onEnd: () => unawaited(settings?.markFirstStep('tour')),
    );
  }

  /// Where the user stands on the first steps (lychnion#7).
  FirstSteps _firstSteps(AppSettings? settings) => FirstSteps(
    aiReady: const {
      AskPhase.loading,
      AskPhase.ready,
      AskPhase.shelter,
      AskPhase.serving,
    }.contains(_phase),
    mapReady: widget.map != null,
    siteSeen: settings?.firstSteps.contains('site') ?? false,
    asked: _threads.recent.isNotEmpty,
  );

  /// Once the first steps are done, the tour shows the screen once.
  void _maybeStartTour(FirstSteps steps, AppSettings? settings) {
    if (widget.onScreen &&
        widget.view == AskPageView.home &&
        steps.allDone &&
        settings != null &&
        !settings.firstSteps.contains('tour') &&
        !_tourStarted) {
      _tourStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _startTour());
    }
  }
}
