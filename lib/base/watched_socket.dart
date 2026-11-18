import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A connection that says when the other side has gone ([gone]).
///
/// HttpServer does not tell while a request is being answered: the phone
/// may have closed the connection minutes ago, and only writing the
/// answer shows it. The connection's incoming bytes end (or fail) as soon
/// as the phone closes it, and this wrapper listens for that.
///
/// This relies on HttpServer reading on while a request is answered (it
/// does in Dart 3.12 to 3.14; base_limits_test checks it). A client that
/// closes only its sending side counts as gone; the app's clients never
/// do that.
class WatchedSocket extends StreamView<Uint8List> implements Socket {
  WatchedSocket(this._socket) : super(_socket);

  final Socket _socket;
  final _gone = Completer<void>();

  /// Completes when the other side closed the connection (or it failed).
  Future<void> get gone => _gone.future;

  /// Whether [gone] has completed.
  bool get isGone => _gone.isCompleted;

  void _markGone() {
    if (!_gone.isCompleted) _gone.complete();
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _socket.listen(
    onData,
    onError: (Object e, StackTrace st) {
      _markGone();
      if (onError is void Function(Object, StackTrace)) {
        onError(e, st);
      } else if (onError is void Function(Object)) {
        onError(e);
      } else {
        // As without a handler: the error is not lost.
        Zone.current.handleUncaughtError(e, st);
      }
    },
    onDone: () {
      _markGone();
      onDone?.call();
    },
    cancelOnError: cancelOnError,
  );

  @override
  InternetAddress get address => _socket.address;
  @override
  int get port => _socket.port;
  @override
  InternetAddress get remoteAddress => _socket.remoteAddress;
  @override
  int get remotePort => _socket.remotePort;
  @override
  Encoding get encoding => _socket.encoding;
  @override
  set encoding(Encoding e) => _socket.encoding = e;
  @override
  void add(List<int> data) => _socket.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _socket.addError(error, stackTrace);
  @override
  Future<void> addStream(Stream<List<int>> stream) => _socket.addStream(stream);
  @override
  Future<void> close() => _socket.close();
  @override
  void destroy() {
    _markGone();
    _socket.destroy();
  }

  @override
  Future<void> get done => _socket.done;
  @override
  Future<void> flush() => _socket.flush();
  @override
  bool setOption(SocketOption option, bool enabled) =>
      _socket.setOption(option, enabled);
  @override
  Uint8List getRawOption(RawSocketOption option) =>
      _socket.getRawOption(option);
  @override
  void setRawOption(RawSocketOption option) => _socket.setRawOption(option);
  @override
  void write(Object? object) => _socket.write(object);
  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      _socket.writeAll(objects, separator);
  @override
  void writeCharCode(int charCode) => _socket.writeCharCode(charCode);
  @override
  void writeln([Object? object = '']) => _socket.writeln(object);
}
