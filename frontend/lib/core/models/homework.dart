class HomeworkModel {
  final int id;
  final int teacherId;
  final int grade;
  final String subject;
  final String title;
  final String? description;
  final String homeworkType; // 'online_test' | 'written'
  final int? testId;
  final DateTime? dueDate;
  final DateTime createdAt;
  // True once every roster student has a recorded completion status — i.e. the
  // teacher review is finished. False means it still needs reviewing.
  final bool reviewComplete;

  const HomeworkModel({
    required this.id,
    required this.teacherId,
    required this.grade,
    required this.subject,
    required this.title,
    this.description,
    required this.homeworkType,
    this.testId,
    this.dueDate,
    required this.createdAt,
    this.reviewComplete = false,
  });

  bool get isOnlineTest => homeworkType == 'online_test';

  factory HomeworkModel.fromJson(Map<String, dynamic> json) => HomeworkModel(
        id: json['id'] as int,
        teacherId: json['teacher_id'] as int,
        grade: json['grade'] as int,
        subject: json['subject'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        homeworkType: json['homework_type'] as String,
        testId: json['test_id'] as int?,
        dueDate: json['due_date'] != null
            ? DateTime.parse(json['due_date'] as String)
            : null,
        createdAt: DateTime.parse(json['created_at'] as String),
        reviewComplete: json['review_complete'] as bool? ?? false,
      );
}

/// Teacher-facing row in the homework-completion screen: a student plus
/// whether they've completed this homework. `wasAbsent` means the student
/// has at least one absent attendance row on the homework's assigned date —
/// the teacher screen renders these as locked Incomplete.
class HomeworkCompletionDetail {
  final int studentId;
  final String username;
  final bool completed;
  final DateTime? markedAt;
  final bool wasAbsent;

  const HomeworkCompletionDetail({
    required this.studentId,
    required this.username,
    required this.completed,
    this.markedAt,
    this.wasAbsent = false,
  });

  factory HomeworkCompletionDetail.fromJson(Map<String, dynamic> json) =>
      HomeworkCompletionDetail(
        studentId: json['student_id'] as int,
        username: json['username'] as String,
        completed: json['completed'] as bool,
        markedAt: json['marked_at'] != null
            ? DateTime.parse(json['marked_at'] as String)
            : null,
        wasAbsent: json['was_absent'] as bool? ?? false,
      );
}

/// Wrapped server response: per-student rows + attendance metadata so
/// the teacher screen can render the "mark attendance first" warning
/// without a second round trip.
class HomeworkCompletionsResponse {
  final String attendanceDate; // YYYY-MM-DD
  final bool attendanceRecorded;
  final List<HomeworkCompletionDetail> students;

  const HomeworkCompletionsResponse({
    required this.attendanceDate,
    required this.attendanceRecorded,
    required this.students,
  });

  factory HomeworkCompletionsResponse.fromJson(Map<String, dynamic> json) =>
      HomeworkCompletionsResponse(
        attendanceDate: json['attendance_date'] as String,
        attendanceRecorded: json['attendance_recorded'] as bool,
        students: (json['students'] as List<dynamic>)
            .map((e) =>
                HomeworkCompletionDetail.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Student/parent-facing row: a homework_id and whether it was completed.
/// Absence of an entry for a given homework_id means the teacher has not
/// recorded a status yet — render as "pending" on the client.
class StudentHomeworkCompletion {
  final int homeworkId;
  final bool completed;
  final DateTime? markedAt;

  const StudentHomeworkCompletion({
    required this.homeworkId,
    required this.completed,
    this.markedAt,
  });

  factory StudentHomeworkCompletion.fromJson(Map<String, dynamic> json) =>
      StudentHomeworkCompletion(
        homeworkId: json['homework_id'] as int,
        completed: json['completed'] as bool,
        markedAt: json['marked_at'] != null
            ? DateTime.parse(json['marked_at'] as String)
            : null,
      );
}

class BroadcastModel {
  final int id;
  final int senderId;
  final String senderUsername;
  final String title;
  final String message;
  final String targetType; // 'all' | 'grade'
  final int? targetGrade;
  final DateTime createdAt;

  const BroadcastModel({
    required this.id,
    required this.senderId,
    required this.senderUsername,
    required this.title,
    required this.message,
    required this.targetType,
    this.targetGrade,
    required this.createdAt,
  });

  factory BroadcastModel.fromJson(Map<String, dynamic> json) => BroadcastModel(
        id: json['id'] as int,
        senderId: json['sender_id'] as int,
        senderUsername: json['sender_username'] as String,
        title: json['title'] as String,
        message: json['message'] as String,
        targetType: json['target_type'] as String,
        targetGrade: json['target_grade'] as int?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
