class TestModel {
  final int id;
  final String title;
  final int teacherId;
  final int grade;
  final String subject;
  final String? sourceFileUrl;
  final String? answerKeyUrl;
  final String testType; // 'online' | 'offline'
  final List<Map<String, dynamic>>? questions;
  final double totalMarks;
  final int? timeLimitMinutes;
  final bool isPublished;
  final bool isGraded;
  final DateTime createdAt;
  final DateTime? expiresAt;

  const TestModel({
    required this.id,
    required this.title,
    required this.teacherId,
    required this.grade,
    required this.subject,
    this.sourceFileUrl,
    this.answerKeyUrl,
    required this.testType,
    this.questions,
    required this.totalMarks,
    this.timeLimitMinutes,
    required this.isPublished,
    this.isGraded = false,
    required this.createdAt,
    this.expiresAt,
  });

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  int get questionCount => questions?.length ?? 0;

  factory TestModel.fromJson(Map<String, dynamic> json) => TestModel(
        id: json['id'] as int,
        title: json['title'] as String,
        teacherId: json['teacher_id'] as int,
        grade: json['grade'] as int,
        subject: json['subject'] as String,
        sourceFileUrl: json['source_file_url'] as String?,
        answerKeyUrl: json['answer_key_url'] as String?,
        testType: json['test_type'] as String,
        questions: (json['questions'] as List<dynamic>?)
            ?.map((q) => q as Map<String, dynamic>)
            .toList(),
        totalMarks: (json['total_marks'] as num).toDouble(),
        timeLimitMinutes: json['time_limit_minutes'] as int?,
        isPublished: json['is_published'] as bool,
        isGraded: json['is_graded'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
        expiresAt: json['expires_at'] != null
            ? DateTime.parse(json['expires_at'] as String)
            : null,
      );
}

class TestSubmissionModel {
  final int id;
  final int testId;
  final int studentId;
  final Map<String, dynamic>? answers;
  final double? score;
  final DateTime submittedAt;
  final bool autoSubmitted;

  const TestSubmissionModel({
    required this.id,
    required this.testId,
    required this.studentId,
    this.answers,
    this.score,
    required this.submittedAt,
    required this.autoSubmitted,
  });

  factory TestSubmissionModel.fromJson(Map<String, dynamic> json) =>
      TestSubmissionModel(
        id: json['id'] as int,
        testId: json['test_id'] as int,
        studentId: json['student_id'] as int,
        answers: json['answers'] as Map<String, dynamic>?,
        score: (json['score'] as num?)?.toDouble(),
        submittedAt: DateTime.parse(json['submitted_at'] as String),
        autoSubmitted: json['auto_submitted'] as bool,
      );
}
