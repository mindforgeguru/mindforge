import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindforge/core/api/api_client.dart';
import 'package:mindforge/core/theme/app_theme.dart';
import 'package:mindforge/features/owner/screens/owner_dashboard_screen.dart';

// The owner's Add School / Add Admin dialogs used to close first and call the
// server afterwards, so a rejection (a duplicate name, a taken username) threw
// away everything typed. They now submit in place and stay open on failure.

DioException _conflict(String detail) {
  final req = RequestOptions(path: '/owner/schools');
  return DioException(
    requestOptions: req,
    response: Response(requestOptions: req, statusCode: 409, data: {'detail': detail}),
    type: DioExceptionType.badResponse,
  );
}

class _FakeApiClient extends Fake implements ApiClient {
  @override
  void Function()? onUnauthorized;

  Object? createSchoolError;
  Object? createAdminError;
  int createSchoolCalls = 0;
  int createAdminCalls = 0;

  @override
  Future<List<Map<String, dynamic>>> getOwnerSchools() async => [
        {
          'id': 7,
          'name': 'Greenwood Academy',
          'slug': 'greenwood-academy',
          'is_active': true,
          'admin_count': 1,
          'teacher_count': 0,
          'student_count': 0,
          'parent_count': 0,
        },
      ];

  @override
  Future<Map<String, dynamic>> createSchool({
    required String name,
    String? slug,
    String? contactEmail,
    String? contactPhone,
    String? address,
  }) async {
    createSchoolCalls++;
    if (createSchoolError != null) throw createSchoolError!;
    return {'id': 8, 'name': name};
  }

  @override
  Future<Map<String, dynamic>> createSchoolAdmin(
      int schoolId, String username, String mpin) async {
    createAdminCalls++;
    if (createAdminError != null) throw createAdminError!;
    return {'id': 99, 'username': username};
  }
}

Future<_FakeApiClient> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final api = _FakeApiClient();
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api)],
    child: MaterialApp(theme: AppTheme.lightTheme, home: const OwnerDashboardScreen()),
  ));
  await tester.pumpAndSettle();
  return api;
}

Finder _inDialog(Finder f) => find.descendant(of: find.byType(AlertDialog), matching: f);

void main() {
  group('Add School', () {
    testWidgets('a server rejection keeps the dialog open with what was typed',
        (tester) async {
      final api = await _pump(tester);
      api.createSchoolError =
          _conflict("A school named 'Greenwood Academy' already exists. Choose a different name.");

      await tester.tap(find.text('Add School'));
      await tester.pumpAndSettle();
      await tester.enterText(_inDialog(find.byType(TextField)).at(0), 'Greenwood Academy');
      await tester.enterText(_inDialog(find.byType(TextField)).at(1), 'office@greenwood.test');
      await tester.tap(_inDialog(find.text('Create')));
      await tester.pumpAndSettle();

      expect(api.createSchoolCalls, 1);
      expect(find.byType(AlertDialog), findsOneWidget, reason: 'dialog must stay open');
      expect(_inDialog(find.textContaining('already exists')), findsOneWidget);
      expect(find.text('Greenwood Academy'), findsWidgets); // the typed name survives
      expect(find.text('office@greenwood.test'), findsOneWidget);
    });

    testWidgets('success closes the dialog', (tester) async {
      final api = await _pump(tester);
      await tester.tap(find.text('Add School'));
      await tester.pumpAndSettle();
      await tester.enterText(_inDialog(find.byType(TextField)).at(0), 'Riverdale High');
      await tester.tap(_inDialog(find.text('Create')));
      await tester.pumpAndSettle();

      expect(api.createSchoolCalls, 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('School created.'), findsOneWidget);
    });

    testWidgets('a missing name is caught in the dialog without calling the server',
        (tester) async {
      final api = await _pump(tester);
      await tester.tap(find.text('Add School'));
      await tester.pumpAndSettle();
      await tester.tap(_inDialog(find.text('Create')));
      await tester.pumpAndSettle();

      expect(api.createSchoolCalls, 0);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(_inDialog(find.text('School name is required.')), findsOneWidget);
    });
  });

  group('Add Admin', () {
    testWidgets('a taken username keeps the dialog open with what was typed',
        (tester) async {
      final api = await _pump(tester);
      api.createAdminError = _conflict('A user with this username already exists in this school.');

      await tester.tap(find.text('Add Admin'));
      await tester.pumpAndSettle();
      await tester.enterText(_inDialog(find.byType(TextField)).at(0), 'gw_admin');
      await tester.enterText(_inDialog(find.byType(TextField)).at(1), '583921');
      await tester.tap(_inDialog(find.text('Create')));
      await tester.pumpAndSettle();

      expect(api.createAdminCalls, 1);
      expect(find.byType(AlertDialog), findsOneWidget, reason: 'dialog must stay open');
      expect(_inDialog(find.textContaining('already exists')), findsOneWidget);
      expect(find.text('gw_admin'), findsOneWidget);
    });
  });
}
