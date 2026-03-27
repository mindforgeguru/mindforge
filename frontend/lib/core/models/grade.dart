class GradeModel {
  final int id;
  final int studentId;
  final int? teacherId;
  final String subject;
  final String chapter;
  final int? testId;
  final double marksObtained;
  final double maxMarks;
  final double percentage;
  final String gradeType; // 'online' | 'offline' | 'manual'
  final DateTime createdAt;

  const GradeModel({
    required this.id,
    required this.studentId,
    this.teacherId,
    required this.subject,
    required this.chapter,
    this.testId,
    required this.marksObtained,
    required this.maxMarks,
    required this.percentage,
    required this.gradeType,
    required this.createdAt,
  });

  factory GradeModel.fromJson(Map<String, dynamic> json) => GradeModel(
        id: json['id'] as int,
        studentId: json['student_id'] as int,
        teacherId: json['teacher_id'] as int?,
        subject: json['subject'] as String,
        chapter: json['chapter'] as String,
        testId: json['test_id'] as int?,
        marksObtained: (json['marks_obtained'] as num).toDouble(),
        maxMarks: (json['max_marks'] as num).toDouble(),
        percentage: (json['percentage'] as num).toDouble(),
        gradeType: json['grade_type'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
