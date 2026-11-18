import 'dart:async';

import 'package:flutter/foundation.dart'
    show ValueListenable, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app/lang.dart';
import '../app/settings.dart';
import 'base_discovery.dart';
import 'shelter_link.dart';

/// Shelter computer: the QR code phones scan, one at a time so a camera
/// cannot pick up the wrong one. The browser page comes first: it works on
/// every phone; the app link is for phones with the app.
class ShelterQrCard extends StatefulWidget {
  const ShelterQrCard({
    super.key,
    required this.urls,
    required this.name,
    this.keyText,
    this.large = false,
  });

  /// Addresses of this computer on the local network; the first is in the code.
  final List<String> urls;
  final String name;

  /// Public signing key, put in the code so phones trust signed facts.
  final String? keyText;

  /// Full-screen view (for a screen at the shelter entrance).
  final bool large;

  @override
  State<ShelterQrCard> createState() => _ShelterQrCardState();
}

enum _QrFor { browser, app }

class _ShelterQrCardState extends State<ShelterQrCard> {
  var _for = _QrFor.browser;

  void _showLarge() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (c) => Scaffold(
        appBar: AppBar(title: Text(widget.name)),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ShelterQrCard(
                urls: widget.urls,
                name: widget.name,
                keyText: widget.keyText,
                large: true,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    if (widget.urls.isEmpty) return Text(l.shelterNoAddress);
    final url = widget.urls.first;
    final (data, title, hint) = switch (_for) {
      _QrFor.browser => (url, l.shelterInBrowser, l.shelterBrowserHint),
      _QrFor.app => (
        ShelterLink(
          url,
          name: widget.name,
          key: widget.keyText,
        ).toUri().toString(),
        l.shelterWithApp,
        l.shelterScanHint(l.appName, widget.name),
      ),
    };
    final big = widget.large;
    final code = Container(
      padding: EdgeInsets.all(big ? 16 : 10),
      decoration: BoxDecoration(
        // QR codes need a light background, also in dark mode.
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: QrImageView(
        data: data,
        size: big ? 320 : 180,
        padding: EdgeInsets.zero,
        semanticsLabel: l.shelterQrSpoken(widget.name),
      ),
    );
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style:
              (big
                      ? theme.textTheme.headlineSmall
                      : theme.textTheme.titleMedium)
                  ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(hint, style: big ? theme.textTheme.titleMedium : null),
        SizedBox(height: big ? 24 : 16),
        Text(l.shelterOrEnterAddress, style: theme.textTheme.bodySmall),
        for (final u in widget.urls)
          SelectableText(
            u.replaceFirst('http://', ''),
            style:
                (big
                        ? theme.textTheme.headlineSmall
                        : theme.textTheme.titleMedium)
                    ?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
          ),
      ],
    );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(big ? 28 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.shelterConnectPhones,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (!big)
                  TextButton.icon(
                    onPressed: _showLarge,
                    icon: const Icon(Icons.fullscreen_rounded),
                    label: Text(l.shareShowLarge),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<_QrFor>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: _QrFor.browser,
                  icon: const Icon(Icons.language_rounded),
                  label: Text(l.shelterInBrowser),
                ),
                ButtonSegment(
                  value: _QrFor.app,
                  icon: const Icon(Icons.phone_iphone_rounded),
                  label: Text(l.shelterWithApp),
                ),
              ],
              selected: {_for},
              onSelectionChanged: (s) => setState(() => _for = s.first),
            ),
            const SizedBox(height: 20),
            // Side by side when there is room, else the code on top.
            LayoutBuilder(
              builder: (context, box) => box.maxWidth >= (big ? 640 : 460)
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        code,
                        const SizedBox(width: 24),
                        Expanded(child: text),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [code, const SizedBox(height: 16), text],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks before connecting to a shelter from a scanned link.
Future<bool> confirmShelter(BuildContext context, ShelterLink link) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.cell_tower_rounded),
        title: Text(
          c.l10n.shelterConnectTo(link.name ?? c.l10n.shelterThisShelter),
        ),
        content: Text(
          c.l10n.shelterConnectBody(link.url.replaceFirst('http://', '')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(c.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(c.l10n.shelterConnect),
          ),
        ],
      ),
    ) ??
    false;

/// Settings section on a phone: the saved shelter, connect by address.
class ShelterSettingsTile extends StatelessWidget {
  const ShelterSettingsTile({
    super.key,
    required this.settings,
    @visibleForTesting this.newFinder,
  });

  final AppSettings settings;

  /// Tests: what lists the bases on the Wi-Fi.
  final BaseFinder Function()? newFinder;

  Future<void> _enter(BuildContext context) async {
    final picked = await showDialog<(ShelterLink, bool)>(
      context: context,
      builder: (_) => _AddressDialog(newFinder: newFinder),
    );
    if (picked == null) return;
    final (link, found) = picked;
    // A base found on the Wi-Fi: the same question as for a QR code.
    if (found) {
      if (!context.mounted || !await confirmShelter(context, link)) return;
    }
    // No key: an announcement is not checked in person, so the base's
    // facts are trusted only after its QR code is scanned.
    await settings.setShelter(link.url, name: link.name);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final url = settings.shelterUrl;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.secondaryContainer,
        foregroundColor: scheme.onSecondaryContainer,
        child: const Icon(Icons.cell_tower_rounded, size: 20),
      ),
      title: Text(
        url == null
            ? l.shelterConnectComputer
            : (settings.shelterName ?? url.replaceFirst('http://', '')),
      ),
      subtitle: Text(
        url == null
            ? l.shelterConnectComputerHint
            : settings.shelterKey == null
            ? '${l.shelterAskedFirst(url.replaceFirst('http://', ''))}\n'
                  '${l.shelterScanToTrust}'
            : l.shelterAskedFirst(url.replaceFirst('http://', '')),
      ),
      trailing: url == null
          ? const Icon(Icons.chevron_right)
          : IconButton(
              tooltip: l.shelterDisconnect,
              onPressed: () => settings.setShelter(null),
              icon: const Icon(Icons.link_off_rounded),
            ),
      onTap: url == null ? () => _enter(context) : null,
    );
  }
}

