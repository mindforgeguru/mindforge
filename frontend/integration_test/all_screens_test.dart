/// all_screens_test.dart
///
/// Navigates every screen for every role and asserts it renders without crash.
/// Run with: flutter test integration_test/all_screens_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:mindforge/main.dart' as app;

// ─── Credentials ─────────────────────────────────────────────────────────────
// Pass via --dart-define=ADMIN_MPIN=xxx / TEACHER_USER=xxx etc. if changed
// ignore: do_not_use_environment
const _adminMpin    = String.fromEnvironment('ADMIN_MPIN',    defaultValue: '300573');
// ignore: do_not_use_environment
const _teacherUser  = String.fromEnvironment('TEACHER_USER',  defaultValue: 'chinmay_sir');
// ignore: do_not_use_environment
const _teacherMpin  = String.fromEnvironment('TEACHER_MPIN',  defaultValue: '100898');
// ignore: do_not_use_environment
const _studentUser  = String.fromEnvironment('STUDENT_USER',  defaultValue: 'dummy8');
// ignore: do_not_use_environment
const _studentMpin  = String.fromEnvironment('STUDENT_MPIN',  defaultValue: '111111');
// ignore: do_not_use_environment
const _parentUser   = String.fromEnvironment('PARENT_USER',   defaultValue: 'dummy8_dad');
// ignore: do_not_use_environment
const _parentMpin   = String.fromEnvironment('PARENT_MPIN',   defaultValue: '111111');

