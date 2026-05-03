// Models for the XP & Level system.
//
// Mirrors backend schemas in backend/app/schemas/xp.py. Field names follow
// the Dart camelCase convention; JSON keys stay snake_case.

class XPTransactionModel {
  final int id;
  final int studentId;
  final int amount;
  final String reason;        // ATTENDANCE, HOMEWORK_ON_TIME, ...
  final String? referenceId;
  final String? description;
  final DateTime createdAt;

  const XPTransactionModel({
    required this.id,
    required this.studentId,
    required this.amount,
    required this.reason,
    this.referenceId,
    this.description,
    required this.createdAt,
  });

  factory XPTransactionModel.fromJson(Map<String, dynamic> json) =>
      XPTransactionModel(
        id: json['id'] as int,
        studentId: json['student_id'] as int,
        amount: json['amount'] as int,
        reason: json['reason'] as String,
        referenceId: json['reference_id'] as String?,
        description: json['description'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class StudentXPDetails {
  final int studentId;
  final int totalXp;
  final int currentLevel;
  final String currentLevelTitle;
  final int xpIntoLevel;
  final int? xpForNextLevel;
  final int? nextLevelXpRequired;
  final int? nextLevel;
  final String? nextLevelTitle;
  // Student's chosen cosmetic theme. Null → app default theme.
  final String? selectedTheme;
  final List<XPTransactionModel> recentTransactions;

  const StudentXPDetails({
    required this.studentId,
    required this.totalXp,
    required this.currentLevel,
    required this.currentLevelTitle,
    required this.xpIntoLevel,
    this.xpForNextLevel,
    this.nextLevelXpRequired,
    this.nextLevel,
    this.nextLevelTitle,
    this.selectedTheme,
    required this.recentTransactions,
  });

  /// Fraction in [0,1] of the way through the current level. Returns 1.0
  /// at the level cap (no next level).
  double get progressToNextLevel {
    final needed = xpForNextLevel;
    if (needed == null || needed <= 0) return 1.0;
    return (xpIntoLevel / needed).clamp(0.0, 1.0);
  }

  factory StudentXPDetails.fromJson(Map<String, dynamic> json) =>
      StudentXPDetails(
        studentId: json['student_id'] as int,
        totalXp: json['total_xp'] as int,
        currentLevel: json['current_level'] as int,
        currentLevelTitle: json['current_level_title'] as String,
        xpIntoLevel: json['xp_into_level'] as int,
        xpForNextLevel: json['xp_for_next_level'] as int?,
        nextLevelXpRequired: json['next_level_xp_required'] as int?,
        nextLevel: json['next_level'] as int?,
        nextLevelTitle: json['next_level_title'] as String?,
        selectedTheme: json['selected_theme'] as String?,
        recentTransactions: ((json['recent_transactions'] as List?) ?? const [])
            .map((e) => XPTransactionModel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Catalogue entry for a single cosmetic theme. Frontend resolves
/// `themeId` → `BrandPalette` via `BrandPalettes.byId`.
class ThemeInfo {
  final String themeId;
  final int unlockLevel;
  final bool unlocked;
  final bool selected;

  const ThemeInfo({
    required this.themeId,
    required this.unlockLevel,
    required this.unlocked,
    required this.selected,
  });

  factory ThemeInfo.fromJson(Map<String, dynamic> json) => ThemeInfo(
        themeId: json['theme_id'] as String,
        unlockLevel: json['unlock_level'] as int,
        unlocked: json['unlocked'] as bool,
        selected: json['selected'] as bool,
      );
}

class ThemeListResponse {
  final String? selectedTheme;
  final List<ThemeInfo> themes;

  const ThemeListResponse({this.selectedTheme, required this.themes});

  factory ThemeListResponse.fromJson(Map<String, dynamic> json) =>
      ThemeListResponse(
        selectedTheme: json['selected_theme'] as String?,
        themes: ((json['themes'] as List?) ?? const [])
            .map((e) => ThemeInfo.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class LeaderboardEntry {
  final int rank;
  final int studentId;
  final String username;
  final String? profilePicUrl;
  final int grade;
  final int totalXp;
  final int currentLevel;

  const LeaderboardEntry({
    required this.rank,
    required this.studentId,
    required this.username,
    this.profilePicUrl,
    required this.grade,
    required this.totalXp,
    required this.currentLevel,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) =>
      LeaderboardEntry(
        rank: json['rank'] as int,
        studentId: json['student_id'] as int,
        username: json['username'] as String,
        profilePicUrl: json['profile_pic_url'] as String?,
        grade: json['grade'] as int,
        totalXp: json['total_xp'] as int,
        currentLevel: json['current_level'] as int,
      );
}

class LeaderboardResponse {
  final String scope;       // 'class' | 'grade' | 'school'
  final List<LeaderboardEntry> entries;

  const LeaderboardResponse({required this.scope, required this.entries});

  factory LeaderboardResponse.fromJson(Map<String, dynamic> json) =>
      LeaderboardResponse(
        scope: json['scope'] as String,
        entries: ((json['entries'] as List?) ?? const [])
            .map((e) => LeaderboardEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class LevelInfo {
  final int level;
  final int xpRequired;
  final String title;

  const LevelInfo({
    required this.level,
    required this.xpRequired,
    required this.title,
  });

  factory LevelInfo.fromJson(Map<String, dynamic> json) => LevelInfo(
        level: json['level'] as int,
        xpRequired: json['xp_required'] as int,
        title: json['title'] as String,
      );
}
