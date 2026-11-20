/// When this device answers a question by itself (lychnion/lychnion#65).
library;

import '../app/dev_flags.dart';
import '../ui/ask_view.dart' show AskPhase;

/// Whether this device answers by itself: the chat model is loaded and so
/// are the guides. The model alone never answers, whatever failed after
/// it loaded (the search model, indexing, a package): its text would have
/// no sources and no safety line. Only the `BARE` dev flag ([bare]) lets
/// it, for measuring the model without guides.
bool answersOnDevice({
  required bool modelLoaded,
  required bool guidesLoaded,
  bool bare = DevFlags.bare,
}) => modelLoaded && (guidesLoaded || bare);

/// The phase shown when no base answers: loading; ready only when the
/// device answers by itself ([answersOnDevice]); failed when the model
/// loaded without the guides; else no model.
AskPhase ownPhase({
  required bool loading,
  required bool modelLoaded,
  required bool guidesLoaded,
  bool bare = DevFlags.bare,
}) => loading
    ? AskPhase.loading
    : answersOnDevice(
        modelLoaded: modelLoaded,
        guidesLoaded: guidesLoaded,
        bare: bare,
      )
    ? AskPhase.ready
    : modelLoaded
    ? AskPhase.failed
    : AskPhase.noModel;
