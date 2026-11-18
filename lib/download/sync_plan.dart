import 'package:connectivity_plus/connectivity_plus.dart';

import 'catalog.dart';
import 'download_manager.dart' show ItemStatus;

// What the app fetches by itself (docs/distribution.md, step 5): new
// versions of what is installed (automatic updates), and on a base that
// keeps everything for phones, every guide and map it does not have yet.

/// Error codes after which an item is not tried again by itself: it would
/// fail the same way (signature, version, id of another publisher).
const _final = {'signature', 'older', 'taken'};

/// The items to download now, in catalog order.
///
/// [updates]: automatic updates are on. [keepAll]: this computer keeps a
/// full set for phones; [keepModels] adds the models (gigabytes).
/// [status] and [error] are each item's state now.
List<CatalogItem> itemsToSync(
  Catalog c, {
  required ItemStatus Function(CatalogItem) status,
  required String? Function(CatalogItem) error,
  required bool updates,
  required bool keepAll,
  required bool keepModels,
}) => [
  for (final i in c.items)
    if (!_final.contains(error(i)) && i.record != null)
      if (switch (status(i)) {
        ItemStatus.update => updates || (keepAll && _kept(i, keepModels)),
        // Unverified: its files are here, download() checks them and only
        // fetches what does not match.
        ItemStatus.absent ||
        ItemStatus.partial ||
        ItemStatus.unverified => keepAll && _kept(i, keepModels),
        _ => false,
      })
        i,
];

bool _kept(CatalogItem i, bool keepModels) =>
    i.kind != ItemKind.model || keepModels;

/// Whether the app may fetch by itself on [now]: never offline; on a
/// computer (a base) on any connection; on a phone only on Wi-Fi or a
/// cable, whatever the mobile data setting says.
bool syncAllowed(List<ConnectivityResult> now, {required bool desktop}) {
  if (now.isEmpty || now.every((c) => c == ConnectivityResult.none)) {
    return false;
  }
  if (desktop) return true;
  return now.any(
    (c) => c == ConnectivityResult.wifi || c == ConnectivityResult.ethernet,
  );
}

/// Whether [now] is a connection at all (to notice one coming back).
bool isOnline(List<ConnectivityResult> now) =>
    now.any((c) => c != ConnectivityResult.none);
