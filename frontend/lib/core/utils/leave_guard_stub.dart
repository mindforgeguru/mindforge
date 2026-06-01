/// Non-web stub for the "confirm before leaving" guard.
///
/// On mobile/desktop there is no browser tab to close or refresh, so these are
/// no-ops. The in-app back button is handled separately by PopScope in the test
/// attempt screen.
library;

/// Ask the browser to confirm before the user closes the tab, refreshes, or
/// navigates away. No-op off the web.
void enableLeaveConfirmation() {}

/// Remove the leave confirmation. No-op off the web.
void disableLeaveConfirmation() {}
