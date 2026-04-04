class UserModel {
  final int id;
  final String username;
  final String role;
  final bool isActive;
  final bool isApproved;
  final DateTime createdAt;
  final DateTime? deletedAt;
  final int? grade;                         // students only
  final int? parentUserId;                  // students only
  final String? parentUsername;             // students only
  final String? studentUsername;            // parents only
  final List<String>? teachableSubjects;    // teachers only
  final List<String>? additionalSubjects;   // students only

  const UserModel({
    required this.id,
    required this.username,
    required this.role,
    required this.isActive,
    required this.isApproved,
    required this.createdAt,
    this.deletedAt,
    this.grade,
    this.parentUserId,
    this.parentUsername,
    this.studentUsername,
    this.teachableSubjects,
    this.additionalSubjects,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'] as int,
        username: json['username'] as String,
        role: json['role'] as String,
        isActive: json['is_active'] as bool,
        isApproved: json['is_approved'] as bool,
        createdAt: DateTime.parse(json['created_at'] as String),
        deletedAt: json['deleted_at'] != null
            ? DateTime.parse(json['deleted_at'] as String)
            : null,
        grade: json['grade'] as int?,
        parentUserId: json['parent_user_id'] as int?,
        parentUsername: json['parent_username'] as String?,
        studentUsername: json['student_username'] as String?,
        teachableSubjects: (json['teachable_subjects'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList(),
        additionalSubjects: (json['additional_subjects'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'role': role,
        'is_active': isActive,
        'is_approved': isApproved,
        'created_at': createdAt.toIso8601String(),
        'deleted_at': deletedAt?.toIso8601String(),
        'grade': grade,
        'parent_user_id': parentUserId,
      };
}

class StudentProfileModel {
  final int id;
  final int userId;
  final int grade;
  final String? profilePicUrl;
  final int? parentUserId;

  const StudentProfileModel({
    required this.id,
    required this.userId,
    required this.grade,
    this.profilePicUrl,
    this.parentUserId,
  });

  factory StudentProfileModel.fromJson(Map<String, dynamic> json) =>
      StudentProfileModel(
        id: json['id'] as int,
        userId: json['user_id'] as int,
        grade: json['grade'] as int,
        profilePicUrl: json['profile_pic_url'] as String?,
        parentUserId: json['parent_user_id'] as int?,
      );
}
