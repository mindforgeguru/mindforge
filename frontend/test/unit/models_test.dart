import 'package:flutter_test/flutter_test.dart';
import 'package:mindforge/core/models/test.dart';
import 'package:mindforge/core/models/timetable.dart';
import 'package:mindforge/core/models/grade.dart';

// ── Shared fixtures ───────────────────────────────────────────────────────────

Map<String, dynamic> _testJson({
  int id = 1,
  String? expiresAt,
  List<dynamic>? questions,
  bool isGraded = false,
}) =>
    {
      'id': id,
      'title': 'Chapter 3 Quiz',
      'teacher_id': 7,
      'grade': 9,
      'subject': 'mathematics',
      'source_file_url': null,
      'answer_key_url': null,
      'test_type': 'online',
      'questions': questions,
      'total_marks': 50.0,
      'time_limit_minutes': 30,
      'is_published': true,
      'is_graded': isGraded,
      'created_at': '2026-01-15T10:00:00',
      'expires_at': expiresAt,
    };

Map<String, dynamic> _slotJson({bool isHoliday = false, String? subject}) => {
      'id': 3,
      'grade': 8,
      'slot_date': '2026-04-21',
      'period_number': 2,
      'subject': subject,
      'teacher_id': 5,
      'teacher_username': 'mr_sharma',
      'start_time': '09:00',
      'end_time': '09:45',
      'is_holiday': isHoliday,
      'comment': isHoliday ? 'Diwali holiday' : null,
    };

Map<String, dynamic> _gradeJson({int? teacherId, int? testId}) => {
      'id': 11,
      'student_id': 22,
      'teacher_id': teacherId,
      'subject': 'economics',
      'chapter': 'Supply and Demand',
      'test_id': testId,
      'marks_obtained': 38.0,
      'max_marks': 50.0,
      'percentage': 76.0,
      'grade_type': 'offline',
      'created_at': '2026-03-10T08:30:00',
    };

// ── TestModel ─────────────────────────────────────────────────────────────────

