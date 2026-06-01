/// Web implementation of the "confirm before leaving" guard.
///
/// Hooks the browser `beforeunload` event so that while a test is in progress,
/// closing the tab, refreshing, or navigating the browser away pops the native
/// "Leave site?" confirmation. (Browsers deliberately ignore custom text here
/// and show their own generic message — only the in-app PopScope dialog can
/// show our exact wording.)
///
/// The student's answers are autosaved to the server every few seconds and the
/// attempt is finalized server-side on the next touch, so leaving still results
/// in an auto-submit of whatever was answered — the prompt just gives them a
/// chance to stay.
library;

// This file is only ever compiled for the web target (selected via the
// conditional import in leave_guard.dart), where dart:html is the simplest
// way to hook beforeunload without adding a package:web dependency.
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

html.EventListener? _listener;

void enableLeaveConfirmation() {
  // Idempotent — don't stack multiple listeners.
  if (_listener != null) return;
  _listener = (html.Event e) {
    if (e is html.BeforeUnloadEvent) {
      // Setting returnValue (and preventDefault) is what triggers the native
      // confirmation dialog. The string is shown only by very old browsers;
      // modern ones display their own generic "Leave site?" message.
      e.preventDefault();
      e.returnValue =
          'Your test will be auto-submitted if you leave this page.';
    }
  };
  html.window.addEventListener('beforeunload', _listener);
}

void disableLeaveConfirmation() {
  if (_listener == null) return;
  html.window.removeEventListener('beforeunload', _listener);
  _listener = null;
}
