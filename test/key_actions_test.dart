// The key dialogs in lib/publish/key_actions.dart, as a user goes through
// them: save a backup, restore one, replace the key (lychnion/lychnion#59).
// The file dialogs are replaced by a fake; everything else is the app's.
import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/app/text_delegates.dart';
import 'package:lychnion/download/download_manager.dart';
import 'package:lychnion/download/download_store.dart';
import 'package:lychnion/download/publisher_list.dart';
import 'package:lychnion/l10n/app_localizations.dart';
import 'package:lychnion/publish/key_actions.dart';
import 'package:lychnion/publish/local_publisher.dart';
import 'package:lychnion_format/lychnion_format.dart';
import 'package:material_ui/material_ui.dart';

const _pass = 'correct horse battery';
const _fast = KeyBackupKdf(memory: 64, iterations: 1);

/// The save and open dialogs: answers with the paths set here.
class _FakeFiles extends FileSelectorPlatform {
  String? savePath, openPath;

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async => savePath == null ? null : FileSaveLocation(savePath!);

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => openPath == null ? null : XFile(openPath!);
}

void main() {
  // Real time: the dialogs wait on real file and crypto work, which a
  // fake clock does not let finish reliably.
  LiveTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  final l = lookupAppLocalizations(const Locale('en'));
  late Directory tmp, pubDir, newDir;
  late DownloadManager manager;
  late _FakeFiles files;
  late ValueNotifier<LocalPublisher> me;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('lychnion-key-actions');
    pubDir = Directory('${tmp.path}/publisher');
    newDir = Directory('${tmp.path}/other-computer');
    final store = DownloadStore(
      Directory('${tmp.path}/desk'),
      publishers: PublisherList(File('${tmp.path}/desk/publishers.json')),
    );
    await store.publishers.load();
    manager = DownloadManager.forTest(store);
    me = ValueNotifier(
      await LocalPublisher.create(pubDir, name: 'jp.city.kobe', title: '神戸市'),
    );
    files = _FakeFiles();
    FileSelectorPlatform.instance = files;
  });
  tearDown(() async {
    manager.dispose();
    await tmp.delete(recursive: true);
  });

  /// The key section, and a button that restores into [newDir].
  Future<void> pumpKeys(WidgetTester t) async {
    t.view.physicalSize = const Size(1600, 2400);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: appTextDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: me,
            builder: (context, p, _) => Column(
              children: [
                PublisherKeyActions(
                  dir: pubDir,
                  manager: manager,
                  me: p,
                  busy: false,
                  onChanged: (n) => me.value = n,
                ),
                TextButton(
                  onPressed: () => restoreKey(context, newDir, manager),
                  child: const Text('restore here'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Waits until [f] shows (file and crypto work in real time), and the
  /// dialog before it has gone.
  Future<void> waitFor(WidgetTester t, Finder f) async {
    final end = DateTime.now().add(const Duration(seconds: 90));
    final seen = <String?>{};
    while (f.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) {
        fail('never shown: $f\nshown meanwhile: ${seen.join(' | ')}');
      }
      seen.addAll(
        find.byType(Text).evaluate().map((e) => (e.widget as Text).data),
      );
      await t.pump(const Duration(milliseconds: 50));
    }
    await t.pumpAndSettle();
  }

  /// Closes the snack bar, so the next message is the only one.
  Future<void> dismissSnack(WidgetTester t) async {
    ScaffoldMessenger.of(t.element(find.byType(Scaffold))).clearSnackBars();
    await t.pumpAndSettle();
  }

  Finder dialogButton(String label) => find.descendant(
    of: find.byType(AlertDialog),
    matching: find.widgetWithText(FilledButton, label),
  );

  Future<void> typePassphrase(WidgetTester t, String a, [String? b]) async {
    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await t.enterText(fields.at(0), a);
    if (b != null) await t.enterText(fields.at(1), b);
  }

  Future<String> writeBackup(LocalPublisher p, String name) async {
    final f = File('${tmp.path}/$name.lychnion-key');
    await f.writeAsString(await p.backup(_pass, kdf: _fast));
    return f.path;
  }

  testWidgets('save a backup: checks the passphrase, then saves a file '
      'that opens with the passphrase typed in half-width letters', (t) async {
    await pumpKeys(t);
    files.savePath = '${tmp.path}/kobe.lychnion-key';

    await t.tap(find.text(l.publishBackup));
    await t.pumpAndSettle();
    expect(find.text(l.publishBackupWarning), findsOneWidget);

    await typePassphrase(t, 'too short', 'too short');
    await t.tap(dialogButton(l.publishBackup));
    await t.pump();
    expect(find.text(l.publishPassphraseShort), findsOneWidget);

    await typePassphrase(t, _pass, 'correct horse batterx');
    await t.tap(dialogButton(l.publishBackup));
    await t.pump();
    expect(find.text(l.publishPassphraseMismatch), findsOneWidget);

    // Full-width letters, as a Japanese keyboard may type them (NFKC).
    const wide = 'ｃｏｒｒｅｃｔ ｈｏｒｓｅ ｂａｔｔｅｒｙ';
    await typePassphrase(t, wide, wide);
    await t.tap(dialogButton(l.publishBackup));
    await t.pump();
    await waitFor(t, find.text(l.publishBackupSaved(files.savePath!)));
    expect(find.byType(AlertDialog), findsNothing);

    final opened = (await t.runAsync(
      () async =>
          KeyBackup.open(await File(files.savePath!).readAsString(), _pass),
    ))!;
    expect(opened.name, 'jp.city.kobe');
    expect(
      PublisherLink(name: opened.name, key: opened.publicKey).keyId,
      me.value.link.keyId,
    );
  });

  testWidgets('cancelling a backup saves nothing', (t) async {
    await pumpKeys(t);
    files.savePath = null; // The user closes the save dialog.
    await t.tap(find.text(l.publishBackup));
    await t.pumpAndSettle();
    await typePassphrase(t, _pass, _pass);
    await t.tap(dialogButton(l.publishBackup));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(tmp.listSync().whereType<File>(), isEmpty);
  });

  testWidgets('restore: a wrong passphrase writes nothing; the key id and '
      'date are shown before anything is written', (t) async {
    final path = (await t.runAsync(() => writeBackup(me.value, 'kobe')))!;
    final opened = (await t.runAsync(
      () async => KeyBackup.open(await File(path).readAsString(), _pass),
    ))!;
    final keyId = me.value.link.keyId!;
    final made = opened.made!.split('T').first;
    await pumpKeys(t);
    files.openPath = path;

    // Wrong passphrase.
    await t.tap(find.text('restore here'));
    await waitFor(t, find.byType(TextField)); // After the file is read.
    await typePassphrase(t, 'wrong horse battery');
    await t.tap(dialogButton(l.publishRestore));
    await t.pump();
    await waitFor(t, find.text(l.publishBackupWrongPassphrase));
    expect(LocalPublisher.existsIn(newDir), isFalse);
    await dismissSnack(t);

    // Right passphrase, then Cancel at the check.
    await t.tap(find.text('restore here'));
    await waitFor(t, find.byType(TextField)); // After the file is read.
    await typePassphrase(t, _pass);
    await t.tap(dialogButton(l.publishRestore));
    await t.pump();
    await waitFor(t, find.text(l.publishRestoreCheck(keyId, made)));
    await t.tap(find.text(l.cancel));
    await t.pumpAndSettle();
    expect(LocalPublisher.existsIn(newDir), isFalse);

    // Right passphrase, confirmed.
    await t.tap(find.text('restore here'));
    await waitFor(t, find.byType(TextField)); // After the file is read.
    await typePassphrase(t, _pass);
    await t.tap(dialogButton(l.publishRestore));
    await t.pump();
    await waitFor(t, find.text(l.publishRestoreCheck(keyId, made)));
    await t.tap(dialogButton(l.publishRestore));
    await t.pump();
    await waitFor(t, find.text(l.publishRestored('jp.city.kobe')));
    expect(LocalPublisher.existsIn(newDir), isTrue);
    final restored = (await t.runAsync(() => LocalPublisher.load(newDir)))!;
    expect(restored.link.keyId, keyId);
  });

  testWidgets('replace: the dialog warns when 5 or fewer are left, and '
      'the 51st replacement is refused', (t) async {
    await t.runAsync(() async {
      for (var i = 0; i < 45; i++) {
        me.value = await me.value.replaceKey(pubDir);
      }
    });
    await pumpKeys(t);

    await t.tap(find.text(l.publishReplaceKey));
    await t.pumpAndSettle();
    expect(find.textContaining(l.publishReplaceFewLeft(5)), findsOneWidget);
    await t.tap(dialogButton(l.publishReplaceKey));
    await t.pump();
    await waitFor(
      t,
      find.text(
        l.publishKeyChanged('0', LocalPublisher.keysFileIn(pubDir).path),
      ),
    );
    expect(me.value.replacements, 46);
    await dismissSnack(t);

    await t.runAsync(() async {
      while (me.value.replacementsLeft > 0) {
        me.value = await me.value.replaceKey(pubDir);
      }
    });
    await t.pump();
    final keyBefore = me.value.link.keyId;
    await t.tap(find.text(l.publishReplaceKey));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text(l.publishReplaceNoneLeft), findsOneWidget);
    expect(me.value.link.keyId, keyBefore);
  });

  testWidgets('a key this computer knows was replaced is not replaced again, '
      'and its backup is not restored (before the first publish too)', (
    t,
  ) async {
    // Nothing published: this computer does not trust its own key yet.
    final old = me.value;
    final path = (await t.runAsync(() => writeBackup(old, 'old')))!;
    await pumpKeys(t);

    await t.tap(find.text(l.publishReplaceKey));
    await t.pumpAndSettle();
    expect(find.textContaining(l.publishReplaceKeyText), findsOneWidget);
    expect(find.textContaining('replacements are left'), findsNothing);
    await t.tap(dialogButton(l.publishReplaceKey));
    await t.pump();
    await waitFor(
      t,
      find.text(
        l.publishKeyChanged('0', LocalPublisher.keysFileIn(pubDir).path),
      ),
    );
    expect(me.value.link.keyId, isNot(old.link.keyId));
    await dismissSnack(t);

    // The old key again (an old backup restored, a stale screen).
    me.value = old;
    await t.pump();
    await t.tap(find.text(l.publishReplaceKey));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text(l.publishReplaceAlreadyReplaced), findsOneWidget);
    await dismissSnack(t);

    files.openPath = path;
    await t.tap(find.text('restore here'));
    await waitFor(t, find.byType(TextField)); // After the file is read.
    await typePassphrase(t, _pass);
    await t.tap(dialogButton(l.publishRestore));
    await t.pump();
    await waitFor(t, find.text(l.publishRestoreReplaced));
    expect(LocalPublisher.existsIn(newDir), isFalse);
  });

  testWidgets('revoke before the first publish: the old key counts as '
      'revoked here, and the new one is trusted', (t) async {
    final old = me.value;
    await pumpKeys(t);

    await t.tap(find.text(l.publishRevokeKey));
    await t.pumpAndSettle();
    expect(find.text(l.publishRevokeKeyText), findsOneWidget);
    await t.tap(dialogButton(l.publishRevokeKey));
    await t.pump();
    await waitFor(
      t,
      find.text(
        l.publishKeyChanged('0', LocalPublisher.keysFileIn(pubDir).path),
      ),
    );
    final list = manager.store.publishers;
    expect(me.value.link.keyId, isNot(old.link.keyId));
    expect(list.problemWith(old.link), PublisherProblem.revoked);
    expect(list.problemWith(me.value.link), PublisherProblem.known);
  });
}
