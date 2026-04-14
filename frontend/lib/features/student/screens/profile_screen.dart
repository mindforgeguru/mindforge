import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/student_provider.dart';
import '../../../core/utils/responsive.dart';
import '../widgets/student_bottom_nav.dart';

class StudentProfileScreen extends ConsumerStatefulWidget {
  const StudentProfileScreen({super.key});

  @override
  ConsumerState<StudentProfileScreen> createState() =>
      _StudentProfileScreenState();
}

class _StudentProfileScreenState extends ConsumerState<StudentProfileScreen> {
  // MPIN form
  final _formKey = GlobalKey<FormState>();
  final _currentMpinCtrl = TextEditingController();
  final _newMpinCtrl = TextEditingController();
  final _confirmMpinCtrl = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _saving = false;

  @override
  void dispose() {
    _currentMpinCtrl.dispose();
    _newMpinCtrl.dispose();
    _confirmMpinCtrl.dispose();
    super.dispose();
  }

  Future<void> _changeProfilePic() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 80);
    if (xFile == null) return;
    final bytes = await xFile.readAsBytes();
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.uploadStudentPhoto(bytes, xFile.name);
      final url = res['profile_pic_url'] as String?;
      if (url != null) {
        await ref.read(authProvider.notifier).updateProfilePicUrl(url);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile picture updated!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload photo: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _saveMpin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.changeStudentMpin(
          _currentMpinCtrl.text, _newMpinCtrl.text);
      _currentMpinCtrl.clear();
      _newMpinCtrl.clear();
      _confirmMpinCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('MPIN changed successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      final msg = e.toString().contains('400')
          ? 'Current MPIN is incorrect.'
          : 'Failed to change MPIN. Try again.';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final gradeAsync = ref.watch(studentGradeProvider);
    final profileAsync = ref.watch(studentProfileProvider);
    final username = auth.username ?? 'Student';
    final avatarR = R.fluid(context, 36, min: 30, max: 44);

    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            R.sp(context, 16), 12, R.sp(context, 16), 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Avatar card ─────────────────────────────────────────────
            Container(
              decoration: mindForgeCardDecoration(),
              padding: EdgeInsets.symmetric(
                  horizontal: R.sp(context, 16), vertical: 14),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _changeProfilePic,
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        CircleAvatar(
                          radius: avatarR,
                          backgroundColor:
                              AppColors.secondary.withValues(alpha: 0.15),
                          backgroundImage: auth.profilePicUrl != null
                              ? CachedNetworkImageProvider(auth.profilePicUrl!)
                              : null,
                          child: auth.profilePicUrl == null
                              ? Text(
                                  username.isNotEmpty
                                      ? username[0].toUpperCase()
                                      : 'S',
                                  style: TextStyle(
                                    fontSize: R.fs(context, 26,
                                        min: 20, max: 30),
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.secondary,
                                  ),
                                )
                              : null,
                        ),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.camera_alt,
                              size: 13, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(username,
                      style: TextStyle(
                          fontSize: R.fs(context, 17, min: 14, max: 20),
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    children: [
                      const _Pill(label: 'STUDENT', color: AppColors.secondary),
                      gradeAsync.when(
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                        data: (g) => g == null
                            ? const SizedBox.shrink()
                            : _Pill(
                                label: 'Grade $g',
                                color: AppColors.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  profileAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (p) {
                      final parentName = p['parent_username'] as String?;
                      final linked = parentName != null;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: linked
                              ? AppColors.accent.withValues(alpha: 0.08)
                              : AppColors.textMuted.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: linked
                                ? AppColors.accent.withValues(alpha: 0.3)
                                : AppColors.divider,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.family_restroom,
                                size: 15,
                                color: linked
                                    ? AppColors.accent
                                    : AppColors.textMuted),
                            const SizedBox(width: 6),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Parent Account',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: linked
                                        ? AppColors.accent
                                        : AppColors.textMuted,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                Text(
                                  linked ? parentName : 'Not linked',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: linked
                                        ? AppColors.accent
                                        : AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  TextButton.icon(
                    onPressed: _changeProfilePic,
                    icon: const Icon(Icons.photo_camera_outlined, size: 14),
                    label: const Text('Change Photo',
                        style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Change MPIN ─────────────────────────────────────────────
            Container(
              decoration: mindForgeCardDecoration(),
              padding: const EdgeInsets.all(14),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.lock_outline,
                            size: 16, color: AppColors.primary),
                        SizedBox(width: 8),
                        Text('Change MPIN',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _MpinField(
                      controller: _currentMpinCtrl,
                      label: 'Current MPIN',
                      obscure: _obscureCurrent,
                      onToggle: () => setState(
                          () => _obscureCurrent = !_obscureCurrent),
                      validator: (v) {
                        if (v == null || v.length != 6) {
                          return 'Enter your 6-digit MPIN';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    _MpinField(
                      controller: _newMpinCtrl,
                      label: 'New MPIN',
                      obscure: _obscureNew,
                      onToggle: () =>
                          setState(() => _obscureNew = !_obscureNew),
                      validator: (v) {
                        if (v == null || v.length != 6) {
                          return 'Must be exactly 6 digits';
                        }
                        if (v == _currentMpinCtrl.text) {
                          return 'New MPIN must differ from current';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    _MpinField(
                      controller: _confirmMpinCtrl,
                      label: 'Confirm New MPIN',
                      obscure: _obscureConfirm,
                      onToggle: () => setState(
                          () => _obscureConfirm = !_obscureConfirm),
                      validator: (v) {
                        if (v != _newMpinCtrl.text) {
                          return 'MPINs do not match';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving ? null : _saveMpin,
                        child: _saving
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white),
                              )
                            : const Text('Update MPIN'),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),
          ],
        ),
      ),
      bottomNavigationBar: const StudentBottomNav(),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  const _Pill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
              letterSpacing: 0.5)),
    );
  }
}

class _MpinField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool obscure;
  final VoidCallback onToggle;
  final String? Function(String?) validator;

  const _MpinField({
    required this.controller,
    required this.label,
    required this.obscure,
    required this.onToggle,
    required this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: TextInputType.number,
      maxLength: 6,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        suffixIcon: IconButton(
          icon: Icon(
              obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              size: 18),
          onPressed: onToggle,
        ),
      ),
      validator: validator,
    );
  }
}
