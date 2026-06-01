/// Confirm-before-leaving guard for the test attempt screen.
///
/// Resolves to the web implementation (browser `beforeunload`) when compiled
/// for web, and to a no-op stub everywhere else. Import this file; the right
/// implementation is selected at compile time.
library;

export 'leave_guard_stub.dart'
    if (dart.library.html) 'leave_guard_web.dart';
