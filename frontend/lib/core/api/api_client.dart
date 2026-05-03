import 'package:dio/dio.dart' as dio_pkg;
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:meta/meta.dart';

import '../security/ssl_pinning.dart';
import '../utils/constants.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

const _androidOptions = AndroidOptions(encryptedSharedPreferences: true);

class ApiClient {
  late final Dio _dio;
  final _storage = const FlutterSecureStorage(
    aOptions: _androidOptions,
  );

  @visibleForTesting
  Dio get dio => _dio;

  // In-memory token cache — avoids hitting the Android Keystore on every
  // request, which can be slow right after a phone unlock.
  String? _cachedToken;
  String? _cachedRefreshToken;

  // Refresh mutex — at most one POST /auth/refresh in-flight at a time.
  // Concurrent 401 responses share this future; they all wait for the single
  // refresh to complete, then retry with the new token. Without this, 5+
  // simultaneous dashboard requests each get 401, each trigger a refresh,
  // the second one fails (token already rotated), and the user gets logged out.
  Future<String?>? _refreshFuture;

  /// Called when the server returns 401 (token expired / revoked).
  /// AuthNotifier sets this to its logout callback so the router
  /// redirects to login without the user having to do anything.
  void Function()? onUnauthorized;

  /// Prime the in-memory cache after login or token refresh so that
  /// the first request after a phone unlock does not block on storage.
  void setCachedTokens({String? token, String? refreshToken}) {
    if (token != null) _cachedToken = token;
    if (refreshToken != null) _cachedRefreshToken = refreshToken;
  }

  /// Clear the cache on logout.
  void clearCachedTokens() {
    _cachedToken = null;
    _cachedRefreshToken = null;
  }

  ApiClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.apiBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    // Retry interceptor — retries connection-level failures (DNS, socket, timeout)
    // with exponential backoff before surfacing the error to the UI.
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (DioException error, handler) async {
          // Only retry connection-level failures, not timeouts (retrying a
          // timed-out request just multiplies the wait time for the user).
          final retryable = error.type == DioExceptionType.connectionError ||
              error.type == DioExceptionType.unknown;

          if (retryable) {
            final attempt =
                error.requestOptions.extra['_retryCount'] as int? ?? 0;
            if (attempt < 3) {
              error.requestOptions.extra['_retryCount'] = attempt + 1;
              // Exponential backoff: 1 s, 2 s, 4 s
              await Future.delayed(Duration(seconds: 1 << attempt));
              try {
                final response = await _dio.fetch(error.requestOptions);
                return handler.resolve(response);
              } on DioException catch (e) {
                return handler.next(e);
              }
            }
          }
          return handler.next(error);
        },
      ),
    );

    // JWT interceptor — attaches token and handles 401 with refresh logic
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Use in-memory cache to avoid slow Keystore access after unlock.
          try {
            _cachedToken ??=
                await _storage.read(key: AppConstants.tokenStorageKey);
          } catch (_) {}
          if (_cachedToken != null) {
            options.headers['Authorization'] = 'Bearer $_cachedToken';
          }
          return handler.next(options);
        },
        onError: (DioException error, handler) async {
          if (error.response?.statusCode == 401) {
            // Don't retry the refresh endpoint, the login endpoint, or
            // requests that explicitly opted out.
            if (error.requestOptions.path.contains('/auth/refresh') ||
                error.requestOptions.path.contains('/auth/login') ||
                error.requestOptions.extra['_skipRefresh'] == true) {
              _cachedToken = null;
              _cachedRefreshToken = null;
              try { await _storage.deleteAll(); } catch (_) {}
              onUnauthorized?.call();
              return handler.next(error);
            }

            // De-duplicate concurrent refreshes with a shared future (mutex).
            // If a refresh is already in-flight, wait for it instead of
            // starting another one — prevents the race condition where the
            // second refresh uses an already-rotated token and fails.
            _refreshFuture ??= _executeRefresh()
                .whenComplete(() => _refreshFuture = null);
            final newToken = await _refreshFuture;

            if (newToken != null) {
              final retryOptions = error.requestOptions;
              retryOptions.headers['Authorization'] = 'Bearer $newToken';
              try {
                final response = await _dio.fetch(retryOptions);
                return handler.resolve(response);
              } on DioException catch (e) {
                return handler.next(e);
              }
            }
            // newToken == null means _executeRefresh already called onUnauthorized
          }
          return handler.next(error);
        },
      ),
    );

    // SSL certificate pinning — validates server cert fingerprint on every
    // connection. Skipped on web (TLS is handled by the browser) and in
    // debug mode to allow local proxy inspection.
    if (!kIsWeb) {
      applySSLPinning(_dio.httpClientAdapter as IOHttpClientAdapter);
    }
  }

  // ── Internal refresh helper ───────────────────────────────────────────────

  /// Performs a single token refresh. Returns the new access token, or null
  /// if the refresh token is missing/expired (in which case the user is
  /// logged out via [onUnauthorized]).
  Future<String?> _executeRefresh() async {
    try {
      _cachedRefreshToken ??=
          await _storage.read(key: AppConstants.refreshTokenStorageKey);
    } catch (_) {}
    final rt = _cachedRefreshToken;
    if (rt == null) {
      _cachedToken = null;
      try { await _storage.deleteAll(); } catch (_) {}
      onUnauthorized?.call();
      return null;
    }
    try {
      final res = await _dio.post(
        '/auth/refresh',
        data: {'refresh_token': rt},
        options: Options(
          headers: {'Authorization': null},
          extra: {'_skipRefresh': true},
        ),
      );
      final body = res.data as Map<String, dynamic>;
      final newToken = body['access_token'] as String;
      final newRefresh = body['refresh_token'] as String?;
      _cachedToken = newToken;
      if (newRefresh != null) _cachedRefreshToken = newRefresh;
      try {
        await _storage.write(key: AppConstants.tokenStorageKey, value: newToken);
        if (newRefresh != null) {
          await _storage.write(key: AppConstants.refreshTokenStorageKey, value: newRefresh);
        }
      } catch (_) {}
      return newToken;
    } catch (_) {
      _cachedToken = null;
      _cachedRefreshToken = null;
      try { await _storage.deleteAll(); } catch (_) {}
      onUnauthorized?.call();
      return null;
    }
  }

  // ── Auth ──────────────────────────────────────────────────────────────────

  /// Exchanges a refresh token for a new access token.
  /// Bypasses the JWT interceptor so it doesn't trigger a recursive refresh.
  Future<Map<String, dynamic>> refreshAccessToken(String refreshToken) async {
    final res = await _dio.post(
      '/auth/refresh',
      data: {'refresh_token': refreshToken},
      options: Options(
        headers: {'Authorization': null},
        extra: {'_skipRefresh': true},
      ),
    );
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> login(String username, String mpin) async {
    final res = await _dio.post('/auth/login', data: {
      'username': username,
      'mpin': mpin,
    });
    return res.data as Map<String, dynamic>;
  }

  /// Tells the server to revoke the current access + refresh tokens.
  /// Sends the refresh token in the body so the server can blacklist its
  /// JTI; without this, a captured refresh token could mint new access
  /// tokens after logout. Errors are swallowed — local session is always
  /// cleared regardless.
  Future<void> logoutOnServer() async {
    try {
      _cachedRefreshToken ??=
          await _storage.read(key: AppConstants.refreshTokenStorageKey);
    } catch (_) {}
    try {
      await _dio.post(
        '/auth/logout',
        data: _cachedRefreshToken != null
            ? {'refresh_token': _cachedRefreshToken}
            : null,
        options: Options(extra: {'_skipRefresh': true}),
      );
    } catch (_) {}
  }

  Future<Map<String, dynamic>> register(
      String username, String mpin, String role,
      {String? phone,
      String? email,
      String? parentUsername,
      int? grade,
      List<String>? additionalSubjects,
      List<String>? teachableSubjects}) async {
    final res = await _dio.post('/auth/register', data: {
      'username': username,
      'mpin': mpin,
      'role': role,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      if (email != null && email.isNotEmpty) 'email': email,
      if (parentUsername != null && parentUsername.isNotEmpty)
        'parent_username': parentUsername,
      if (grade != null) 'grade': grade,
      if (additionalSubjects != null) 'additional_subjects': additionalSubjects,
      if (teachableSubjects != null) 'teachable_subjects': teachableSubjects,
    });
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getMe() async {
    final res = await _dio.get('/auth/me');
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> uploadAdminPhoto(
      List<int> bytes, String filename) async {
    final formData = dio_pkg.FormData.fromMap({
      'file': dio_pkg.MultipartFile.fromBytes(bytes, filename: filename),
    });
    final res = await _dio.post('/admin/profile/photo', data: formData);
    return res.data as Map<String, dynamic>;
  }

  Future<void> changeAdminMpin(
      String currentMpin, String newMpin) async {
    await _dio.put('/admin/profile/mpin', data: {
      'current_mpin': currentMpin,
      'new_mpin': newMpin,
    });
  }

  Future<void> editAdminUsername(String newUsername) async {
    await _dio.put('/admin/profile/username', data: {'username': newUsername});
  }

  // ── Teacher ───────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> uploadTeacherPhoto(
      List<int> bytes, String filename) async {
    final formData = dio_pkg.FormData.fromMap({
      'file': dio_pkg.MultipartFile.fromBytes(bytes, filename: filename),
    });
    final res = await _dio.post('/teacher/profile/photo', data: formData);
    return res.data as Map<String, dynamic>;
  }

  Future<void> changeTeacherMpin(
      String currentMpin, String newMpin) async {
    await _dio.put('/teacher/profile/mpin', data: {
      'current_mpin': currentMpin,
      'new_mpin': newMpin,
    });
  }

  Future<List<dynamic>> getStudentsInGrade(int grade) async {
    final res = await _dio.get('/teacher/students', queryParameters: {'grade': grade});
    return res.data as List<dynamic>;
  }

  Future<List<dynamic>> getTeacherAttendance(int grade, {String? date}) async {
    final res = await _dio.get('/teacher/attendance', queryParameters: {
      'grade': grade,
      if (date != null) 'date': date,
    });
    return res.data as List<dynamic>;
  }

  Future<List<String>> getTeacherAttendanceDates(int grade, String month) async {
    final res = await _dio.get('/teacher/attendance/dates', queryParameters: {
      'grade': grade,
      'month': month,
    });
    return (res.data as List<dynamic>).map((e) => e.toString()).toList();
  }

  Future<List<dynamic>> markAttendance(Map<String, dynamic> payload) async {
    final res = await _dio.post('/teacher/attendance', data: payload);
    return res.data as List<dynamic>;
  }

  Future<List<dynamic>> getTeacherTimetable(int grade, {required String date}) async {
    final res = await _dio.get('/teacher/timetable', queryParameters: {'grade': grade, 'date': date});
    return res.data as List<dynamic>;
  }

  Future<List<dynamic>> getTeachers() async {
    final res = await _dio.get('/teacher/teachers');
    return res.data as List<dynamic>;
  }

  Future<Map<String, dynamic>?> getTeacherTimetableConfig() async {
    try {
      final res = await _dio.get('/teacher/timetable-config');
      if (res.data == null) return null;
      return res.data as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<List<dynamic>> getMyTimetable() async {
    final res = await _dio.get('/teacher/my-timetable');
    return res.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> createTimetableSlot(Map<String, dynamic> data) async {
    final res = await _dio.post('/teacher/timetable', data: data);
    return res.data as Map<String, dynamic>;
  }

  Future<void> deleteTimetable(int grade, String date) async {
    await _dio.post('/teacher/timetable/delete',
        queryParameters: {'grade': grade, 'date': date});
  }

  Future<List<dynamic>> getTeacherGrades({int? grade, String? subject, int? studentId, int skip = 0, int limit = 50}) async {
    final res = await _dio.get('/teacher/grades', queryParameters: {
      if (grade != null) 'grade': grade,
      if (subject != null) 'subject': subject,
      if (studentId != null) 'student_id': studentId,
      if (skip > 0) 'skip': skip,
      if (limit != 50) 'limit': limit,
    });
    return res.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> createGrade(Map<String, dynamic> data) async {
    final res = await _dio.post('/teacher/grades', data: data);
    return res.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> getTeacherTests({int? grade, int skip = 0, int limit = 20}) async {
    final res = await _dio.get('/teacher/tests', queryParameters: {
      if (grade != null) 'grade': grade,
      'skip': skip,
      'limit': limit,
    });
    return res.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> generateTest(FormData formData) async {
    final res = await _dio.post(
      '/teacher/tests/generate',
      data: formData,
      options: Options(receiveTimeout: const Duration(seconds: 180)),
    );
    return res.data as Map<String, dynamic>;
  }

  // ── Teacher database ──────────────────────────────────────────────────────

  Future<List<dynamic>> listOldTestPapers({int? grade, String? subject}) async {
    final res = await _dio.get('/teacher/database/old-tests', queryParameters: {
      if (grade != null) 'grade': grade,
      if (subject != null) 'subject': subject,
    });
    return res.data as List<dynamic>;
  }

  Future<List<dynamic>> uploadOldTestPapers(FormData formData) async {
    final res = await _dio.post(
      '/teacher/database/old-tests/upload',
      data: formData,
      options: Options(receiveTimeout: const Duration(seconds: 120)),
    );
    return res.data as List<dynamic>;
  }

  Future<void> deleteOldTestPaper(int id) async {
    await _dio.delete('/teacher/database/old-tests/$id');
  }

  Future<List<Map<String, dynamic>>> listChapterNames(int grade, String subject) async {
    final res = await _dio.get('/teacher/database/chapters/names',
        queryParameters: {'grade': grade, 'subject': subject});
    return (res.data as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<List<dynamic>> listChapterDocuments({int? grade, String? subject}) async {
    final res = await _dio.get('/teacher/database/chapters', queryParameters: {
      if (grade != null) 'grade': grade,
      if (subject != null) 'subject': subject,
    });
    return res.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> uploadChapterDocument(FormData formData) async {
    final res = await _dio.post(
      '/teacher/database/chapters/upload',
      data: formData,
      options: Options(receiveTimeout: const Duration(seconds: 120)),
    );
    return res.data as Map<String, dynamic>;
  }

  Future<void> deleteChapterDocument(int id) async {
    await _dio.delete('/teacher/database/chapters/$id');
  }

  Future<List<dynamic>> listSyllabus({int? grade, String? subject}) async {
    final res = await _dio.get('/teacher/database/syllabus', queryParameters: {
      if (grade != null) 'grade': grade,
      if (subject != null) 'subject': subject,
    });
    return res.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> uploadSyllabus(FormData formData) async {
    final res = await _dio.post('/teacher/database/syllabus/upload', data: formData,
        options: Options(receiveTimeout: const Duration(seconds: 120)));
    return res.data as Map<String, dynamic>;
  }

  Future<void> deleteSyllabus(int id) async {
    await _dio.delete('/teacher/database/syllabus/$id');
  }

  Future<Map<String, dynamic>> getTest(int testId) async {
    final res = await _dio.get('/teacher/tests/$testId');
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getTestPdfUrls(int testId) async {
    final res = await _dio.get('/teacher/tests/$testId/pdf-urls');
    return res.data as Map<String, dynamic>;
  }

  Future<List<int>> downloadTestPdf(int testId) async {
    final res = await _dio.get<List<int>>(
      '/teacher/tests/$testId/download-pdf',
      options: Options(responseType: ResponseType.bytes),
    );
    return res.data!;
  }

  Future<List<int>> downloadAnswerKeyPdf(int testId) async {
    final res = await _dio.get<List<int>>(
      '/teacher/tests/$testId/download-answer-key',
      options: Options(responseType: ResponseType.bytes),
    );
    return res.data!;
  }

  Future<List<dynamic>> getTestSubmissions(int testId) async {
    final res = await _dio.get('/teacher/tests/$testId/submissions');
    return res.data as List<dynamic>;
  }

  Future<List<dynamic>> getTestGrades(int testId) async {
    final res = await _dio.get('/teacher/tests/$testId/grades');
    return res.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> saveOfflineGrades(
      int testId, List<Map<String, dynamic>> grades) async {
    final res = await _dio.post(
      '/teacher/tests/$testId/offline-grades',
      data: {'grades': grades},
    );
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> publishTest(int testId) async {
    final res = await _dio.post('/teacher/tests/$testId/publish');
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateTestQuestions(
      int testId, List<Map<String, dynamic>> questions) async {
    final res = await _dio.put(
      '/teacher/tests/$testId/questions',
      data: {'questions': questions},
    );
    return res.data as Map<String, dynamic>;
  }

  Future<void> deleteTest(int testId) async {
    await _dio.delete('/teacher/tests/$testId');
  }

  // ── Student ───────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> uploadStudentPhoto(
      List<int> bytes, String filename) async {
    final formData = dio_pkg.FormData.fromMap({
      'file': dio_pkg.MultipartFile.fromBytes(bytes, filename: filename),
    });
    final res = await _dio.post('/student/profile/picture', data: formData);
    return res.data as Map<String, dynamic>;
  }

  Future<void> changeStudentMpin(
      String currentMpin, String newMpin) async {
    await _dio.put('/student/profile/mpin', data: {
      'current_mpin': currentMpin,
      'new_mpin': newMpin,
    });
  }

  Future<void> changeParentMpin(
      String currentMpin, String newMpin) async {
    await _dio.put('/parent/profile/mpin', data: {
      'current_mpin': currentMpin,
      'new_mpin': newMpin,
    });
  }

  Future<Map<String, dynamic>> getStudentProfile() async {
    final res = await _dio.get('/student/profile');
    return res.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> getStudentAttendance({int skip = 0, int limit = 50}) async {
    final res = await _dio.get('/student/attendance', queryParameters: {
      if (skip > 0) 'skip': skip,
      if (limit != 50) 'limit': limit,
    });
    return res.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> getStudentAttendanceSummary() async {
    final res = await _dio.get('/student/attendance/summary');
    return res.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> getFaculty() async {
    final res = await _dio.get('/student/faculty');
    return res.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> getTeacherBio() async {
    final res = await _dio.get('/teacher/profile/bio');
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateTeacherBio(String bio) async {
    final res = await _dio.put('/teacher/profile/bio', data: {'bio': bio});
    return res.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> getClassAttendanceLeaderboard({int limit = 7}) async {
    final res = await _dio.get('/student/attendance/class-leaderboard',
        queryParameters: {'limit': limit});
    return res.data as List<dynamic>;
  }

  Future<List<dynamic>> getStudentTimetable({required String date}) async {
    final res = await _dio.get('/student/timetable', queryParameters: {'date': date});
    return res.data as List<dynamic>;
  }

  Future<List<dynamic>> getStudentGrades({String? subject, String? gradeType, int skip = 0, int limit = 50}) async {
    final res = await _dio.get('/student/grades', queryParameters: {
      if (subject != null) 'subject': subject,
      if (gradeType != null) 'grade_type': gradeType,
      if (skip > 0) 'skip': skip,
      if (limit != 50) 'limit': limit,
    });
    return res.data as List<dynamic>;
  }

  Future<List<dynamic>> getPendingTests() async {
    final res = await _dio.get('/student/tests/pending');
    return res.data as List<dynamic>;
  }

  Future<List<dynamic>> getStudentOfflineTests() async {
    final res = await _dio.get('/student/tests/offline');
    return res.data as List<dynamic>;
  }

  Future<List<dynamic>> getStudentCompletedTests() async {
    final res = await _dio.get('/student/tests/completed');
    return res.data as List<dynamic>;
  }

  Future<List<dynamic>> getChildTests() async {
    final res = await _dio.get('/parent/child/tests');
    return res.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> getTestReview(int testId) async {
    final res = await _dio.get('/student/tests/$testId/review');
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> submitTest(
      int testId, Map<String, dynamic> answers, bool autoSubmitted) async {
    final res = await _dio.post('/student/tests/$testId/submit', data: {
      'answers': answers,
      'auto_submitted': autoSubmitted,
    });
    return res.data as Map<String, dynamic>;
  }

  /// Start (or resume) the student's single attempt at an online test.
  /// Returns questions, any autosaved answers, and remaining_seconds.
  /// If the deadline has already passed the response carries
  /// is_finalized=true so the caller can show the result dialog.
  Future<Map<String, dynamic>> startTestAttempt(int testId) async {
    final res = await _dio.post('/student/tests/$testId/start');
    return res.data as Map<String, dynamic>;
  }

  /// Autosave the in-progress attempt's answers. Returns remaining_seconds.
  /// Throws DioException with status 410 once the deadline has passed
  /// (server finalizes the attempt at that point).
  Future<Map<String, dynamic>> saveTestAnswers(
      int testId, Map<String, dynamic> answers) async {
    final res = await _dio.post('/student/tests/$testId/save', data: {
      'answers': answers,
    });
    return res.data as Map<String, dynamic>;
  }

  /// Forfeit an in-progress online test attempt. Score becomes 0 and the
  /// row is finalized. Idempotent — safe to call when already finalized.
  Future<Map<String, dynamic>> forfeitTest(int testId) async {
    final res = await _dio.post('/student/tests/$testId/forfeit');
    return res.data as Map<String, dynamic>;
  }

  // ── Parent ────────────────────────────────────────────────────────────────

  Future<List<dynamic>> getChildAttendance({int skip = 0, int limit = 50}) async {
    final res = await _dio.get('/parent/child/attendance', queryParameters: {
      if (skip > 0) 'skip': skip,
      if (limit != 50) 'limit': limit,
    });
    return res.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> getChildAttendanceSummary() async {
    final res = await _dio.get('/parent/child/attendance/summary');
    return res.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> getChildTimetable({required String date}) async {
    final res = await _dio.get('/parent/child/timetable', queryParameters: {'date': date});
    return res.data as List<dynamic>;
  }

  Future<List<dynamic>> getChildGrades({String? subject, String? gradeType, int skip = 0, int limit = 50}) async {
    final res = await _dio.get('/parent/child/grades', queryParameters: {
      if (subject != null) 'subject': subject,
      if (gradeType != null) 'grade_type': gradeType,
      if (skip > 0) 'skip': skip,
      if (limit != 50) 'limit': limit,
    });
    return res.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> getChildFees({String? academicYear}) async {
    final res = await _dio.get('/parent/fees', queryParameters: {
      if (academicYear != null) 'academic_year': academicYear,
    });
    return res.data as Map<String, dynamic>;
  }

  // ── Admin ─────────────────────────────────────────────────────────────────

  Future<List<dynamic>> getPendingUsers() async {
    final res = await _dio.get('/admin/users/pending');
    return res.data as List<dynamic>;
  }

  Future<List<dynamic>> getAllUsers({String? role, int? grade}) async {
    final res = await _dio.get('/admin/users', queryParameters: {
      if (role != null) 'role': role,
      if (grade != null) 'grade': grade,
    });
    return res.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> approveUser(int userId) async {
    final res = await _dio.post('/admin/users/$userId/approve');
    return res.data as Map<String, dynamic>;
  }

  Future<void> revokeUser(int userId) async {
    await _dio.delete('/admin/users/$userId/revoke');
  }

  Future<Map<String, dynamic>> editUser(int userId, Map<String, dynamic> data) async {
    final res = await _dio.put('/admin/users/$userId', data: data);
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> setUserActive(int userId, bool isActive) async {
    final res = await _dio.patch('/admin/users/$userId/active',
        data: {'is_active': isActive});
    return res.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> getFeeSummaries(String academicYear) async {
    final res = await _dio.get('/admin/fees/summary',
        queryParameters: {'academic_year': academicYear});
    return res.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> uploadQrCode(List<int> bytes, String filename, int slot) async {
    final formData = dio_pkg.FormData.fromMap({
      'file': dio_pkg.MultipartFile.fromBytes(bytes, filename: filename),
    });
    final res = await _dio.post('/admin/fees/payment-info/$slot/qr', data: formData);
    return res.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> getFeeStructures({String? academicYear}) async {
    final res = await _dio.get('/admin/fees/structure', queryParameters: {
      if (academicYear != null) 'academic_year': academicYear,
    });
    return res.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> createFeeStructure(Map<String, dynamic> data) async {
    final res = await _dio.post('/admin/fees/structure', data: data);
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateFeeStructure(
      int id, Map<String, dynamic> data) async {
    final res = await _dio.put('/admin/fees/structure/$id', data: data);
    return res.data as Map<String, dynamic>;
  }

  Future<void> deleteFeeStructure(int id) async {
    await _dio.delete('/admin/fees/structure/$id');
  }

  Future<Map<String, dynamic>> recordFeePayment(Map<String, dynamic> data) async {
    final res = await _dio.post('/admin/fees/payments', data: data);
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateFeePayment(
      int paymentId, double amount, String? notes) async {
    final res = await _dio.put('/admin/fees/payments/$paymentId', data: {
      'amount': amount,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });
    return res.data as Map<String, dynamic>;
  }

  Future<void> deleteFeePayment(int paymentId) async {
    await _dio.delete('/admin/fees/payments/$paymentId');
  }

  Future<List<dynamic>> getPaymentInfo() async {
    try {
      final res = await _dio.get('/admin/fees/payment-info');
      return res.data as List<dynamic>;
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> updatePaymentInfo(int slot, Map<String, dynamic> data) async {
    final res = await _dio.put('/admin/fees/payment-info/$slot', data: data);
    return res.data as Map<String, dynamic>;
  }

  // ── Academic Year ─────────────────────────────────────────────────────────

  Future<List<dynamic>> getAcademicYears() async {
    final res = await _dio.get('/admin/academic-years');
    return res.data as List<dynamic>;
  }

  Future<Map<String, dynamic>?> getCurrentAcademicYear() async {
    final res = await _dio.get('/admin/academic-years/current');
    return res.data as Map<String, dynamic>?;
  }

  Future<Map<String, dynamic>> startNewAcademicYear() async {
    final res = await _dio.post('/admin/academic-years/new');
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> initAcademicYear() async {
    final res = await _dio.post('/admin/academic-years/init');
    return res.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> getUsersByYear(int yearId, {String? role}) async {
    final res = await _dio.get('/admin/academic-years/$yearId/users',
        queryParameters: {if (role != null) 'role': role});
    return res.data as List<dynamic>;
  }

  Future<Map<String, dynamic>?> getTimetableConfig() async {
    final res = await _dio.get('/admin/timetable/config');
    return res.data as Map<String, dynamic>?;
  }

  Future<Map<String, dynamic>> updateTimetableConfig(Map<String, dynamic> data) async {
    final res = await _dio.put('/admin/timetable/config', data: data);
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> clearTimetableSlots({int? grade}) async {
    final res = await _dio.delete(
      '/admin/timetable/slots',
      queryParameters: grade != null ? {'grade': grade} : null,
    );
    return res.data as Map<String, dynamic>;
  }

  // ── Homework (Teacher) ────────────────────────────────────────────────────

  Future<List<dynamic>> getTeacherHomework({int? grade}) async {
    final res = await _dio.get('/teacher/homework', queryParameters: {
      if (grade != null) 'grade': grade,
    });
    return res.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> createHomework(Map<String, dynamic> data) async {
    final res = await _dio.post('/teacher/homework', data: data);
    return res.data as Map<String, dynamic>;
  }

  Future<void> deleteHomework(int homeworkId) async {
    await _dio.delete('/teacher/homework/$homeworkId');
  }

  // ── Homework completions (Teacher) ────────────────────────────────────────

  Future<Map<String, dynamic>> listHomeworkCompletions(int homeworkId) async {
    final res = await _dio.get('/teacher/homework/$homeworkId/completions');
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> upsertHomeworkCompletions(
      int homeworkId, List<Map<String, dynamic>> records) async {
    final res = await _dio.put(
      '/teacher/homework/$homeworkId/completions',
      data: {'records': records},
    );
    return res.data as Map<String, dynamic>;
  }

  // ── Homework (Student) ────────────────────────────────────────────────────

  Future<List<dynamic>> getStudentHomework() async {
    final res = await _dio.get('/student/homework');
    return res.data as List<dynamic>;
  }

  Future<List<dynamic>> getStudentHomeworkCompletions() async {
    final res = await _dio.get('/student/homework/completions');
    return res.data as List<dynamic>;
  }

  // ── Homework (Parent) ─────────────────────────────────────────────────────

  Future<List<dynamic>> getChildHomework() async {
    final res = await _dio.get('/parent/child/homework');
    return res.data as List<dynamic>;
  }

  Future<List<dynamic>> getChildHomeworkCompletions() async {
    final res = await _dio.get('/parent/child/homework/completions');
    return res.data as List<dynamic>;
  }

  // ── Broadcast (Teacher) ───────────────────────────────────────────────────

  Future<Map<String, dynamic>> sendBroadcast(Map<String, dynamic> data) async {
    final res = await _dio.post('/teacher/broadcast', data: data);
    return res.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> getTeacherBroadcasts() async {
    final res = await _dio.get('/teacher/broadcast');
    return res.data as List<dynamic>;
  }

  // ── Broadcasts (Student) ──────────────────────────────────────────────────

  Future<List<dynamic>> getStudentBroadcasts() async {
    final res = await _dio.get('/student/broadcasts');
    return res.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> getStudentFees({String? academicYear}) async {
    final res = await _dio.get('/student/fees', queryParameters: {
      if (academicYear != null) 'academic_year': academicYear,
    });
    return res.data as Map<String, dynamic>;
  }

  // ── Broadcasts (Parent) ───────────────────────────────────────────────────

  Future<List<dynamic>> getParentBroadcasts() async {
    final res = await _dio.get('/parent/broadcasts');
    return res.data as List<dynamic>;
  }

  Future<List<int>> downloadPendingFeesReport(String academicYear) async {
    final res = await _dio.get(
      '/admin/reports/pending-fees',
      queryParameters: {'academic_year': academicYear},
      options: Options(responseType: ResponseType.bytes),
    );
    return res.data as List<int>;
  }

  Future<List<int>> downloadStudentLedger(int studentId, String academicYear) async {
    final res = await _dio.get(
      '/admin/reports/student-ledger/$studentId',
      queryParameters: {'academic_year': academicYear},
      options: Options(responseType: ResponseType.bytes),
    );
    return res.data as List<int>;
  }

  // ── Dashboard summary endpoints ──────────────────────────────────────────────

  Future<Map<String, dynamic>> getStudentDashboardSummary({String? date}) async {
    final res = await _dio.get('/student/dashboard-summary', queryParameters: {
      if (date != null) 'date': date,
    });
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getTeacherDashboardSummary() async {
    final res = await _dio.get('/teacher/dashboard-summary');
    return res.data as Map<String, dynamic>;
  }

  /// Per-grade workflow snapshot used by the teacher dashboard card.
  /// Shape: { date, is_holiday_for_teacher, grades: [{grade, is_holiday,
  /// attendance_taken, pending_review_homework_ids, can_assign_new_homework,
  /// next_step}] }
  Future<Map<String, dynamic>> getTeacherTodayWorkflow() async {
    final res = await _dio.get('/teacher/today-workflow');
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getParentDashboardSummary({String? date}) async {
    final res = await _dio.get('/parent/dashboard-summary', queryParameters: {
      if (date != null) 'date': date,
    });
    return res.data as Map<String, dynamic>;
  }

  // ── FCM token registration ───────────────────────────────────────────────────

  Future<void> updateFcmToken(String token) async {
    await _dio.put('/auth/fcm-token', data: {'fcm_token': token});
  }

  // ── XP / Level system ────────────────────────────────────────────────────────

  /// Current student's XP snapshot — total, level, progress, last 10 txns.
  Future<Map<String, dynamic>> getMyXp() async {
    final res = await _dio.get('/xp/me');
    return res.data as Map<String, dynamic>;
  }

  /// Leaderboard. `scope` is 'class' | 'grade' | 'school'.
  Future<Map<String, dynamic>> getLeaderboard({
    String scope = 'grade',
    int limit = 20,
  }) async {
    final res = await _dio.get('/xp/leaderboard', queryParameters: {
      'scope': scope,
      'limit': limit,
    });
    return res.data as Map<String, dynamic>;
  }

  /// Admin/teacher view of any student's XP. Students may only call with
  /// their own id (server enforces — see /api/xp/student/{id}).
  Future<Map<String, dynamic>> getStudentXp(int studentId) async {
    final res = await _dio.get('/xp/student/$studentId');
    return res.data as Map<String, dynamic>;
  }

  /// Admin manual XP adjustment. `amount` may be negative; `reason` required.
  Future<Map<String, dynamic>> adjustStudentXp({
    required int studentId,
    required int amount,
    required String reason,
  }) async {
    final res = await _dio.post('/xp/admin/adjust', data: {
      'student_id': studentId,
      'amount': amount,
      'reason': reason,
    });
    return res.data as Map<String, dynamic>;
  }

  /// Full level table (50 rows seeded by migration 021).
  Future<List<dynamic>> getLevels() async {
    final res = await _dio.get('/xp/levels');
    return res.data as List<dynamic>;
  }

  /// Cosmetic theme catalogue with the current student's lock state.
  Future<Map<String, dynamic>> getThemes() async {
    final res = await _dio.get('/xp/themes');
    return res.data as Map<String, dynamic>;
  }

  /// Pick an unlocked theme. Pass null to revert to the default theme.
  /// Backend returns the refreshed catalogue.
  Future<Map<String, dynamic>> selectTheme(String? themeId) async {
    final res = await _dio.post('/xp/themes/select', data: {
      'theme_id': themeId,
    });
    return res.data as Map<String, dynamic>;
  }
}
