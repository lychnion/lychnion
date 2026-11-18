import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:lychnion_format/lychnion_format.dart';
import 'package:material_ui/material_ui.dart';

import '../app/lang.dart';
import '../download/download_manager.dart';
import '../download/publisher_list.dart';
import '../l10n/app_localizations.dart';
import 'local_publisher.dart';
import 'publish.dart';

// Backing up, restoring, replacing and revoking this computer's publisher
// key (docs/distribution.md, "Backing up and replacing the key").

const _keyFiles = XTypeGroup(
  label: 'Lychnion key',
  extensions: ['lychnion-key'],
);

/// A backup is a few hundred bytes; anything much larger is not one.
const _maxBackupBytes = 64 * 1024;

String backupProblemText(AppLocalizations l, KeyBackupProblem p) => switch (p) {
  KeyBackupProblem.notABackup => l.publishBackupNotBackup,
  KeyBackupProblem.newer => l.publishBackupNewer,
  KeyBackupProblem.damaged => l.publishBackupDamaged,
  KeyBackupProblem.wrongPassphrase => l.publishBackupWrongPassphrase,
};

/// Asks for a passphrase (twice when [confirm]); null when cancelled.
Future<String?> askPassphrase(
  BuildContext context, {
  required String title,
  String? text,
  bool confirm = false,
}) => showDialog<String>(
  context: context,
  builder: (_) => _PassphraseDialog(title: title, text: text, confirm: confirm),
);

class _PassphraseDialog extends StatefulWidget {
  const _PassphraseDialog({
    required this.title,
    required this.text,
    required this.confirm,
  });
  final String title;
  final String? text;
  final bool confirm;

  @override
  State<_PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<_PassphraseDialog> {
  final _a = TextEditingController(), _b = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  void _ok() {
    final l = context.l10n;
    if (widget.confirm &&
        _a.text.runes.length < KeyBackup.minPassphraseLength) {
      setState(() => _error = l.publishPassphraseShort);
    } else if (widget.confirm && _a.text != _b.text) {
      setState(() => _error = l.publishPassphraseMismatch);
    } else if (_a.text.isNotEmpty) {
      Navigator.pop(context, _a.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.text case final t?) ...[
              Text(t),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _a,
              obscureText: true,
              autofocus: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: l.publishPassphrase,
                errorText: widget.confirm ? null : _error,
              ),
              onSubmitted: (_) => widget.confirm ? null : _ok(),
            ),
            if (widget.confirm)
              TextField(
                controller: _b,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: l.publishPassphraseAgain,
                  errorText: _error,
                ),
                onSubmitted: (_) => _ok(),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(onPressed: _ok, child: Text(widget.title)),
      ],
    );
  }
}

Future<bool> _confirm(
  BuildContext context,
  String title,
  String text, {
  bool danger = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(c.l10n.cancel),
          ),
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(c).colorScheme.error,
                    foregroundColor: Theme.of(c).colorScheme.onError,
                  )
                : null,
            onPressed: () => Navigator.pop(c, true),
            child: Text(title),
          ),
        ],
      ),
    ) ??
    false;

void _tell(BuildContext context, String text) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), duration: const Duration(seconds: 10)),
  );
}

Future<String?> _pickBackup() async {
  final f = await openFile(acceptedTypeGroups: const [_keyFiles]);
  if (f == null) return null;
  if (await f.length() > _maxBackupBytes) return '';
  return f.readAsString();
}

/// Saves a backup of [me] where the user picks.
Future<void> backupKey(BuildContext context, LocalPublisher me) async {
  final l = context.l10n;
  final pass = await askPassphrase(
    context,
    title: l.publishBackup,
    text: l.publishBackupWarning,
    confirm: true,
  );
  if (pass == null) return;
  final to = await getSaveLocation(
    suggestedName: '${me.name}${KeyBackup.extension}',
    acceptedTypeGroups: const [_keyFiles],
  );
  if (to == null) return;
  try {
    final text = await me.backup(pass);
    await File(to.path).writeAsString(text, flush: true);
    if (context.mounted) _tell(context, l.publishBackupSaved(to.path));
  } on Object catch (e) {
    if (context.mounted) _tell(context, l.publishFailed('$e'));
  }
}

