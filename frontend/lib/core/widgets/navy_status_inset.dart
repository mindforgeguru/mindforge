import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Navy band behind the status bar over the content area of the wide
/// (sidebar) layouts, so the status bar's white icons stay readable.
///
/// On an iPad the sidebar is navy but the content area is light, and the
/// dashboards cap their navy header at 600 px: the right half of the status
/// bar (Wi-Fi, battery) was white on light grey. Nothing on web, where there
/// is no top inset.
class NavyStatusInset extends StatelessWidget {
  final Widget child;
  const NavyStatusInset({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    if (top == 0) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(height: top, color: AppColors.primary),
        Expanded(
          child: MediaQuery.removePadding(
              context: context, removeTop: true, child: child),
        ),
      ],
    );
  }
}
