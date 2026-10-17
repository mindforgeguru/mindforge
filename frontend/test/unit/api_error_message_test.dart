import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindforge/core/utils/api_error.dart';

// Seventy-four snackbars and error texts across the app were written as
// `Text('Upload failed: $e')`. A DioException's toString() is a paragraph about
// validateStatus — and it never contains the response body, so the backend's
// own sentence ("Theme locked until level 5.") was lost as well. apiErrorMessage
// is what they show instead.
DioException _dio({dynamic data, int? status, DioExceptionType? type}) =>
    DioException(
      requestOptions: RequestOptions(path: '/x'),
      response: status == null
          ? null
          : Response(
              requestOptions: RequestOptions(path: '/x'),
              data: data,
              statusCode: status,
            ),
      type: type ?? DioExceptionType.badResponse,
    );

void main() {
  group('apiErrorMessage', () {
    test("shows the backend's detail sentence", () {
      final e = _dio(data: {'detail': 'Theme locked until level 5.'}, status: 403);
      expect(apiErrorMessage(e), 'Theme locked until level 5.');
    });

    test('takes the first msg of a FastAPI 422 list, without the "Value error, " prefix', () {
      final e = _dio(data: {
        'detail': [
          {'msg': 'Value error, MPIN is too easy to guess.', 'loc': ['body', 'mpin']},
        ],
      }, status: 422);
      expect(apiErrorMessage(e), 'MPIN is too easy to guess.');
    });

    test('never shows the DioException text', () {
      final e = _dio(data: {'detail': 'Nope.'}, status: 409);
      expect(apiErrorMessage(e), isNot(contains('DioException')));
      expect(apiErrorMessage(e), isNot(contains('validateStatus')));
    });

    test('a server error with no usable body says so, with the status', () {
      final msg = apiErrorMessage(_dio(data: '<html>502 Bad Gateway</html>', status: 502));
      expect(msg, contains('502'));
      expect(msg, isNot(contains('<html>')));
    });

    test('no response at all reads as a connection problem', () {
      final e = _dio(type: DioExceptionType.connectionError);
      expect(apiErrorMessage(e), contains('reach the server'));
    });

    test('a timeout says it timed out', () {
      for (final t in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        expect(apiErrorMessage(_dio(type: t)), contains('timed out'), reason: '$t');
      }
    });

    test("the app's own Exception('…') shows its sentence, not the type", () {
      expect(apiErrorMessage(Exception('Please choose a PDF first.')),
          'Please choose a PDF first.');
    });

    test('anything else is a plain apology', () {
      expect(apiErrorMessage(StateError('boom')),
          'Something went wrong. Please try again.');
    });
  });
  fieldNamedMessages();
}

// Pydantic's stock messages don't name the field: "String should have at most
// 300 characters" could be about the title or the description. The 422 carries
// the field in `loc`, so the message can say which.
void fieldNamedMessages() {
  group('a stock 422 message names its field', () {
    Map<String, dynamic> err(String type, List loc, String msg, [Map? ctx]) =>
        {'detail': [{'type': type, 'loc': loc, 'msg': msg, if (ctx != null) 'ctx': ctx}]};

    test('too long', () {
      final e = _dio(status: 422, data: err('string_too_long', ['body', 'title'],
          'String should have at most 300 characters', {'max_length': 300}));
      expect(apiErrorMessage(e), 'Title must be at most 300 characters.');
    });
    test('empty', () {
      final e = _dio(status: 422, data: err('string_too_short', ['body', 'message'],
          'String should have at least 1 character', {'min_length': 1}));
      expect(apiErrorMessage(e), "Message can't be empty.");
    });
    test('too small', () {
      final e = _dio(status: 422, data: err('greater_than', ['body', 'amount'],
          'Input should be greater than 0', {'gt': 0}));
      expect(apiErrorMessage(e), 'Amount must be more than 0.');
    });
    test('too big', () {
      final e = _dio(status: 422, data: err('less_than', ['body', 'base_amount'],
          'Input should be less than 100000000', {'lt': 100000000}));
      expect(apiErrorMessage(e), 'Base amount must be less than 100000000.');
    });
    test('a custom validator keeps its own sentence', () {
      final e = _dio(status: 422, data: err('value_error', ['body', 'grade'],
          'Value error, Grade must be 8, 9, or 10.'));
      expect(apiErrorMessage(e), 'Grade must be 8, 9, or 10.');
    });
    test('an unknown type falls back to the message', () {
      final e = _dio(status: 422, data: err('literal_error', ['body', 'target_type'],
          "Input should be 'all' or 'grade'"));
      expect(apiErrorMessage(e), "Input should be 'all' or 'grade'");
    });
  });
}
