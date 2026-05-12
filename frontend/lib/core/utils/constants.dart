/// Application-wide constants for MIND FORGE.
class AppConstants {
  AppConstants._();

  static const String appName = 'MIND FORGE';
  static const String tagline = 'AI Assisted Learning';

  // ⚠️  LOCAL DEV MODE — change back to false before building a release APK
  static const bool _local = true;

  static const String apiBaseUrl =
      _local ? 'http://127.0.0.1:8000/api' : 'https://api.mindforge.guru/api';
  static const String wsBaseUrl =
      _local ? 'ws://127.0.0.1:8000/ws' : 'wss://api.mindforge.guru/ws';

  /// Public privacy-policy URL. Required by Play Store + App Store. Leave
  /// empty to hide the in-app link until the policy is published.
  static const String privacyPolicyUrl = '';

  /// Supported grades (ICSE)
  static const List<int> grades = [8, 9, 10];

  /// ICSE subject list for grades 8–10
  static const List<String> subjects = [
    'Mathematics',
    'Physics',
    'Chemistry',
    'Biology',
    'History & Civics',
    'Geography',
    'English 1',
    'English 2',
    'Computer Applications',
    'Economics',
    'Environmental Science',
    'Artificial Intelligence',
  ];

  /// Days of the week labels (index 0 = Monday)
  static const List<String> daysOfWeek = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  static const String tokenStorageKey = 'mindforge_jwt_token';
  static const String refreshTokenStorageKey = 'mindforge_jwt_refresh_token';
  static const String roleStorageKey = 'mindforge_user_role';
  static const String userIdStorageKey = 'mindforge_user_id';
  static const String usernameStorageKey = 'mindforge_username';
  static const String profilePicUrlStorageKey = 'mindforge_profile_pic_url';
}

/// Named routes for GoRouter.
class RouteNames {
  RouteNames._();

  static const String splash = '/';
  static const String login = '/login';
  static const String teacherDashboard = '/teacher';
  static const String studentDashboard = '/student';
  static const String parentDashboard = '/parent';
  static const String adminDashboard = '/admin';
}
