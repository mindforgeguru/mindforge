import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mindforge/core/api/websocket_client.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// Seen on the local stack, 2026-10-10: after the backend restarted, one open
// client reconnected ~60 times a second, each socket living 2 ms, and never
// settled. A failed attempt scheduled a retry from more than one callback
// (`ready` failing, the stream erroring, the stream closing), all in the same
// generation; each retry closed whatever socket was current, and that close
// scheduled yet another. Retries multiplied during the outage and then kept
// each other alive after it.
//
// These drive the real client against scripted channels under fake time. Each
// test ends with disconnect(): testWidgets fails a test that leaves a timer
// pending, and a connected client always has its ping timer.

class _FakeSink extends Fake implements WebSocketSink {
  _FakeSink(this._onClose);
  final void Function() _onClose;
  final sent = <Object?>[];

  @override
  void add(Object? data) => sent.add(data);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async => _onClose();
}

class _FakeChannel extends Fake implements WebSocketChannel {
  _FakeChannel({required bool healthy}) {
    sink = _FakeSink(dropFromServer);
    if (healthy) {
      ready = Future<void>.value();
    } else {
      // What a refused connection looks like: `ready` fails, and the stream
      // reports the error and then closes.
      ready = Future<void>.error(StateError('connection refused'));
      scheduleMicrotask(() {
        if (_events.isClosed) return;
        _events.addError(StateError('connection refused'));
        _events.close();
      });
    }
  }

  final _events = StreamController<dynamic>();

  @override
  late final Future<void> ready;

  @override
  late final _FakeSink sink;

  @override
  Stream<dynamic> get stream => _events.stream;

  bool get isOpen => !_events.isClosed;

  /// The server (or the network) ends this socket.
  void dropFromServer() {
    if (!_events.isClosed) _events.close();
  }
}

void main() {
  late bool serverUp;
  late List<_FakeChannel> opened;
  late WebSocketClient client;

  setUp(() {
    serverUp = true;
    opened = [];
    client = WebSocketClient(
      connectChannel: (_) {
        final channel = _FakeChannel(healthy: serverUp);
        opened.add(channel);
        // A runaway client would never let fake time advance. Pull the plug
        // so the test fails on its count instead of hanging.
        if (opened.length > 400) client.disconnect();
        return channel;
      },
    );
  });

  int openNow() => opened.where((c) => c.isOpen).length;

  testWidgets('retries do not multiply while the server is down',
      (tester) async {
    client.connect(7, 'token');
    await tester.pump();
    expect(opened, hasLength(1));

    serverUp = false;
    opened.single.dropFromServer();

    // One minute of outage. With a retry every few seconds that is on the
    // order of 20 attempts; the old client made thousands.
    await tester.pump(const Duration(seconds: 60));
    expect(opened.length, lessThan(30));
    client.disconnect();
  });

  testWidgets('settles on exactly one socket once the server is back',
      (tester) async {
    client.connect(7, 'token');
    await tester.pump();

    serverUp = false;
    opened.single.dropFromServer();
    await tester.pump(const Duration(seconds: 30));

    serverUp = true;
    await tester.pump(const Duration(seconds: 10));
    final afterRecovery = opened.length;
    expect(openNow(), 1);

    // Nothing left over from the outage may touch the healthy socket.
    await tester.pump(const Duration(seconds: 60));
    expect(opened.length, afterRecovery);
    expect(openNow(), 1);
    client.disconnect();
  });

  testWidgets('forceReconnect replaces the socket once, with no echo',
      (tester) async {
    client.connect(7, 'token');
    await tester.pump();

    client.forceReconnect();
    await tester.pump(const Duration(seconds: 30));

    // The deliberately closed socket must not schedule a reconnect of its own.
    expect(opened, hasLength(2));
    expect(openNow(), 1);
    client.disconnect();
  });

  testWidgets('a dropped socket is replaced once', (tester) async {
    client.connect(7, 'token');
    await tester.pump();

    opened.single.dropFromServer();
    await tester.pump(const Duration(seconds: 30));

    expect(opened, hasLength(2));
    expect(openNow(), 1);
    client.disconnect();
  });
}
