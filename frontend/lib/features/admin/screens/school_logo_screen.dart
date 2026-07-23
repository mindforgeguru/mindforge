import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers/school_logo_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/constants.dart';
import '../../../core/utils/image_pick.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../providers/admin_provider.dart';
import '../widgets/admin_scaffold.dart';

/// Setup task 5: upload the school's logo. Once set, it is shown app-wide above
/// the MindForge logo (see the school badge in the side nav).
class AdminSchoolLogoScreen extends ConsumerStatefulWidget {
  const AdminSchoolLogoScreen({super.key});

  @override
  ConsumerState<AdminSchoolLogoScreen> createState() =>
      _AdminSchoolLogoScreenState();
}

class _AdminSchoolLogoScreenState extends ConsumerState<AdminSchoolLogoScreen> {
  bool _uploading = false;

  Future<void> _pickAndUpload() async {
    final picker = ImagePicker();
    final picked = await pickImageBytes(picker, imageQuality: 90);
    if (picked == null || !mounted) return;

    final ok = await showConfirmDialog(
      context,
      title: 'Set school logo?',
      message: 'This logo will be shown across the app above the MindForge '
          'logo. Is this the image you want to use?',
      confirmLabel: 'Upload',
    );
    if (!ok || !mounted) return;

    setState(() => _uploading = true);
    try {
      await ref
          .read(apiClientProvider)
          .uploadSchoolLogo(picked.bytes, picked.name);
      ref.invalidate(currentSchoolLogoProvider);
      ref.invalidate(adminSetupStatusProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('School logo saved!'),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Upload failed: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final logoAsync = ref.watch(currentSchoolLogoProvider);

    return AdminScaffold(
      showMobileBottomNav: false,
      appBar: AppBar(
        title: const Text('School Logo'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(RouteNames.adminDashboard),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.divider),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: logoAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, __) => const Icon(Icons.broken_image_outlined,
                        size: 48, color: AppColors.textMuted),
                    data: (url) => url == null
                        ? const Icon(Icons.image_outlined,
                            size: 56, color: AppColors.textMuted)
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: url,
                              fit: BoxFit.contain,
                              errorWidget: (_, __, ___) => const Icon(
                                  Icons.broken_image_outlined,
                                  size: 48,
                                  color: AppColors.textMuted),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  logoAsync.valueOrNull == null
                      ? 'No logo uploaded yet.'
                      : 'This logo appears above the MindForge logo everywhere.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _uploading ? null : _pickAndUpload,
                    icon: _uploading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.upload_outlined),
                    label: Text(_uploading
                        ? 'Uploading...'
                        : (logoAsync.valueOrNull == null
                            ? 'Upload Logo'
                            : 'Replace Logo')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