void main() {
  group('TestModel.fromJson', () {
    test('parses all required fields correctly', () {
      final m = TestModel.fromJson(_testJson());
      expect(m.id, 1);
      expect(m.title, 'Chapter 3 Quiz');
      expect(m.teacherId, 7);
      expect(m.grade, 9);
      expect(m.subject, 'mathematics');
      expect(m.testType, 'online');
      expect(m.totalMarks, 50.0);
      expect(m.timeLimitMinutes, 30);
      expect(m.isPublished, isTrue);
    });

    test('parses createdAt as DateTime', () {
      final m = TestModel.fromJson(_testJson());
      expect(m.createdAt, isA<DateTime>());
      expect(m.createdAt.year, 2026);
      expect(m.createdAt.month, 1);
      expect(m.createdAt.day, 15);
    });

    test('expiresAt is null when not provided', () {
      final m = TestModel.fromJson(_testJson());
      expect(m.expiresAt, isNull);
    });

    test('parses expiresAt when provided', () {
      final m = TestModel.fromJson(_testJson(expiresAt: '2026-12-31T23:59:59'));
      expect(m.expiresAt, isNotNull);
      expect(m.expiresAt!.year, 2026);
    });

    test('isExpired is false when expiresAt is null', () {
      expect(TestModel.fromJson(_testJson()).isExpired, isFalse);
    });

    test('isExpired is false when expiresAt is in future', () {
      final future = DateTime.now().add(const Duration(days: 1)).toIso8601String();
      final m = TestModel.fromJson(_testJson(expiresAt: future));
      expect(m.isExpired, isFalse);
    });

    test('isExpired is true when expiresAt is in past', () {
      final past = '2020-01-01T00:00:00';
      final m = TestModel.fromJson(_testJson(expiresAt: past));
      expect(m.isExpired, isTrue);
    });

    test('questionCount returns 0 when questions is null', () {
      final m = TestModel.fromJson(_testJson(questions: null));
      expect(m.questionCount, 0);
    });

    test('questionCount returns correct count', () {
      final q = [
        {'text': 'Q1', 'options': ['a', 'b']},
        {'text': 'Q2', 'options': ['c', 'd']},
      ];
      final m = TestModel.fromJson(_testJson(questions: q));
      expect(m.questionCount, 2);
    });

    test('isGraded defaults to false when field is absent/null', () {
      final json = _testJson()..remove('is_graded');
      final m = TestModel.fromJson(json);
      expect(m.isGraded, isFalse);
    });

    test('isGraded parses true correctly', () {
      final m = TestModel.fromJson(_testJson(isGraded: true));
      expect(m.isGraded, isTrue);
    });
  });

  // ── TimetableSlotModel ───────────────────────────────────────────────────────

  group('TimetableSlotModel.fromJson', () {
    test('parses all fields correctly', () {
      final m = TimetableSlotModel.fromJson(_slotJson(subject: 'mathematics'));
      expect(m.id, 3);
      expect(m.grade, 8);
      expect(m.slotDate, '2026-04-21');
      expect(m.periodNumber, 2);
      expect(m.subject, 'mathematics');
      expect(m.teacherUsername, 'mr_sharma');
      expect(m.startTime, '09:00');
      expect(m.endTime, '09:45');
      expect(m.isHoliday, isFalse);
    });

    test('isHoliday flag is parsed correctly when true', () {
      final m = TimetableSlotModel.fromJson(_slotJson(isHoliday: true));
      expect(m.isHoliday, isTrue);
      expect(m.comment, 'Diwali holiday');
    });

    test('subject is null for a free/holiday slot', () {
      final m = TimetableSlotModel.fromJson(_slotJson(isHoliday: true));
      expect(m.subject, isNull);
    });

    test('optional fields are null when absent', () {
      final json = {
        'id': 1,
        'grade': 9,
        'slot_date': '2026-04-21',
        'period_number': 1,
        'subject': null,
        'teacher_id': null,
        'teacher_username': null,
        'start_time': null,
        'end_time': null,
        'is_holiday': false,
        'comment': null,
      };
      final m = TimetableSlotModel.fromJson(json);
      expect(m.subject, isNull);
      expect(m.teacherId, isNull);
      expect(m.startTime, isNull);
      expect(m.comment, isNull);
    });

    test('slotDate is stored as a string, not parsed to DateTime', () {
      final m = TimetableSlotModel.fromJson(_slotJson());
      expect(m.slotDate, isA<String>());
      expect(m.slotDate, '2026-04-21');
    });
  });

  // ── GradeModel ───────────────────────────────────────────────────────────────

  group('GradeModel.fromJson', () {
    test('parses all required fields', () {
      final m = GradeModel.fromJson(_gradeJson(teacherId: 5, testId: 10));
      expect(m.id, 11);
      expect(m.studentId, 22);
      expect(m.teacherId, 5);
      expect(m.subject, 'economics');
      expect(m.chapter, 'Supply and Demand');
      expect(m.testId, 10);
      expect(m.marksObtained, 38.0);
      expect(m.maxMarks, 50.0);
      expect(m.percentage, 76.0);
      expect(m.gradeType, 'offline');
    });

    test('teacherId is null when not provided', () {
      final m = GradeModel.fromJson(_gradeJson());
      expect(m.teacherId, isNull);
    });

    test('testId is null when not provided', () {
      final m = GradeModel.fromJson(_gradeJson());
      expect(m.testId, isNull);
    });

    test('parses createdAt as DateTime', () {
      final m = GradeModel.fromJson(_gradeJson());
      expect(m.createdAt, isA<DateTime>());
      expect(m.createdAt.year, 2026);
      expect(m.createdAt.month, 3);
    });

    test('marksObtained and maxMarks accept integer JSON values', () {
      final json = _gradeJson();
      json['marks_obtained'] = 38; // int in JSON, should cast to double
      json['max_marks'] = 50;
      final m = GradeModel.fromJson(json);
      expect(m.marksObtained, 38.0);
      expect(m.maxMarks, 50.0);
    });

    test('percentage accepts integer JSON value', () {
      final json = _gradeJson();
      json['percentage'] = 76; // int
      final m = GradeModel.fromJson(json);
      expect(m.percentage, 76.0);
    });
  });
}
