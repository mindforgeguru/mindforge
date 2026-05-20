import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/error_view.dart';
import '../providers/admin_provider.dart';
import '../widgets/admin_scaffold.dart';

class AdminTeachersScreen extends ConsumerWidget {
  const AdminTeachersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teachersAsync = ref.watch(adminTeachersProvider);

    return AdminScaffold(
      showMobileBottomNav: false,
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Teacher Profiles'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(adminTeachersProvider),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6)),
              padding: const EdgeInsets.all(3),
              child: Image.asset('assets/images/logo.png',
                  fit: BoxFit.contain),
            ),
          ),
        ],
      ),
      body: teachersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(adminTeachersProvider),
        ),
        data: (teachers) {
          if (teachers.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_outline,
                      size: 64,
                      color: AppColors.textMuted.withValues(alpha: 0.4)),
                  const SizedBox(height: 16),
                  Text('No teachers yet.',
                      style: GoogleFonts.poppins(
                          fontSize: 15, color: AppColors.textMuted)),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(adminTeachersProvider.future),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              itemCount: teachers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _TeacherEditCard(teacher: teachers[i]),
            ),
          );
        },
      ),
    );
  }
}

class _TeacherEditCard extends ConsumerWidget {
  final Map<String, dynamic> teacher;
  const _TeacherEditCard({required this.teacher});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = teacher['username'] as String? ?? '';
    final picUrl = teacher['profile_pic_url'] as String?;
    final bio = teacher['bio'] as String?;
    final subjects = (teacher['subjects'] as List?)?.cast<String>() ?? [];

    return Container(
      decoration: mindForgeCardDecoration(),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 72,
              height: 72,
              child: picUrl != null
                  ? CachedNetworkImage(
                      imageUrl: picUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: AppColors.primary.withValues(alpha: 0.08),
                      ),
                      errorWidget: (_, __, ___) =>
                          _AvatarPlaceholder(name: name),
                    )
                  : _AvatarPlaceholder(name: name),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
                if (subjects.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: subjects
                        .take(4)
                        .map((s) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(s,
                                  style: GoogleFonts.poppins(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.accent)),
                            ))
                        .toList(),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  bio?.isNotEmpty == true ? bio! : 'No bio yet.',
                  style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.4,
                      fontStyle: bio?.isNotEmpty == true
                          ? FontStyle.normal
                          : FontStyle.italic),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: () => _openEditor(context, ref, teacher),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(
                          color: AppColors.primary.withValues(alpha: 0.4)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openEditor(
      BuildContext context, WidgetRef ref, Map<String, dynamic> t) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _TeacherEditorDialog(teacher: t),
    );
  }
}

class _TeacherEditorDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> teacher;
  const _TeacherEditorDialog({required this.teacher});

  @override
  ConsumerState<_TeacherEditorDialog> createState() =>
      _TeacherEditorDialogState();
}

class _TeacherEditorDialogState extends ConsumerState<_TeacherEditorDialog> {
  late final TextEditingController _bioCtrl;
  late String? _picUrl;
  bool _saving = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _bioCtrl = TextEditingController(
        text: widget.teacher['bio'] as String? ?? '');
    _picUrl = widget.teacher['profile_pic_url'] as String?;
  }

  @override
  void dispose() {
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await picked.readAsBytes();
      final api = ref.read(apiClientProvider);
      final result = await api.uploadTeacherPhotoAsAdmin(
          widget.teacher['id'] as int, bytes, picked.name);
      setState(() => _picUrl = result['profile_pic_url'] as String?);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Photo updated.'),
            backgroundColor: AppColors.success));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Photo upload failed: $e'),
            backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.updateTeacherBioAsAdmin(
          widget.teacher['id'] as int, _bioCtrl.text.trim());
      ref.invalidate(adminTeachersProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.teacher['username'] as String? ?? '';
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Edit $name',
                  style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
              const SizedBox(height: 16),
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      width: 96,
                      height: 96,
                      child: _uploading
                          ? const Center(
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : (_picUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: _picUrl!,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) =>
                                      _AvatarPlaceholder(name: name),
                                )
                              : _AvatarPlaceholder(name: name)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FilledButton.icon(
                          onPressed: _uploading ? null : _pickPhoto,
                          icon: const Icon(Icons.camera_alt_outlined, size: 16),
                          label: Text(_picUrl == null
                              ? 'Upload photo'
                              : 'Change photo'),
                          style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'JPEG or PNG, ≤ a few MB.',
                          style: GoogleFonts.poppins(
                              fontSize: 11, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text('Description',
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              TextField(
                controller: _bioCtrl,
                maxLines: 5,
                maxLength: 500,
                decoration: InputDecoration(
                  hintText:
                      'Short bio shown to students and parents on the Faculty page.',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary),
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvatarPlaceholder extends StatelessWidget {
  final String name;
  const _AvatarPlaceholder({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primary.withValues(alpha: 0.1),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : 'T',
          style: GoogleFonts.poppins(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: AppColors.primary.withValues(alpha: 0.5)),
        ),
      ),
    );
  }
}
