import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/constants.dart';
import '../providers/presentation_provider.dart';
import '../widgets/teacher_scaffold.dart';

class AutoPresentationUploadScreen extends ConsumerStatefulWidget {
  const AutoPresentationUploadScreen({super.key});

  @override
  ConsumerState<AutoPresentationUploadScreen> createState() =>
      _AutoPresentationUploadScreenState();
}

class _AutoPresentationUploadScreenState
    extends ConsumerState<AutoPresentationUploadScreen> {
  int _grade = 9;
  final _subjectCtrl = TextEditingController();
  final _chapterCtrl = TextEditingController();
  PlatformFile? _picked;
  bool _submitting = false;

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _chapterCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() => _picked = result.files.first);
  }

  Future<void> _submit() async {
    final subject = _subjectCtrl.text.trim();
    final chapter = _chapterCtrl.text.trim();
    if (subject.isEmpty || chapter.isEmpty || _picked == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill subject, chapter, and pick a PDF.')),
      );
      return;
    }
    final bytes = _picked!.bytes;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read the PDF bytes — try picking again.')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final api = ref.read(apiClientProvider);
      final result = await api.uploadChapterPresentation(
        grade: _grade,
        subject: subject,
        chapterName: chapter,
        fileBytes: bytes,
        filename: _picked!.name,
      );
      final id = result['presentation_id'] as int;
      ref.invalidate(presentationListProvider);
      if (!mounted) return;
      // Send the teacher to the detail page so they can watch generation finish.
      context.go('${RouteNames.teacherDashboard}/presentations/$id');
    } on DioException catch (e) {
      final body = e.response?.data;
      String msg;
      if (body is Map && body['detail'] is String) {
        msg = body['detail'] as String;
      } else if (body is Map && body['detail'] is List) {
        msg = (body['detail'] as List)
            .map((it) => (it is Map && it['msg'] is String) ? it['msg'] : '')
            .where((s) => (s as String).isNotEmpty)
            .join('\n');
        if (msg.isEmpty) {
          msg = 'Upload failed (status ${e.response?.statusCode ?? '?'}).';
        }
      } else {
        msg = 'Upload failed (status ${e.response?.statusCode ?? '?'}).';
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.error),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e'),
            backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pickedLabel = _picked?.name ?? 'Tap to pick a PDF';
    return TeacherScaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Upload Chapter PDF',
            style: GoogleFonts.poppins(
              fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white,
            )),
        backgroundColor: AppColors.primary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<int>(
            initialValue: _grade,
            decoration: const InputDecoration(
              labelText: 'Grade',
              prefixIcon: Icon(Icons.school_outlined),
            ),
            items: const [
              DropdownMenuItem(value: 8, child: Text('Grade 8')),
              DropdownMenuItem(value: 9, child: Text('Grade 9')),
              DropdownMenuItem(value: 10, child: Text('Grade 10')),
            ],
            onChanged: _submitting
                ? null
                : (v) => setState(() => _grade = v ?? _grade),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _subjectCtrl,
            enabled: !_submitting,
            decoration: const InputDecoration(
              labelText: 'Subject',
              hintText: 'e.g. Biology',
              prefixIcon: Icon(Icons.menu_book_outlined),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _chapterCtrl,
            enabled: !_submitting,
            decoration: const InputDecoration(
              labelText: 'Chapter name',
              hintText: 'e.g. Photosynthesis',
              prefixIcon: Icon(Icons.bookmark_border),
            ),
          ),
          const SizedBox(height: 20),
          InkWell(
            onTap: _submitting ? null : _pickPdf,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
              decoration: BoxDecoration(
                color: _picked == null
                    ? AppColors.iconContainer
                    : AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _picked == null
                      ? AppColors.divider
                      : AppColors.primary,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _picked == null
                        ? Icons.picture_as_pdf_outlined
                        : Icons.check_circle_outline,
                    color: _picked == null
                        ? AppColors.textMuted
                        : AppColors.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      pickedLabel,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: _picked == null
                            ? AppColors.textSecondary
                            : AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_picked != null)
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: _submitting
                          ? null
                          : () => setState(() => _picked = null),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              minimumSize: const Size(double.infinity, 50),
            ),
            child: _submitting
                ? const SizedBox(
                    height: 20, width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    'Generate Presentation',
                    style: GoogleFonts.poppins(
                      fontSize: 14, fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
          const SizedBox(height: 10),
          Text(
            'Gemini will scan the chapter and design a slide deck sized for one-hour periods. '
            'This usually takes 30-90 seconds.',
            style: GoogleFonts.poppins(
              fontSize: 11, color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
