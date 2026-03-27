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
