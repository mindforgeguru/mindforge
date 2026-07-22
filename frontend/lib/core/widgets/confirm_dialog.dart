import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A generic "double-check before you submit" dialog. Used by the admin setup
/// tasks so the admin can review the details they entered before they're saved
/// (both on first submit and on later edits). Returns true only when the admin
/// taps the confirm action.
///
/// [message] should recap the values being submitted so the admin can verify
/// them at a glance.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'OK',
  String cancelLabel = 'Cancel',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    useRootNavigator: false,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed == true;
}
