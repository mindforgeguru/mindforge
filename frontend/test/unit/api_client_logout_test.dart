import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindforge/core/api/api_client.dart';

/// Captures every outgoing request so the test can assert what was sent.
class _RecordingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString('', 204, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ApiClient.logoutOnServer()', () {
    test('sends refresh_token in body when cache is primed', () async {
      final client = ApiClient();
      final adapter = _RecordingAdapter();
      client.dio.httpClientAdapter = adapter;

      client.setCachedTokens(refreshToken: 'rt-abc-123');

      await client.logoutOnServer();

      expect(adapter.requests, hasLength(1));
      final req = adapter.requests.single;
      expect(req.path, '/auth/logout');
      expect(req.method, 'POST');

      final body = jsonDecode(jsonEncode(req.data)) as Map<String, dynamic>;
      expect(body, {'refresh_token': 'rt-abc-123'});
    });

    test('still hits /auth/logout when no refresh token is cached', () async {
      final client = ApiClient();
      final adapter = _RecordingAdapter();
      client.dio.httpClientAdapter = adapter;

      // Storage read may fail in the test env — that path is expected to
      // swallow the error and send a body-less logout.
      await client.logoutOnServer();

      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.path, '/auth/logout');
      expect(adapter.requests.single.data, isNull);
    });

    test('swallows network errors so callers can always log out locally',
        () async {
      final client = ApiClient();
      // Adapter that throws on every request.
      client.dio.httpClientAdapter = _ThrowingAdapter();

      client.setCachedTokens(refreshToken: 'rt-xyz');

      // Must not throw, even though the underlying request fails.
      await client.logoutOnServer();
    });
  });
}

class _ThrowingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException.connectionError(
      requestOptions: options,
      reason: 'simulated network failure',
    );
  }

  @override
  void close({bool force = false}) {}
}
