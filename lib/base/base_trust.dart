/// Trusting a base's notices in person (lychnion/lychnion#63).
///
/// A `lychnion://base` link from the base's QR code and one from a web page
/// or a message look the same to the app. So a link only connects; the
/// base's notices count as official once the user compared the key's code
/// (base_key_code.dart) with the one on the base's screen. Trusted bases
/// are listed in Settings, where the user can remove them.
library;

import 'package:material_ui/material_ui.dart';

import '../app/lang.dart';
import '../facts/fact_store.dart';
import '../facts/signing.dart';
import 'base_checks.dart';
import 'base_key_code.dart';
import 'base_link.dart';

/// The user's answer to [confirmBase]: connect, and whether they compared
/// the code and trust the base's notices.
typedef BaseConsent = ({bool trust});

/// The comparison code, large and easy to read aloud.
class BaseKeyCodeText extends StatelessWidget {
  const BaseKeyCodeText(this.code, {super.key, this.large = false});

  final String code;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SelectableText(
      code,
      // Read out group by group, not as one word.
      semanticsLabel: code.split('').join(' '),
      style:
          (large ? theme.textTheme.displaySmall : theme.textTheme.headlineSmall)
              ?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
    );
  }
}

/// Asks before connecting to a base from a link or found on the Wi-Fi;
/// null when the user cancels. A link with a key also shows the key's
/// code: only when the user ticks that it matches the base's screen are
/// its notices trusted ([trustBaseKey]).
Future<BaseConsent?> confirmBase(BuildContext context, BaseLink link) =>
    showDialog<BaseConsent>(
      context: context,
      builder: (_) => _ConfirmBaseDialog(link),
    );

class _ConfirmBaseDialog extends StatefulWidget {
  const _ConfirmBaseDialog(this.link);

  final BaseLink link;

  @override
  State<_ConfirmBaseDialog> createState() => _ConfirmBaseDialogState();
}

class _ConfirmBaseDialogState extends State<_ConfirmBaseDialog> {
  var _trust = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final link = widget.link;
    final code = baseKeyCode(link.key);
    return AlertDialog(
      icon: const Icon(Icons.cell_tower_rounded),
      title: Text(l.baseConnectTo(link.name ?? l.baseThisBase)),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.baseConnectBody(link.url.replaceFirst('http://', ''))),
            if (code != null) ...[
              const SizedBox(height: 16),
              Text(l.baseKeyCodeLabel),
              const SizedBox(height: 4),
              BaseKeyCodeText(code),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _trust,
                onChanged: (v) => setState(() => _trust = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(l.baseTrustCodeMatches),
                subtitle: Text(l.baseTrustCodeHint),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop<BaseConsent>(context, (
            trust: code != null && _trust,
          )),
          child: Text(l.baseConnect),
        ),
      ],
    );
  }
}

/// Asks the user to compare the code of the connected base's [keyText]
/// with its screen; true when they say it matches.
Future<bool> compareBaseCode(
  BuildContext context, {
  required String keyText,
  required String name,
}) async {
  final code = baseKeyCode(keyText);
  if (code == null) return false;
  return await showDialog<bool>(
        context: context,
        builder: (c) {
          final l = c.l10n;
          return AlertDialog(
            icon: const Icon(Icons.verified_user_outlined),
            title: Text(l.baseTrustTitle(name)),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l.baseKeyCodeLabel),
                  const SizedBox(height: 4),
                  BaseKeyCodeText(code),
                  const SizedBox(height: 12),
                  Text(l.baseTrustCodeHint),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text(l.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(l.baseTrustSame),
              ),
            ],
          );
        },
      ) ??
      false;
}

/// Settings: the bases whose notices this device trusts, each with its
/// code and a button to stop trusting it. Nothing when there are none.
class TrustedBasesList extends StatelessWidget {
  const TrustedBasesList({super.key, required this.facts});

  final FactStore facts;

  Future<void> _remove(BuildContext context, TrustedKey key) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) {
        final l = c.l10n;
        return AlertDialog(
          title: Text(l.baseTrustedRemoveTitle(key.name)),
          content: Text(l.baseTrustedRemoveBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(l.baseTrustedRemove),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    await forgetBaseKey(key.id, name: key.name, facts: facts);
  }

  @override
  Widget build(BuildContext context) {
    final trust = facts.trust;
    if (trust == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: trust,
      builder: (context, _) {
        final keys = trust.keysOf(TrustedKeyKind.base);
        if (keys.isEmpty) return const SizedBox.shrink();
        final l = context.l10n;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                l.baseTrustedTitle,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            for (final k in keys)
              ListTile(
                leading: const Icon(Icons.verified_user_outlined),
                title: Text(k.name),
                subtitle: Text(baseKeyCode(k.keyText) ?? k.id),
                trailing: IconButton(
                  tooltip: l.baseTrustedRemove,
                  icon: const Icon(Icons.remove_moderator_outlined),
                  onPressed: () => _remove(context, k),
                ),
              ),
          ],
        );
      },
    );
  }
}
