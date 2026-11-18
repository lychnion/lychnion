import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app/lang.dart';
import '../download/download_store.dart';
import 'shelter_library.dart';
import 'shelter_link.dart';
import 'shelter_server.dart';

/// "Share with people nearby": while this screen is open, the phone passes
/// on what it has downloaded (guides, maps, models) to phones on the same
/// Wi-Fi or hotspot. It does not answer questions (too slow on phones).
///
/// The other phone scans the code, the app adds this phone's signed catalog
/// to its Downloads, and checks every record and file as for any download.
class ShareNearbyScreen extends StatefulWidget {
  const ShareNearbyScreen({super.key, this.store, this.port});

  /// For tests; the app's download store otherwise.
  final DownloadStore? store;

  /// For tests; [ShelterServer.sharePort] otherwise.
  final int? port;

  @override
  State<ShareNearbyScreen> createState() => _ShareNearbyScreenState();
}

class _ShareNearbyScreenState extends State<ShareNearbyScreen> {
  ShelterServer? _server;
  List<String>? _urls;
  int _items = 0;
  int _sent = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
    // A locked phone stops sharing; keep the screen on while it is open.
    unawaited(_wake(true));
  }

  /// Ignored where the platform has no wake lock (tests, desktop).
  static Future<void> _wake(bool on) async {
    try {
      await WakelockPlus.toggle(enable: on);
    } on Object {
      // Sharing still works; the phone may lock on its own.
    }
  }

  Future<void> _start() async {
    try {
      final store = widget.store ?? await DownloadStore.instance();
      final library = ShelterLibrary(store);
      final port = widget.port ?? ShelterServer.sharePort;
      final server = ShelterServer(answerer: null, name: '', library: library)
        ..onBlobServed = (_) {
          if (mounted) setState(() => _sent++);
        };
      await server.start(port: port);
      if (!mounted) {
        await server.stop();
        return;
      }
      final addrs = await ShelterServer.localAddresses();
      setState(() {
        _server = server;
        _items = library.items.length;
        _urls = [for (final a in addrs) 'http://$a:$port'];
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    // Sharing ends with this screen.
    unawaited(_server?.stop());
    unawaited(_wake(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final urls = _urls;
    Widget body;
    if (_error != null) {
      body = Text(_error!);
    } else if (urls == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_items == 0) {
      body = Text(l.shareNearbyNothing);
    } else if (urls.isEmpty) {
      body = Text(l.shareNearbyNoNetwork);
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.shareNearbyIntro),
          const SizedBox(height: 20),
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                // QR codes need a light background, also in dark mode.
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: ShareLink(urls.first).toUri().toString(),
                size: 240,
                padding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: SelectableText(
              urls.first.replaceFirst('http://', ''),
              style: theme.textTheme.titleMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '${l.shareNearbyItems(_items)} · ${l.shareNearbySent(_sent)}',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            l.shareNearbyKeepOpen,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l.shareNearby)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: body,
      ),
    );
  }
}
