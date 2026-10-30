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
        startTime: _hhmm(json['start_time'] as String?),
        endTime: _hhmm(json['end_time'] as String?),
        isHoliday: json['is_holiday'] as bool,
        comment: json['comment'] as String?,
      );

  /// This slot as the editor loaded it, sent with a save so the server can
  /// refuse it if someone else changed the period meanwhile (J-21 / #39).
  /// Pass null for a period that was empty.
  static Map<String, dynamic> snapshotOf(TimetableSlotModel? slot) =>
      slot == null
          ? const {'exists': false}
          : {
              'exists': true,
              'subject': slot.subject,
              'teacher_id': slot.teacherId,
              'is_holiday': slot.isHoliday,
              'comment': slot.comment,
            };

  /// The API sends Postgres TIME values as "09:00:00"; every screen shows
  /// them as-is, so the seconds read as noise and truncated the period
  /// chips ("09:00:00…", #6). Keep "HH:MM".
  static String? _hhmm(String? t) =>
      t != null && t.length > 5 && t[2] == ':' ? t.substring(0, 5) : t;
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
