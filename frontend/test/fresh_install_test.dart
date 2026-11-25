import 'package:flutter_test/flutter_test.dart';
import 'package:mindforge/core/utils/fresh_install.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<(bool, int)> run(Map<String, Object> stored) async {
    SharedPreferences.setMockInitialValues(stored);
    final prefs = await SharedPreferences.getInstance();
    var wipes = 0;
    final wiped = await clearSecureStorageOnFreshInstall(
        prefs, () async => wipes++);
    expect(prefs.getBool(freshInstallMarkerKey), isTrue);
    return (wiped, wipes);
  }

  test('a fresh install (no preferences) clears the leftover Keychain',
      () async {
    expect(await run({}), (true, 1));
  });

  test('later launches leave storage alone', () async {
    expect(await run({freshInstallMarkerKey: true}), (false, 0));
  });

  test('a Keychain error does not stop start-up', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final wiped = await clearSecureStorageOnFreshInstall(
        prefs, () async => throw Exception('keychain locked'));
    expect(wiped, isFalse);
    expect(prefs.getBool(freshInstallMarkerKey), isTrue);
  });
}