const _admin   = ('admin',        _adminMpin);
const _teacher = (_teacherUser,   _teacherMpin);
const _student = (_studentUser,   _studentMpin);
const _parent  = (_parentUser,    _parentMpin);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ── Shared helpers ──────────────────────────────────────────────────────────

  Future<void> clearAuth() async {
    try {
      await const FlutterSecureStorage().deleteAll();
    } catch (_) {}
  }

  /// Advance past the splash screen (total animation ≈ 4.2 s).
  /// Also sets a phone-sized viewport so the PIN pad and login button are
  /// fully on-screen (932 = iPhone 14 Pro Max logical height).
  Future<void> passSplash(WidgetTester t) async {
    t.view.physicalSize = const Size(390.0, 932.0);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    for (int i = 0; i < 60; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.pumpAndSettle();
  }

  Future<void> tapDigit(WidgetTester t, String d) async {
    await t.tap(find.text(d).last);
    await t.pump(const Duration(milliseconds: 80));
  }

  Future<void> enterMpin(WidgetTester t, String mpin) async {
    for (final d in mpin.split('')) await tapDigit(t, d);
  }

  /// Login and wait up to 8 s for the network + navigation to settle.
  Future<void> login(WidgetTester t, (String, String) creds) async {
    await passSplash(t);
    await t.enterText(find.widgetWithText(TextField, 'Username'), creds.$1);
    await t.pump();
    await enterMpin(t, creds.$2);
    await t.tap(find.byType(ElevatedButton).first);
    for (int i = 0; i < 80; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.pumpAndSettle();
  }

  /// Tap a bottom-nav / quick-action label and wait for the screen to load.
  Future<void> goTo(WidgetTester t, String label) async {
    await t.tap(find.text(label).last);
    for (int i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.pumpAndSettle();
  }

  /// Navigate via a dashboard section header's "See all →" button.
  /// [anchorText] is the section title shown on the dashboard.
  Future<void> goViaSeeAll(WidgetTester t, String anchorText) async {
    // Drag the first VERTICAL Scrollable downward until the target section
    // header appears in the widget tree. Using iterative drags (rather than
    // scrollUntilVisible) avoids the problem where Scrollable.first resolves
    // to a nested horizontal timetable scroll instead of the main dashboard
    // scroll, which would leave off-screen slivers unbuilt.
    Finder verticalScrollable() {
      for (final s in t.widgetList<Scrollable>(find.byType(Scrollable))) {
        if (s.axisDirection == AxisDirection.down) return find.byWidget(s);
      }
      return find.byType(Scrollable).first;
    }

    for (int i = 0; i < 20; i++) {
      if (find.text(anchorText).evaluate().isNotEmpty) break;
      await t.drag(verticalScrollable(), const Offset(0, -500));
      await t.pump(const Duration(milliseconds: 120));
    }
    await t.pumpAndSettle();

    // The section title and its "See all →" button share the same Row
    final rows = find.ancestor(
      of: find.text(anchorText),
      matching: find.byType(Row),
    );
    final seeAll = find.descendant(
      of: rows.first,
      matching: find.text('See all →'),
    );
    await t.tap(seeAll, warnIfMissed: false);
    for (int i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.pumpAndSettle();
  }

  /// Tap the profile avatar (ClipOval) to navigate to the profile screen.
  Future<void> goToProfile(WidgetTester t) async {
    await t.tap(find.byType(ClipOval).first);
    for (int i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.pumpAndSettle();
  }

  /// Assert the current screen rendered (no blank/error page).
  void expectScreen(String name) {
    expect(find.byType(Scaffold), findsWidgets,
        reason: '$name screen should render a Scaffold');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ADMIN  (6 screens)
  // ══════════════════════════════════════════════════════════════════════════
  group('Admin', () {
    setUp(clearAuth);

    testWidgets('Dashboard', (t) async {
      app.main();
      await login(t, _admin);
      expectScreen('Admin Dashboard');
      // Key dashboard cards visible
      expect(find.text('Fees'), findsWidgets);
      expect(find.text('Timetable'), findsWidgets);
      expect(find.text('Users'), findsWidgets);
    });

    testWidgets('Users screen', (t) async {
      app.main();
      await login(t, _admin);
      await goTo(t, 'Users');
      expectScreen('Admin Users');
    });

    testWidgets('Fees screen', (t) async {
      app.main();
      await login(t, _admin);
      await goTo(t, 'Fees');
      expectScreen('Admin Fees');
    });

    testWidgets('Reports screen', (t) async {
      app.main();
      await login(t, _admin);
      await goTo(t, 'Reports');
      expectScreen('Admin Reports');
    });

    testWidgets('Timetable screen', (t) async {
      app.main();
      await login(t, _admin);
      await goTo(t, 'Timetable');
      expectScreen('Admin Timetable');
    });

    testWidgets('Profile screen', (t) async {
      app.main();
      await login(t, _admin);
      await goTo(t, 'Profile');
      expectScreen('Admin Profile');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // TEACHER  (7 screens)
  // bottom nav: Home | Grades | Tests | Attendance | Timetable
  // extras via dashboard "See all →": Broadcasts (Announcements), Homework (Recent Homework)
  // profile via avatar tap
  // ══════════════════════════════════════════════════════════════════════════
  group('Teacher', () {
    setUp(clearAuth);

    testWidgets('Dashboard', (t) async {
      app.main();
      await login(t, _teacher);
      expectScreen('Teacher Dashboard');
      expect(find.text('TEACHER'), findsWidgets);
    });

    testWidgets('Grades screen', (t) async {
      app.main();
      await login(t, _teacher);
      await goTo(t, 'Grades');
      expectScreen('Teacher Grades');
    });

    testWidgets('Tests screen', (t) async {
      app.main();
      await login(t, _teacher);
      await goTo(t, 'Tests');
      expectScreen('Teacher Tests');
    });

    testWidgets('Attendance screen', (t) async {
      app.main();
      await login(t, _teacher);
      await goTo(t, 'Attendance');
      expectScreen('Teacher Attendance');
    });

    testWidgets('Timetable screen', (t) async {
      app.main();
      await login(t, _teacher);
      await goTo(t, 'Timetable');
      expectScreen('Teacher Timetable');
    });

    testWidgets('Broadcasts screen', (t) async {
      app.main();
      await login(t, _teacher);
      // Broadcasts is reached via the Announcements section "See all →" on mobile
      await goViaSeeAll(t, 'Announcements');
      expectScreen('Teacher Broadcasts');
    });

    testWidgets('Homework screen', (t) async {
      app.main();
      await login(t, _teacher);
      // Homework is reached via the Recent Homework section "See all →" on mobile
      await goViaSeeAll(t, 'Recent Homework');
      expectScreen('Teacher Homework');
    });

    testWidgets('Profile screen', (t) async {
      app.main();
      await login(t, _teacher);
      await goToProfile(t);
      expectScreen('Teacher Profile');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // STUDENT  (7 screens)
  // bottom nav: Home | Grades | Tests | Attendance | Homework
  // extras via dashboard "See all →": Timetable, Broadcasts
  // profile via avatar tap
  // ══════════════════════════════════════════════════════════════════════════
  group('Student', () {
    setUp(clearAuth);

    testWidgets('Dashboard', (t) async {
      app.main();
      await login(t, _student);
      expectScreen('Student Dashboard');
      expect(find.text('STUDENT'), findsWidgets);
    });

    testWidgets('Grades screen', (t) async {
      app.main();
      await login(t, _student);
      await goTo(t, 'Grades');
      expectScreen('Student Grades');
    });

    testWidgets('Tests screen', (t) async {
      app.main();
      await login(t, _student);
      await goTo(t, 'Tests');
      expectScreen('Student Tests');
    });

    testWidgets('Attendance screen', (t) async {
      app.main();
      await login(t, _student);
      await goTo(t, 'Attendance');
      expectScreen('Student Attendance');
    });

    testWidgets('Timetable screen', (t) async {
      app.main();
      await login(t, _student);
      // Timetable is not in the student bottom nav; reach it via dashboard header
      await goViaSeeAll(t, "Today's Timetable");
      expectScreen('Student Timetable');
    });

    testWidgets('Homework screen', (t) async {
      app.main();
      await login(t, _student);
      // Homework is not in the student bottom nav; reach via dashboard section
      await goViaSeeAll(t, 'Recent Homework');
      expectScreen('Student Homework');
    });

    testWidgets('Broadcasts screen', (t) async {
      app.main();
      await login(t, _student);
      // Broadcasts is not in the student bottom nav; reach via Announcements section
      await goViaSeeAll(t, 'Announcements');
      expectScreen('Student Broadcasts');
    });

    testWidgets('Profile screen', (t) async {
      app.main();
      await login(t, _student);
      await goToProfile(t);
      expectScreen('Student Profile');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // PARENT  (6 screens)
  // bottom nav: Home | Attendance | Timetable | Grades | Fees
  // extras via dashboard "See all →": Homework (Recent Homework section)
  // profile via avatar tap
  // ══════════════════════════════════════════════════════════════════════════
  group('Parent', () {
    setUp(clearAuth);

    testWidgets('Dashboard', (t) async {
      app.main();
      await login(t, _parent);
      expectScreen('Parent Dashboard');
    });

    testWidgets('Attendance screen', (t) async {
      app.main();
      await login(t, _parent);
      await goTo(t, 'Attendance');
      expectScreen('Parent Attendance');
    });

    testWidgets('Timetable screen', (t) async {
      app.main();
      await login(t, _parent);
      await goTo(t, 'Timetable');
      expectScreen('Parent Timetable');
    });

    testWidgets('Grades screen', (t) async {
      app.main();
      await login(t, _parent);
      await goTo(t, 'Grades');
      expectScreen('Parent Grades');
    });

    testWidgets('Fees screen', (t) async {
      app.main();
      await login(t, _parent);
      await goTo(t, 'Fees');
      expectScreen('Parent Fees');
    });

    testWidgets('Homework screen', (t) async {
      app.main();
      await login(t, _parent);
      // Homework is not in the parent bottom nav; reach via Recent Homework section
      await goViaSeeAll(t, 'Recent Homework');
      expectScreen('Parent Homework');
    });

    testWidgets('Profile screen', (t) async {
      app.main();
      await login(t, _parent);
      await goToProfile(t);
      expectScreen('Parent Profile');
    });
  });
}
