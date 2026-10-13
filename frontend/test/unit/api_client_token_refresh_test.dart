import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindforge/core/api/api_client.dart';

/// A server whose access token 'at-old' has expired. Any request carrying it
/// is answered 401; /auth/refresh behaves as [refresh] says.
class _ExpiredTokenServer implements HttpClientAdapter {
  /// 'ok' reissues the session, 'refused' answers 401, 'offline' never
  /// reaches the server.
  String refresh;
  _ExpiredTokenServer({this.refresh = 'ok'});

  final List<RequestOptions> requests = [];
  int get refreshCalls =>
      requests.where((r) => r.path.contains('/auth/refresh')).length;

  ResponseBody _json(Object body, int status) =>
      ResponseBody.fromString(jsonEncode(body), status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    // Let every request of a burst leave before any answer comes back, as
    // happens on a real network.
    await Future<void>.delayed(const Duration(milliseconds: 5));

    if (options.path.contains('/auth/refresh')) {
      switch (refresh) {
        case 'refused':
          return _json({'detail': 'Invalid or expired refresh token.'}, 401);
        case 'offline':
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionTimeout,
          );
        default:
          return _json(
              {'access_token': 'at-new', 'refresh_token': 'rt-new'}, 200);
      }
    }
    if (options.headers['Authorization'] == 'Bearer at-new') {
      return _json({'ok': true}, 200);
    }
    return _json({'detail': 'Could not validate credentials.'}, 401);
  }

  @override
  void close({bool force = false}) {}
}

({ApiClient client, _ExpiredTokenServer server, List<int> loggedOut}) _rig(
    {String refresh = 'ok'}) {
  final client = ApiClient();
  final server = _ExpiredTokenServer(refresh: refresh);
  client.dio.httpClientAdapter = server;
  client.setCachedTokens(token: 'at-old', refreshToken: 'rt-old');
  final loggedOut = <int>[];
  client.onUnauthorized = () => loggedOut.add(1);
  return (client: client, server: server, loggedOut: loggedOut);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // An access token lasts an hour. When it runs out mid-session the app is
  // meant to swap it for a new one and carry on, without the user noticing.
  test('an expired token is refreshed and the request retried', () async {
    final rig = _rig();

    final res = await rig.client.dio.get('/student/profile');

    expect(res.data, {'ok': true});
    expect(rig.server.refreshCalls, 1);
    expect(rig.client.cachedToken, 'at-new');
    expect(rig.loggedOut, isEmpty);
  });

  // A dashboard fires several requests at once. The refresh token is
  // single-use: a second refresh would present an already-rotated token, be
  // refused, and sign the user out.
  test('requests that expire together share one refresh', () async {
    final rig = _rig();

    final results = await Future.wait([
      for (final path in ['/a', '/b', '/c', '/d', '/e'])
        rig.client.dio.get(path),
    ]);

    expect(results.map((r) => r.statusCode), everyElement(200));
    expect(rig.server.refreshCalls, 1);
    expect(rig.loggedOut, isEmpty);
  });

  test('a refused refresh signs the user out, once', () async {
    final rig = _rig(refresh: 'refused');

    await expectLater(
      Future.wait([rig.client.dio.get('/a'), rig.client.dio.get('/b')]),
      throwsA(isA<DioException>()),
    );

    expect(rig.loggedOut, hasLength(1));
    expect(rig.client.cachedToken, isNull);
  });

  // No signal is not a verdict on the session. The refresh token is good for
  // thirty days; losing it to a tunnel or a bad carrier means typing the
  // MPIN again for nothing.
  test('a refresh that cannot reach the server does not sign the user out',
      () async {
    final rig = _rig(refresh: 'offline');

    await expectLater(
      rig.client.dio.get('/student/profile'),
      throwsA(isA<DioException>()),
    );
    expect(rig.loggedOut, isEmpty);

    // Back in coverage: the same session carries on.
    rig.server.refresh = 'ok';
    final res = await rig.client.dio.get('/student/profile');
    expect(res.data, {'ok': true});
    expect(rig.loggedOut, isEmpty);
  });
}