/// Settings section on a computer: share on the local network, the
/// shelter's name, and the QR codes phones scan while sharing.
class ShelterShareSection extends StatelessWidget {
  const ShelterShareSection({
    super.key,
    required this.settings,
    required this.urls,
    this.keyText,
  });

  final AppSettings settings;

  /// This computer's addresses while sharing (empty until it starts).
  final ValueListenable<List<String>> urls;
  final String? keyText;

  /// Asks for the shelter's name; null when cancelled.
  static Future<String?> askName(BuildContext context, String? current) =>
      showDialog<String>(
        context: context,
        builder: (_) => _NameDialog(current),
      );

  Future<void> _toggle(BuildContext context, bool on) async {
    // A shelter needs a name before phones see it.
    if (on && settings.sharingName == null) {
      final name = await askName(context, null);
      if (name == null) return;
      await settings.setSharing(true, name: name);
      return;
    }
    await settings.setSharing(on);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final name = settings.sharingName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          secondary: const Icon(Icons.cell_tower_rounded),
          title: Text(l.shareOnNetwork),
          subtitle: Text(l.shareOnNetworkHint),
          value: settings.sharing,
          onChanged: (on) => _toggle(context, on),
        ),
        if (settings.sharing) ...[
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: const Icon(Icons.badge_outlined),
            title: Text(l.shareName),
            subtitle: Text(name ?? ''),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final n = await askName(context, name);
              if (n != null) await settings.setSharing(true, name: n);
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: ValueListenableBuilder(
              valueListenable: urls,
              builder: (context, u, _) => u.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(l.shareStarting),
                    )
                  : ShelterQrCard(urls: u, name: name ?? '', keyText: keyText),
            ),
          ),
        ],
      ],
    );
  }
}

/// The shelter's name. Owns its text controller, so the controller lives
/// until the dialog has finished closing.
class _NameDialog extends StatefulWidget {
  const _NameDialog(this.current);

  final String? current;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _ctrl = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ok = _ctrl.text.trim().isNotEmpty;
    void done() => Navigator.pop(context, _ctrl.text.trim());
    return AlertDialog(
      title: Text(l.shareName),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        maxLength: 60,
        decoration: InputDecoration(helperText: l.shareNameHint),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => ok ? done() : null,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(onPressed: ok ? done : null, child: Text(l.save)),
      ],
    );
  }
}

/// A base found on the Wi-Fi, or its address typed by hand. Returns the
/// link and whether it was found (then the caller asks first). Owns its
/// text controller, so the controller lives until the dialog has finished
/// closing.
class _AddressDialog extends StatefulWidget {
  const _AddressDialog({this.newFinder});

  final BaseFinder Function()? newFinder;

  @override
  State<_AddressDialog> createState() => _AddressDialogState();
}

class _AddressDialogState extends State<_AddressDialog> {
  final _ctrl = TextEditingController();
  late final _finder = widget.newFinder?.call() ?? BaseFinder();

  /// False when this device cannot look (no Wi-Fi discovery here).
  var _looking = true;

  /// After a while without a base, the spinner gives way to a line (it
  /// still keeps looking).
  var _waited = false;
  Timer? _wait;

  @override
  void initState() {
    super.initState();
    unawaited(
      _finder.start().catchError((Object _) {
        if (mounted) setState(() => _looking = false);
      }),
    );
    _wait = Timer(const Duration(seconds: 15), () {
      if (mounted) setState(() => _waited = true);
    });
  }

  @override
  void dispose() {
    _wait?.cancel();
    _finder.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final ok = ShelterLink.normalize(_ctrl.text);
    void typed() => Navigator.pop(context, (ShelterLink(ok!), false));
    return AlertDialog(
      title: Text(l.shelterAddress),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_looking) ...[
              Text(
                l.shelterFoundTitle,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              ValueListenableBuilder(
                valueListenable: _finder.found,
                builder: (c, found, _) => found.isEmpty
                    ? ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: _waited
                            ? const Icon(Icons.wifi_find_rounded)
                            : const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                        title: Text(
                          _waited ? l.shelterFoundNone : l.shelterFoundLooking,
                        ),
                      )
                    : ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              for (final b in found)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.cell_tower_rounded),
                                  title: Text(b.name ?? l.shelterThisShelter),
                                  subtitle: Text(
                                    b.url.replaceFirst('http://', ''),
                                  ),
                                  onTap: () =>
                                      Navigator.pop(context, (b, true)),
                                ),
                            ],
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _ctrl,
              autofocus: !_looking,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: '192.168.1.20',
                helperText: l.shelterAddressHelper,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => ok == null ? null : typed(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: ok == null ? null : typed,
          child: Text(l.shelterConnect),
        ),
      ],
    );
  }
}
