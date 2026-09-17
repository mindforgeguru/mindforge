import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindforge/core/api/api_client.dart';

/// Answers the MPIN change with a reissued session, as the server does, and
/// records every request so the test can see which token the next one carries.
class _ReissuingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final body = options.path.endsWith('/profile/mpin')
        ? {
            'message': 'MPIN updated successfully.',
            'access_token': 'at-new',
            'refresh_token': 'rt-new',
            'token_type': 'bearer',
          }
        : <String, dynamic>{};
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The server ends every session on an MPIN change, the caller's included.
  // If the client kept its old tokens, the next request would 401 and the
  // user would be logged out for changing their MPIN.
  final changes = <String, Future<void> Function(ApiClient)>{
    'admin': (c) => c.changeAdminMpin('847362', '592814'),
    'teacher': (c) => c.changeTeacherMpin('847362', '592814'),
    'student': (c) => c.changeStudentMpin('847362', '592814'),
    'parent': (c) => c.changeParentMpin('847362', '592814'),
  };

  for (final entry in changes.entries) {
    test('${entry.key} MPIN change adopts the reissued session', () async {
      final client = ApiClient();
      final adapter = _ReissuingAdapter();
      client.dio.httpClientAdapter = adapter;
      client.setCachedTokens(token: 'at-old', refreshToken: 'rt-old');

      await entry.value(client);

      expect(client.cachedToken, 'at-new');

      await client.dio.get('/student/profile');
      expect(
        adapter.requests.last.headers['Authorization'],
        'Bearer at-new',
      );
    });
  }
}
