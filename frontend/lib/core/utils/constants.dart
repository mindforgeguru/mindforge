/// Application-wide constants for MIND FORGE.
class AppConstants {
  AppConstants._();

  static const String appName = 'MIND FORGE';
  static const String tagline = 'AI Assisted Learning';

  /// Change this to your deployed backend URL in production.
  static const String apiBaseUrl = 'https://mindforge-production-4d7e.up.railway.app/api';
  static const String wsBaseUrl = 'wss://mindforge-production-4d7e.up.railway.app/ws';

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
    'English Language',
    'English Literature',
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
