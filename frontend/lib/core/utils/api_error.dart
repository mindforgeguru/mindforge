import 'package:dio/dio.dart';

/// A sentence a user can read, from whatever an API call threw.
///
/// Screens used to show `'Upload failed: $e'`. For a DioException that is a
/// paragraph about validateStatus, and it never includes the response body —
/// so the backend's own explanation ({"detail": "..."}) was lost too. This digs
/// the detail out of the parsed body (a string, or FastAPI's 422 list of
/// {"msg": ...}), and otherwise says plainly what kind of failure it was.
String apiErrorMessage(Object e) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map) {
      final detail = data['detail'];
      if (detail is String && detail.isNotEmpty) return _clean(detail);
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first['msg'] is String) {
          return _fieldMessage(first) ?? _clean(first['msg'] as String);
        }
      }
      if (detail != null) return _clean(detail.toString());
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'The request timed out. Please try again.';
      case DioExceptionType.connectionError:
        return "Couldn't reach the server. Check your connection and try again.";
      default:
        break;
    }
    final status = e.response?.statusCode;
    if (status != null) return 'Request failed (HTTP $status). Please try again.';
    return "Couldn't reach the server. Check your connection and try again.";
  }
  // The app's own `throw Exception('Please choose a file.')` carries a sentence
  // meant for the user; drop the type name Dart puts in front of it.
  if (e is Exception) {
    final s = e.toString();
    const prefix = 'Exception: ';
    if (s.startsWith(prefix) && s.length > prefix.length) {
      return s.substring(prefix.length);
    }
  }
  return 'Something went wrong. Please try again.';
}

// Pydantic v2 prepends "Value error, " to messages raised from a custom
// validator (e.g. the weak-MPIN check), and it rides through the 422 body into
// the UI. Strip that machine prefix so the user sees just the sentence.
String _clean(String msg) {
  const prefix = 'Value error, ';
  return msg.startsWith(prefix) ? msg.substring(prefix.length) : msg;
}

// Pydantic's stock messages don't say which field they are about ("String
// should have at most 300 characters"), but the 422 names it in `loc`. For the
// limits the request schemas set, say it with the field's name.
String? _fieldMessage(Map err) {
  final loc = err['loc'];
  final ctx = err['ctx'] is Map ? err['ctx'] as Map : const {};
  if (loc is! List || loc.isEmpty || loc.last is! String) return null;
  final raw = (loc.last as String).replaceAll('_', ' ');
  final field = raw.isEmpty ? raw : raw[0].toUpperCase() + raw.substring(1);
  switch (err['type']) {
    case 'string_too_long':
      return '$field must be at most ${ctx['max_length']} characters.';
    case 'string_too_short':
      return ctx['min_length'] == 1
          ? "$field can't be empty."
          : '$field must be at least ${ctx['min_length']} characters.';
    case 'greater_than':
      return '$field must be more than ${ctx['gt']}.';
    case 'greater_than_equal':
      return '$field must be ${ctx['ge']} or more.';
    case 'less_than':
      return '$field must be less than ${ctx['lt']}.';
    case 'less_than_equal':
      return '$field must be ${ctx['le']} or less.';
    case 'finite_number':
      return '$field must be a number.';
    default:
      return null;
  }
}
