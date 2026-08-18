import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindforge/core/security/screen_security.dart';

/// FLAG_SECURE is a *window* flag on Android — one switch for the whole app, not
/// per-widget. So the Dart side has to track how many sensitive screens are
/// currently on top and only clear the flag when the last one leaves. A plain
/// bool gets this wrong the moment one secure screen opens another: popping the
/// inner one would unsecure the outer one while it is still visible.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.mindforge.mindforge/screen_security');
  late List<bool> calls;

  void mockChannel({bool throwMissingPlugin = false}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (throwMissingPlugin) {
        throw MissingPluginException('no impl');
      }
      if (call.method == 'setSecure') {
        calls.add(call.arguments['enabled'] as bool);
      }
      return null;
    });
  }

  setUp(() {
    calls = <bool>[];
    ScreenSecurity.debugReset();
    mockChannel();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('single screen', () {
    test('acquire turns the flag on, release turns it off', () async {
      await ScreenSecurity.acquire();
      expect(calls, [true]);
      await ScreenSecurity.release();
      expect(calls, [true, false]);
    });
  });

  group('nested screens', () {
    test('the flag stays on until the last screen leaves', () async {
      await ScreenSecurity.acquire(); // fees
      await ScreenSecurity.acquire(); // grades opened on top
      expect(calls, [true], reason: 'should not re-issue while already secured');

      await ScreenSecurity.release(); // grades popped, fees still visible
      expect(calls, [true],
          reason: 'clearing here would expose the fee screen still on screen');

      await ScreenSecurity.release(); // fees popped
      expect(calls, [true, false]);
    });
  });

  _wrapperTests();

  group('robustness', () {
    test('an unbalanced release cannot drive the count negative', () async {
      // A screen disposed twice, or released without acquiring, must not leave
      // the counter below zero — the next acquire would then silently no-op and
      // the screen would render unprotected.
      await ScreenSecurity.release();
      await ScreenSecurity.release();
      calls.clear();

      await ScreenSecurity.acquire();
      expect(calls, [true]);
    });

    test('a platform without the channel is a no-op, not a crash', () async {
      // Web and iOS have no handler registered. A sensitive screen must still
      // render rather than throwing on the way in.
      mockChannel(throwMissingPlugin: true);
      await expectLater(ScreenSecurity.acquire(), completes);
      await expectLater(ScreenSecurity.release(), completes);
    });
  });
}

/// The wrapper exists for stateless screens; it must tie the flag to its own
/// mount/unmount exactly as the mixin does.
void _wrapperTests() {
  const channel = MethodChannel('com.mindforge.mindforge/screen_security');

  testWidgets('SecureScreen secures while mounted and releases when gone',
      (tester) async {
    final calls = <bool>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setSecure') {
        calls.add(call.arguments['enabled'] as bool);
      }
      return null;
    });
    ScreenSecurity.debugReset();

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SecureScreen(child: Text('fees')),
      ),
    );
    await tester.pump();
    expect(find.text('fees'), findsOneWidget,
        reason: 'wrapper must render its child unchanged');
    expect(calls, [true]);

    // Replace the tree — the screen is gone.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(calls, [true, false]);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}
