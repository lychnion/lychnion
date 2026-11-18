import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app/lang.dart';
import '../app/settings.dart';
import 'shelter_link.dart';

/// Shelter computer: a QR code phones scan to connect.
class ShelterQrCard extends StatelessWidget {
  const ShelterQrCard({
    super.key,
    required this.urls,
    required this.name,
    this.keyText,
  });

  /// Addresses of this computer on the local network; the first is in the code.
  final List<String> urls;
  final String name;

  /// Public signing key, put in the code so phones trust signed facts.
  final String? keyText;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    if (urls.isEmpty) return Text(l.shelterNoAddress);
    final link = ShelterLink(
      urls.first,
      name: name,
      key: keyText,
    ).toUri().toString();
    final web = urls.first;
    Widget qr(String data, String title, String hint) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            // QR codes need a light background, also in dark mode.
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: QrImageView(data: data, size: 160, padding: EdgeInsets.zero),
        ),
        const SizedBox(height: 10),
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 176,
          child: Text(hint, style: theme.textTheme.bodySmall),
        ),
      ],
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.shelterConnectPhones,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            // Two codes: the app (signed facts, its own map), and the
            // browser for phones without the app.
            Wrap(
              spacing: 28,
              runSpacing: 20,
              children: [
                qr(link, l.shelterWithApp, l.shelterScanHint(l.appName, name)),
                qr(web, l.shelterInBrowser, l.shelterBrowserHint),
              ],
            ),
            const SizedBox(height: 14),
            Text(l.shelterOrEnterAddress, style: theme.textTheme.bodySmall),
            for (final u in urls)
              SelectableText(
                u.replaceFirst('http://', ''),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
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
  const ShelterSettingsTile({super.key, required this.settings});

  final AppSettings settings;

  Future<void> _enter(BuildContext context) async {
    final ctrl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) {
          final ok = ShelterLink.normalize(ctrl.text);
          return AlertDialog(
            title: Text(c.l10n.shelterAddress),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: '192.168.1.20',
                helperText: c.l10n.shelterAddressHelper,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => ok == null ? null : Navigator.pop(c, ok),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: Text(c.l10n.cancel),
              ),
              FilledButton(
                onPressed: ok == null ? null : () => Navigator.pop(c, ok),
                child: Text(c.l10n.shelterConnect),
              ),
            ],
          );
        },
      ),
    );
    ctrl.dispose();
    if (url != null) await settings.setShelter(url);
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
