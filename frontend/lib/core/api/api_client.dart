import 'package:dio/dio.dart' as dio_pkg;
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../utils/constants.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

class ApiClient {
  late final Dio _dio;
  final _storage = const FlutterSecureStorage();

  ApiClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.apiBaseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 120), // Long for AI generation
        headers: {'Content-Type': 'application/json'},
      ),
    );

    // Retry interceptor — retries connection-level failures (DNS, socket, timeout)
    // with exponential backoff before surfacing the error to the UI.
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (DioException error, handler) async {
          final retryable = error.type == DioExceptionType.connectionError ||
              error.type == DioExceptionType.unknown ||
              error.type == DioExceptionType.connectionTimeout ||
              error.type == DioExceptionType.receiveTimeout;

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

    // JWT interceptor — attaches token and handles 401
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.read(key: AppConstants.tokenStorageKey);
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (DioException error, handler) async {
          if (error.response?.statusCode == 401) {
            // Clear stored credentials and let the router redirect to login
            await _storage.deleteAll();
          }
          return handler.next(error);
        },
      ),
    );
  }

  // ── Auth ──────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> login(String username, String mpin) async {
    final res = await _dio.post('/auth/login', data: {
      'username': username,
      'mpin': mpin,
    });
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> register(
      String username, String mpin, String role,
      {String? parentUsername,
      int? grade,
      List<String>? additionalSubjects,
      List<String>? teachableSubjects}) async {
    final res = await _dio.post('/auth/register', data: {
      'username': username,
      'mpin': mpin,
      'role': role,
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

  Future<List<dynamic>> getTeacherGrades({int? grade, String? subject, int? studentId}) async {
    final res = await _dio.get('/teacher/grades', queryParameters: {
      if (grade != null) 'grade': grade,
      if (subject != null) 'subject': subject,
      if (studentId != null) 'student_id': studentId,
    });
    return res.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> createGrade(Map<String, dynamic> data) async {
    final res = await _dio.post('/teacher/grades', data: data);
    return res.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> getTeacherTests({int? grade}) async {
    final res = await _dio.get('/teacher/tests', queryParameters: {
      if (grade != null) 'grade': grade,
    });
    return res.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> generateTest(FormData formData) async {
    final res = await _dio.post('/teacher/tests/generate', data: formData);
    return res.data as Map<String, dynamic>;
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

  Future<List<dynamic>> getStudentAttendance() async {
    final res = await _dio.get('/student/attendance');
    return res.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> getStudentAttendanceSummary() async {
    final res = await _dio.get('/student/attendance/summary');
    return res.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> getStudentTimetable({required String date}) async {
    final res = await _dio.get('/student/timetable', queryParameters: {'date': date});
    return res.data as List<dynamic>;
  }

  Future<List<dynamic>> getStudentGrades({String? subject, String? gradeType}) async {
    final res = await _dio.get('/student/grades', queryParameters: {
      if (subject != null) 'subject': subject,
      if (gradeType != null) 'grade_type': gradeType,
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

  // ── Parent ────────────────────────────────────────────────────────────────

  Future<List<dynamic>> getChildAttendance() async {
    final res = await _dio.get('/parent/child/attendance');
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

  Future<List<dynamic>> getChildGrades({String? subject, String? gradeType}) async {
    final res = await _dio.get('/parent/child/grades', queryParameters: {
      if (subject != null) 'subject': subject,
      if (gradeType != null) 'grade_type': gradeType,
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

  // ── Homework (Student) ────────────────────────────────────────────────────

  Future<List<dynamic>> getStudentHomework() async {
    final res = await _dio.get('/student/homework');
    return res.data as List<dynamic>;
  }

  // ── Homework (Parent) ─────────────────────────────────────────────────────

  Future<List<dynamic>> getChildHomework() async {
    final res = await _dio.get('/parent/child/homework');
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
}
