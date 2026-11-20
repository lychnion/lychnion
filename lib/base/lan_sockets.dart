/// Listening only on the local network (lychnion/lychnion#64).
///
/// The base and Share nearby are for the phones on the same Wi-Fi or
/// hotspot. Bound to `0.0.0.0` they were also reachable on every other
/// interface: a desktop base on its upstream office or public network (or
/// the internet, with a public address), a sharing phone on mobile data.
/// [LanSockets] binds one socket per local-network address instead, the
/// same addresses the screen shows, and follows the network as it changes.
library;

import 'dart:async';
import 'dart:io';

/// A [ServerSocket] made of one socket per local-network address, all on
/// the same port. Every [every] it looks at the addresses again: it binds
/// new ones (the phone joined a Wi-Fi, the hotspot came on) and closes
/// those that went away. Connections already open stay open.
class LanSockets extends Stream<Socket> implements ServerSocket {
  LanSockets._(this._port, this._addresses);

  /// Binds [port] on each of [addresses] (by default the device's own,
  /// BaseServer.localAddresses). Throws when there are addresses but none
  /// could be bound (for example the port is taken); with no address yet
  /// it waits for one.
  static Future<LanSockets> bind(
    int port, {
    required Future<List<String>> Function() addresses,
    Duration every = const Duration(seconds: 10),
  }) async {
    final s = LanSockets._(port, addresses);
    final error = await s._sync();
    if (error != null && s._bound.isEmpty) {
      await s.close();
      throw error;
    }
    s._timer = Timer.periodic(every, (_) => unawaited(s._serial()));
    return s;
  }

  int _port;
  final Future<List<String>> Function() _addresses;
  Timer? _timer;
  var _closed = false;

  final _bound = <String, (ServerSocket, StreamSubscription<Socket>)>{};
  final _out = StreamController<Socket>();

  /// Called after the bound addresses changed.
  void Function(List<String> addresses)? onChanged;

  /// Called when an address could not be bound, once per new error (for
  /// the log: the port is taken there, the address went away).
  void Function(SocketException error)? onError;

  /// The addresses listened on now, in the order the address list gave
  /// them last (the first one goes in the QR code).
  List<String> get addresses {
    int at(String a) {
      final i = _order.indexOf(a);
      return i < 0 ? _order.length : i;
    }

    return List<String>.unmodifiable(
      <String>[..._bound.keys]..sort((a, b) => at(a).compareTo(at(b))),
    );
  }

  /// The addresses as the list gave them last.
  var _order = const <String>[];

  /// Why the last look could not bind an address, or null.
  SocketException? get lastError => _lastError;
  SocketException? _lastError;

  Future<void> _running = Future.value();

  Future<void> _serial() {
    final next = _running.then((_) => _sync());
    _running = next.catchError((Object _) => null);
    return next;
  }

  /// Binds new addresses and closes old ones; returns the first error, if
  /// any.
  Future<SocketException?> _sync() async {
    if (_closed) return null;
    final List<String> want;
    try {
      want = await _addresses();
    } on Object catch (e) {
      return _lastError = SocketException(
        'Could not list the network addresses: $e',
      );
    }
    SocketException? error;
    final before = addresses;
    _order = List.of(want);
    var changed = false;
    for (final a in [..._bound.keys]) {
      if (want.contains(a)) continue;
      final (socket, sub) = _bound[a]!;
      await sub.cancel();
      await socket.close();
      // Listed until it is closed.
      _bound.remove(a);
      changed = true;
    }
    for (final a in want) {
      if (_bound.containsKey(a) || _closed) continue;
      try {
        final socket = await ServerSocket.bind(a, _port);
        if (_closed) {
          await socket.close();
          break;
        }
        // Port 0 (tests): the other addresses take the same port.
        if (_port == 0) _port = socket.port;
        // Cancelled when the address goes away or in close().
        // ignore: cancel_subscriptions
        final sub = socket.listen(
          _out.add,
          // For the server's log (too many open files, …). An interface
          // that went away is closed by the next look.
          onError: (Object e, StackTrace s) {
            if (!_out.isClosed) _out.addError(e, s);
          },
        );
        _bound[a] = (socket, sub);
        changed = true;
      } on SocketException catch (e) {
        error ??= e;
      }
    }
    // Each new error once, not every 10 seconds.
    if (error != null && '$error' != '$_lastError') {
      try {
        onError?.call(error);
      } on Object {
        // A log callback must not stop the next look.
      }
    }
    _lastError = error;
    final after = addresses;
    if (changed || !_sameList(before, after)) {
      try {
        onChanged?.call(after);
      } on Object {
        // A screen that went away must not stop the next look.
      }
    }
    return error;
  }

  static bool _sameList(List<String> a, List<String> b) =>
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);

  @override
  StreamSubscription<Socket> listen(
    void Function(Socket event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _out.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  int get port => _port;

  /// Any IPv4 address: there may be several, see [addresses].
  @override
  InternetAddress get address => InternetAddress.anyIPv4;

  @override
  Future<ServerSocket> close() async {
    _closed = true;
    _timer?.cancel();
    await _running;
    for (final (socket, sub) in _bound.values) {
      await sub.cancel();
      await socket.close();
    }
    _bound.clear();
    // Not awaited: without a listener the done event never arrives.
    if (!_out.isClosed) unawaited(_out.close());
    return this;
  }
}
