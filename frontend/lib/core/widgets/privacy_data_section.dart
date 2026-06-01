import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../utils/constants.dart';
import '../../features/auth/providers/auth_provider.dart';
import 'app_about_section.dart';

/// Drop-in "Privacy & Data" section for the Profile screens of every
/// non-admin role. Provides:
///  • Privacy Policy link (hidden when AppConstants.privacyPolicyUrl is empty)
///  • Optional "Delete my account" with type-to-confirm dialog
///
/// As of 2026-05-14 the deletion policy is:
///   - Admins: no self-delete (excluded from admin profile screen).
///   - Students: no self-delete — use `showDeleteButton: false` on the
///     student profile. Only the parent or an admin can delete a student.
///   - Parents: self-delete cascades to the one linked student account on
///     the server side. Show the cascade warning by passing
///     `deleteWarning: PrivacyDataSection.parentCascadeWarning`.
class PrivacyDataSection extends ConsumerWidget {
  /// When false, the "Delete my account" tile is hidden. Used on the student
  /// profile because students cannot self-delete server-side either.
  final bool showDeleteButton;

  /// Extra warning text shown above the "type to confirm" prompt. Used by
  /// the parent profile to disclose the cascade-to-child deletion.
  final String? deleteWarning;

  const PrivacyDataSection({
    super.key,
    this.showDeleteButton = true,
    this.deleteWarning,
  });

  /// Standard warning string for the parent's delete dialog.
  static const String parentCascadeWarning =
      'Your child\'s student account is linked to this parent account. '
      'Deleting this account will also permanently delete the linked '
      'student account. This cannot be undone.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasUrl = AppConstants.privacyPolicyUrl.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            'Privacy & Data',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
        if (hasUrl)
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy Policy'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () async {
              final uri = Uri.parse(AppConstants.privacyPolicyUrl);
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
          ),
        if (showDeleteButton)
          ListTile(
            leading: const Icon(Icons.delete_forever_outlined, color: Colors.red),
            title: const Text('Delete my account',
                style: TextStyle(color: Colors.red)),
            onTap: () => _confirmDelete(context, ref),
          ),
        const AppAboutSection(),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final auth = ref.read(authProvider);
    final username = auth.username ?? '';
    if (username.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DeleteConfirmDialog(
        username: username,
        controller: controller,
        warning: deleteWarning,
      ),
    );
    controller.dispose();

    if (confirmed != true) return;

    try {
      await ref.read(apiClientProvider).deleteMyAccount();
    } on DioMultiChildException catch (e) {
      // Server rejected because the parent has more than one linked student.
      messenger.showSnackBar(
        SnackBar(content: Text(e.message)),
      );
      return;
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not delete account. Try again.')),
      );
      return;
    }
    // Clear local state — logout() handles tokens, storage, ws, FCM.
    await ref.read(authProvider.notifier).logout();
  }
}

class _DeleteConfirmDialog extends StatefulWidget {
  final String username;
  final TextEditingController controller;
  final String? warning;
  const _DeleteConfirmDialog({
    required this.username,
    required this.controller,
    this.warning,
  });

  @override
  State<_DeleteConfirmDialog> createState() => _DeleteConfirmDialogState();
}

class _DeleteConfirmDialogState extends State<_DeleteConfirmDialog> {
  bool _matches = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete account?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.warning != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.warning!,
                      style: const TextStyle(color: Colors.red, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            'This permanently disables your "${widget.username}" account. '
            'Your data will be removed from the app — historical class '
            'records may remain on the school\'s admin side.\n\n'
            'Type your username below to confirm.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: widget.controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: widget.username,
              border: const OutlineInputBorder(),
            ),
            onChanged: (v) =>
                setState(() => _matches = v.trim() == widget.username),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: _matches ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Delete'),
        ),
      ],
    );
  }
}
