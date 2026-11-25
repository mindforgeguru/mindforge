import 'package:shared_preferences/shared_preferences.dart';

/// Set once the app has started on this install.
const freshInstallMarkerKey = 'install_seen_v1';

/// Signs out a reinstalled app (J-26).
///
/// iOS keeps Keychain items when an app is deleted, so a reinstall opened
/// straight into the last user's dashboard: deleting the app did not sign
/// anyone out of a shared school iPad or a family phone. SharedPreferences
/// *is* wiped on delete, so a missing marker means a fresh install, and the
/// Keychain left over from the old one is cleared.
///
/// The first launch after updating to a build with this check also has no
/// marker, so it signs out once. That only touches iOS, which had not shipped
/// to users when this was added. Returns true when [wipeSecureStorage] ran.
Future<bool> clearSecureStorageOnFreshInstall(
  SharedPreferences prefs,
  Future<void> Function() wipeSecureStorage,
) async {
  if (prefs.getBool(freshInstallMarkerKey) == true) return false;
  var wiped = false;
  try {
    await wipeSecureStorage();
    wiped = true;
  } catch (_) {
    // A Keychain error must never stop the app from starting.
  }
  await prefs.setBool(freshInstallMarkerKey, true);
  return wiped;
}
