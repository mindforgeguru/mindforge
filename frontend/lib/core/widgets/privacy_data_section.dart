import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../utils/constants.dart';
import '../../features/auth/providers/auth_provider.dart';

/// Drop-in "Privacy & Data" section for the Profile screens of every
/// non-admin role. Provides:
///  • Privacy Policy link (hidden when AppConstants.privacyPolicyUrl is empty)
///  • "Delete my account" with type-to-confirm dialog
class PrivacyDataSection extends ConsumerWidget {
  const PrivacyDataSection({super.key});

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
        ListTile(
          leading: const Icon(Icons.delete_forever_outlined, color: Colors.red),
          title: const Text('Delete my account',
              style: TextStyle(color: Colors.red)),
          onTap: () => _confirmDelete(context, ref),
        ),
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
      ),
    );
    controller.dispose();

    if (confirmed != true) return;

    try {
      await ref.read(apiClientProvider).deleteMyAccount();
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
  const _DeleteConfirmDialog({required this.username, required this.controller});

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
