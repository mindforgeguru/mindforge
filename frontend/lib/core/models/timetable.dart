class TimetableSlotModel {
  final int id;
  final int grade;
  final String slotDate;   // "YYYY-MM-DD" — specific calendar date
  final int periodNumber;
  final String? subject;
  final int? teacherId;
  final String? teacherUsername;
  final String? startTime;
  final String? endTime;
  final bool isHoliday;
  final String? comment;

  const TimetableSlotModel({
    required this.id,
    required this.grade,
    required this.slotDate,
    required this.periodNumber,
    this.subject,
    this.teacherId,
    this.teacherUsername,
    this.startTime,
    this.endTime,
    required this.isHoliday,
    this.comment,
  });

  factory TimetableSlotModel.fromJson(Map<String, dynamic> json) =>
      TimetableSlotModel(
        id: json['id'] as int,
        grade: json['grade'] as int,
        slotDate: json['slot_date'] as String,
        periodNumber: json['period_number'] as int,
        subject: json['subject'] as String?,
        teacherId: json['teacher_id'] as int?,
        teacherUsername: json['teacher_username'] as String?,
        startTime: json['start_time'] as String?,
        endTime: json['end_time'] as String?,
        isHoliday: json['is_holiday'] as bool,
        comment: json['comment'] as String?,
      );
}

class TimetableConfigModel {
  final int id;
  final int periodsPerDay;
  final bool enableWeekends;
  final List<dynamic>? periodTimes;
  final int? createdByAdminId;

  const TimetableConfigModel({
    required this.id,
    required this.periodsPerDay,
    required this.enableWeekends,
    this.periodTimes,
    this.createdByAdminId,
  });

  factory TimetableConfigModel.fromJson(Map<String, dynamic> json) =>
      TimetableConfigModel(
        id: json['id'] as int,
        periodsPerDay: json['periods_per_day'] as int,
        enableWeekends: json['enable_weekends'] as bool,
        periodTimes: json['period_times'] as List<dynamic>?,
        createdByAdminId: json['created_by_admin_id'] as int?,
      );
}
