import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app/settings.dart';
import 'shelter_link.dart';

/// Shelter computer: a QR code phones scan to connect.
class ShelterQrCard extends StatelessWidget {
  const ShelterQrCard({
    super.key,
    required this.urls,
    required this.name,
    required this.en,
  });

  /// Addresses of this computer on the local network; the first is in the code.
  final List<String> urls;
  final String name;
  final bool en;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (urls.isEmpty) {
      return Text(
        en
            ? 'No network address found. Connect this computer to the shelter Wi-Fi.'
            : 'ネットワークのアドレスがありません。この端末を施設のWi-Fiに接続してください。',
      );
    }
    final link = ShelterLink(urls.first, name: name).toUri().toString();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                // QR codes need a light background, also in dark mode.
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: link,
                size: 168,
                padding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    en ? 'Connect phones' : 'スマートフォンを接続',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    en
                        ? 'On the shelter Wi-Fi, scan this code with the phone camera. fieldkit opens and connects to "$name".'
                        : '施設のWi-Fiに接続したスマートフォンのカメラで読み取ると、fieldkit が開き「$name」に接続します。',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    en ? 'Or enter the address:' : 'またはアドレスを入力：',
                    style: theme.textTheme.bodySmall,
                  ),
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
          ],
        ),
      ),
    );
  }
}

/// Asks before connecting to a shelter from a scanned link.
Future<bool> confirmShelter(
  BuildContext context,
  ShelterLink link, {
  required bool en,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.cell_tower_rounded),
        title: Text(
          en
              ? 'Connect to ${link.name ?? 'this shelter'}?'
              : '${link.name ?? 'この避難所'}に接続しますか？',
        ),
        content: Text(
          en
              ? 'The shelter computer (${link.url.replaceFirst('http://', '')}) will answer your questions and share current information. '
                    'Only connect to a shelter you are at.'
              : '避難所のコンピューター（${link.url.replaceFirst('http://', '')}）が質問に答え、最新の情報を共有します。'
                    'いま居る避難所のコードだけを読み取ってください。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(en ? 'Cancel' : 'キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(en ? 'Connect' : '接続'),
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
    required this.en,
  });

  final AppSettings settings;
  final bool en;

  Future<void> _enter(BuildContext context) async {
    final ctrl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) {
          final ok = ShelterLink.normalize(ctrl.text);
          return AlertDialog(
            title: Text(en ? 'Shelter address' : '避難所のアドレス'),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: '192.168.1.20',
                helperText: en
                    ? 'Shown on the shelter computer, under the QR code.'
                    : '避難所の端末のQRコードの横に表示されています。',
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => ok == null ? null : Navigator.pop(c, ok),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: Text(en ? 'Cancel' : 'キャンセル'),
              ),
              FilledButton(
                onPressed: ok == null ? null : () => Navigator.pop(c, ok),
                child: Text(en ? 'Connect' : '接続'),
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
            ? (en ? 'Connect to a shelter computer' : '避難所のコンピューターに接続')
            : (settings.shelterName ?? url.replaceFirst('http://', '')),
      ),
      subtitle: Text(
        url == null
            ? (en
                  ? 'Scan the QR code at the shelter, or enter its address. Answers come faster.'
                  : '避難所のQRコードを読み取るか、アドレスを入力します。回答が速くなります。')
            : (en
                  ? 'Asked first · ${url.replaceFirst('http://', '')}'
                  : '先にこちらに質問 · ${url.replaceFirst('http://', '')}'),
      ),
      trailing: url == null
          ? const Icon(Icons.chevron_right)
          : IconButton(
              tooltip: en ? 'Disconnect' : '切断',
              onPressed: () => settings.setShelter(null),
              icon: const Icon(Icons.link_off_rounded),
            ),
      onTap: url == null ? () => _enter(context) : null,
    );
  }
}
