/// Application-wide constants for MIND FORGE.
class AppConstants {
  AppConstants._();

  static const String appName = 'MIND FORGE';
  static const String tagline = 'AI Assisted Learning';

  /// App version shown on the About/Licenses page. Keep in sync with the
  /// `version:` field in pubspec.yaml (without the build number).
  static const String appVersion = '1.0.0';

  /// Copyright line shown in the app's About section. Update the year range
  /// as needed.
  static const String copyright = '© 2026 MIND FORGE. All rights reserved.';

  // Local-dev backend toggle. Defaults to FALSE so any plain `flutter build`
  // (web/apk/ipa) targets production — it's impossible to ship a build that
  // points at 127.0.0.1 by accident. For local development, run against the
  // Docker backend with:  flutter run --dart-define=LOCAL_DEV=true
  static const bool _local =
      bool.fromEnvironment('LOCAL_DEV', defaultValue: false);

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
