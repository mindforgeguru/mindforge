class AttendanceModel {
  final int id;
  final int studentId;
  final int? teacherId;
  final int grade;
  final int period;
  final DateTime date;
  final String status; // 'present' | 'absent'
  final DateTime createdAt;

  const AttendanceModel({
    required this.id,
    required this.studentId,
    this.teacherId,
    required this.grade,
    required this.period,
    required this.date,
    required this.status,
    required this.createdAt,
  });

  bool get isPresent => status == 'present';

  factory AttendanceModel.fromJson(Map<String, dynamic> json) =>
      AttendanceModel(
        id: json['id'] as int,
        studentId: json['student_id'] as int,
        teacherId: json['teacher_id'] as int?,
        grade: json['grade'] as int,
        period: json['period'] as int,
        date: DateTime.parse(json['date'] as String),
        status: json['status'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class AttendanceSummaryModel {
  final int studentId;
  final int totalClasses;
  final int presentCount;
  final int absentCount;
  final double attendancePercentage;

  const AttendanceSummaryModel({
    required this.studentId,
    required this.totalClasses,
    required this.presentCount,
    required this.absentCount,
    required this.attendancePercentage,
  });

  factory AttendanceSummaryModel.fromJson(Map<String, dynamic> json) =>
      AttendanceSummaryModel(
        studentId: json['student_id'] as int,
        totalClasses: json['total_classes'] as int,
        presentCount: json['present_count'] as int,
        absentCount: json['absent_count'] as int,
        attendancePercentage:
            (json['attendance_percentage'] as num).toDouble(),
      );
}