/// Restores a key from a backup into [dir]; the restored publisher, or
/// null.
Future<LocalPublisher?> restoreKey(
  BuildContext context,
  Directory dir,
  DownloadManager manager,
) async {
  final l = context.l10n;
  final text = await _pickBackup();
  if (text == null || !context.mounted) return null;
  final pass = await askPassphrase(context, title: l.publishRestore);
  if (pass == null || !context.mounted) return null;
  try {
    final k = await KeyBackup.open(text, pass);
    // A key revoked or replaced here must not become this computer's key
    // again: what it signs is not trusted, or a second replacement would
    // revoke it.
    final link = PublisherLink(name: k.name, key: k.publicKey);
    final list = manager.store.publishers;
    if (list.problemWith(link) == PublisherProblem.revoked) {
      if (context.mounted) _tell(context, l.publishRestoreRevoked);
      return null;
    }
    if (list.statements.any(
      (s) =>
          s.publisher == k.name &&
          s.type == KeyStatementType.replace &&
          s.oldKeyId == link.keyId,
    )) {
      if (context.mounted) _tell(context, l.publishRestoreReplaced);
      return null;
    }
    final me = await LocalPublisher.restore(dir, k);
    // Trusts its own publisher, and gets back what it signed.
    await adoptNewKey(manager.store, dir, me);
    await manager.publishersChanged();
    if (context.mounted) _tell(context, l.publishRestored(me.name));
    return me;
  } on KeyBackupException catch (e) {
    if (context.mounted) _tell(context, backupProblemText(l, e.problem));
  } on ArgumentError catch (e) {
    if (context.mounted) {
      _tell(
        context,
        e.message == 'exists' ? l.publishKeyExists : l.publishBadName,
      );
    }
  } on PublishError catch (e) {
    if (context.mounted) _tell(context, l.publishFailed('$e'));
  } on Object catch (e) {
    if (context.mounted) _tell(context, l.publishFailed('$e'));
  }
  return null;
}

/// Revokes the key in a backup, without its passphrase (a lost key).
Future<void> revokeFromBackup(
  BuildContext context,
  Directory dir,
  DownloadManager manager,
) async {
  final l = context.l10n;
  final text = await _pickBackup();
  if (text == null || !context.mounted) return;
  final KeyStatement s;
  try {
    s = await KeyBackup.revocationIn(text);
  } on KeyBackupException catch (e) {
    if (context.mounted) _tell(context, backupProblemText(l, e.problem));
    return;
  }
  if (!context.mounted) return;
  final ok = await _confirm(
    context,
    l.publishRevokeKey,
    l.publishRevokeConfirm(s.oldKeyId, s.publisher),
    danger: true,
  );
  if (!ok) return;
  try {
    await LocalPublisher.writeKeysFile(dir, [s]);
    await manager.store.publishers.learn([s], any: true);
    await manager.publishersChanged();
    if (context.mounted) {
      _tell(
        context,
        l.publishRevocationSaved(LocalPublisher.keysFileIn(dir).path),
      );
    }
  } on Object catch (e) {
    if (context.mounted) _tell(context, l.publishFailed('$e'));
  }
}

/// Replaces ([revoke] false) or revokes and renews [me]'s key; the new
/// publisher, or null.
Future<LocalPublisher?> changeKey(
  BuildContext context,
  Directory dir,
  DownloadManager manager,
  LocalPublisher me, {
  required bool revoke,
}) async {
  final l = context.l10n;
  final ok = await _confirm(
    context,
    revoke ? l.publishRevokeKey : l.publishReplaceKey,
    revoke ? l.publishRevokeKeyText : l.publishReplaceKeyText,
    danger: revoke,
  );
  if (!ok || !context.mounted) return null;
  final LocalPublisher next;
  try {
    next = revoke ? await me.revokeAndRenew(dir) : await me.replaceKey(dir);
  } on Object catch (e) {
    // Nothing changed: the old key is still the key.
    if (context.mounted) _tell(context, l.publishFailed('$e'));
    return null;
  }
  // The new key is saved: from here on it is the key, also if a step
  // below fails (adoptNewKey runs again when the screen opens).
  try {
    final ids = await adoptNewKey(manager.store, dir, next);
    await manager.publishersChanged();
    if (context.mounted) {
      _tell(
        context,
        l.publishKeyChanged(
          '${ids.length}',
          LocalPublisher.keysFileIn(dir).path,
        ),
      );
    }
  } on Object catch (e) {
    if (context.mounted) _tell(context, l.publishFailed('$e'));
  }
  return next;
}

/// The "Your key" section under the publisher's code.
class PublisherKeyActions extends StatelessWidget {
  const PublisherKeyActions({
    super.key,
    required this.dir,
    required this.manager,
    required this.me,
    required this.onChanged,
    required this.busy,
  });

  final Directory dir;
  final DownloadManager manager;
  final LocalPublisher me;
  final bool busy;

  /// A new key was made (replace, revoke).
  final void Function(LocalPublisher) onChanged;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.publishKeySection,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: busy ? null : () => backupKey(context, me),
              icon: const Icon(Icons.save_alt_rounded),
              label: Text(l.publishBackup),
            ),
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      final n = await changeKey(
                        context,
                        dir,
                        manager,
                        me,
                        revoke: false,
                      );
                      if (n != null) onChanged(n);
                    },
              icon: const Icon(Icons.autorenew_rounded),
              label: Text(l.publishReplaceKey),
            ),
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      final n = await changeKey(
                        context,
                        dir,
                        manager,
                        me,
                        revoke: true,
                      );
                      if (n != null) onChanged(n);
                    },
              icon: const Icon(Icons.gpp_bad_outlined),
              label: Text(l.publishRevokeKey),
            ),
          ],
        ),
      ],
    );
  }
}
