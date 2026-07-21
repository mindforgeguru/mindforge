import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindforge/features/owner/screens/owner_dashboard_screen.dart';

// Regression: the owner console used to format errors with
// `e.toString().indexOf('detail')`, but a DioException's toString() never
// includes the response body — so a 409 "slug already exists" surfaced as a
// raw exception dump instead of the backend's friendly message.
DioException _dio({dynamic data, int? status}) => DioException(
      requestOptions: RequestOptions(path: '/owner/schools'),
      response: Response(
        requestOptions: RequestOptions(path: '/owner/schools'),
        data: data,
        statusCode: status,
      ),
      type: DioExceptionType.badResponse,
    );

void main() {
  group('ownerApiErrorMessage', () {
    test('extracts the backend detail string (409 duplicate slug)', () {
      final e = _dio(
        data: {'detail': "A school with slug 'qa-academy' already exists."},
        status: 409,
      );
      expect(ownerApiErrorMessage(e),
          "A school with slug 'qa-academy' already exists.");
    });

    test('extracts the first msg from a FastAPI 422 detail list', () {
      final e = _dio(
        data: {
          'detail': [
            {'msg': 'value is not a valid email address', 'loc': ['body', 'contact_email']},
          ],
        },
        status: 422,
      );
      expect(ownerApiErrorMessage(e), 'value is not a valid email address');
    });

    test("strips Pydantic's 'Value error, ' prefix from a validator message", () {
      final e = _dio(
        data: {
          'detail': [
            {'msg': 'Value error, MPIN is too easy to guess.', 'loc': ['body', 'mpin']},
          ],
        },
        status: 422,
      );
      expect(ownerApiErrorMessage(e), 'MPIN is too easy to guess.');
      expect(ownerApiErrorMessage(e), isNot(startsWith('Value error')));
    });

    test('never leaks the raw DioException toString()', () {
      final e = _dio(
        data: {'detail': "A school with slug 'qa-academy' already exists."},
        status: 409,
      );
      final msg = ownerApiErrorMessage(e);
      expect(msg, isNot(contains('DioException')));
      expect(msg, isNot(contains('validateStatus')));
    });

    test('falls back to the status code when the body has no usable detail', () {
      final e = _dio(data: '<html>502 Bad Gateway</html>', status: 502);
      expect(ownerApiErrorMessage(e), contains('502'));
    });

    test('handles a non-Dio error without dumping its type', () {
      expect(ownerApiErrorMessage(StateError('boom')),
          'Something went wrong. Please try again.');
    });
  });
}
