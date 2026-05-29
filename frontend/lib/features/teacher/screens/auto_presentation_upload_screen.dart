import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/constants.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/shimmer_list.dart';
import '../providers/presentation_provider.dart';
import '../widgets/teacher_scaffold.dart';

class AutoPresentationUploadScreen extends ConsumerWidget {
  const AutoPresentationUploadScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: TeacherScaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(
            'New Presentation',
            style: GoogleFonts.poppins(
              fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white,
            ),
          ),
          backgroundColor: AppColors.primary,
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorColor: AppColors.accent,
            tabs: const [
              Tab(text: 'Pick from Database'),
              Tab(text: 'Upload New PDF'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _PickFromDatabaseTab(),
            _UploadNewTab(),
          ],
        ),
      ),
    );
  }
}

// ── Pick from database ───────────────────────────────────────────────────────

class _PickFromDatabaseTab extends ConsumerStatefulWidget {
  const _PickFromDatabaseTab();

  @override
  ConsumerState<_PickFromDatabaseTab> createState() =>
      _PickFromDatabaseTabState();
}

class _PickFromDatabaseTabState extends ConsumerState<_PickFromDatabaseTab> {
  int? _gradeFilter;
  String _subjectFilter = '';
  int? _submittingChapterId;

  @override
  Widget build(BuildContext context) {
    final chaptersAsync = ref.watch(availableChaptersProvider);

    return Column(
      children: [
        // Filter bar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int?>(
                  initialValue: _gradeFilter,
                  decoration: const InputDecoration(
                    labelText: 'Grade',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('All')),
                    DropdownMenuItem(value: 8, child: Text('Grade 8')),
                    DropdownMenuItem(value: 9, child: Text('Grade 9')),
                    DropdownMenuItem(value: 10, child: Text('Grade 10')),
                  ],
                  onChanged: (v) => setState(() => _gradeFilter = v),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'Subject filter',
                    isDense: true,
                  ),
                  onChanged: (v) =>
                      setState(() => _subjectFilter = v.trim().toLowerCase()),
                ),
              ),
            ],
          ),
        ),
        // List
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => ref.invalidate(availableChaptersProvider),
            child: chaptersAsync.when(
              loading: () => const ShimmerList(showAvatar: false),
              error: (e, _) => ErrorView(
                error: e,
                onRetry: () => ref.invalidate(availableChaptersProvider),
              ),
              data: (rows) {
                final filtered = rows.where((r) {
                  if (_gradeFilter != null && r['grade'] != _gradeFilter) {
                    return false;
                  }
                  if (_subjectFilter.isNotEmpty &&
                      !(r['subject'] as String? ?? '')
                          .toLowerCase()
                          .contains(_subjectFilter)) {
                    return false;
                  }
                  return true;
                }).toList();
                if (filtered.isEmpty) {
                  return _EmptyChapterState(
                    hasAny: rows.isNotEmpty,
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final c = filtered[i];
                    final chapterId = c['chapter_document_id'] as int;
                    final existingId =
                        c['existing_presentation_id'] as int?;
                    final existingStatus =
                        c['existing_presentation_status'] as String?;
                    return _ChapterRow(
                      data: c,
                      submitting: _submittingChapterId == chapterId,
                      existingPresentationId: existingId,
                      existingPresentationStatus: existingStatus,
                      onGenerate: () => _generate(chapterId),
                      onOpenExisting: existingId == null
                          ? null
                          : () => context.go(
                              '${RouteNames.teacherDashboard}/presentations/$existingId'),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _generate(int chapterDocumentId) async {
    setState(() => _submittingChapterId = chapterDocumentId);
    try {
      final api = ref.read(apiClientProvider);
      final result = await api.createPresentationFromChapter(
        chapterDocumentId: chapterDocumentId,
      );
      final id = result['presentation_id'] as int;
      ref.invalidate(availableChaptersProvider);
      ref.invalidate(presentationListProvider);
      if (mounted) {
        context.go('${RouteNames.teacherDashboard}/presentations/$id');
      }
    } on DioException catch (e) {
      _showError(e.response?.data is Map &&
              e.response!.data['detail'] is String
          ? e.response!.data['detail'] as String
          : 'Failed: ${e.response?.statusCode ?? '?'}');
    } catch (e) {
      _showError('Failed: $e');
    } finally {
      if (mounted) setState(() => _submittingChapterId = null);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error),
    );
  }
}

class _ChapterRow extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool submitting;
  final int? existingPresentationId;
  final String? existingPresentationStatus;
  final VoidCallback onGenerate;
  final VoidCallback? onOpenExisting;

  const _ChapterRow({
    required this.data,
    required this.submitting,
    required this.existingPresentationId,
    required this.existingPresentationStatus,
    required this.onGenerate,
    required this.onOpenExisting,
  });

  @override
  Widget build(BuildContext context) {
    final hasExisting = existingPresentationId != null;
    final isReady = existingPresentationStatus == 'READY';
    final isProcessing = existingPresentationStatus == 'PROCESSING';
    final created = DateTime.tryParse(data['created_at']?.toString() ?? '');

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.iconContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Grade ${data['grade']} · ${data['subject']}',
                  style: GoogleFonts.poppins(
                    fontSize: 11, fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const Spacer(),
              if (hasExisting)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: isReady
                        ? AppColors.success.withOpacity(0.15)
                        : isProcessing
                            ? AppColors.warning.withOpacity(0.15)
                            : AppColors.error.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isReady
                        ? 'Presentation ready'
                        : isProcessing
                            ? 'Generating…'
                            : 'Failed',
                    style: GoogleFonts.poppins(
                      fontSize: 10, fontWeight: FontWeight.w700,
                      color: isReady
                          ? AppColors.success
                          : isProcessing
                              ? AppColors.warning
                              : AppColors.error,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            data['chapter_name']?.toString() ?? '—',
            style: GoogleFonts.poppins(
              fontSize: 14, fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            'uploaded by ${data['teacher_username']}'
            '${created != null ? '  ·  ${DateFormat('d MMM').format(created)}' : ''}',
            style: GoogleFonts.poppins(
              fontSize: 11, color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (hasExisting) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: submitting ? null : onOpenExisting,
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: Text(
                      'Open existing',
                      style: GoogleFonts.poppins(
                          fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ] else ...[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: submitting ? null : onGenerate,
                    icon: submitting
                        ? const SizedBox(
                            height: 14, width: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.auto_awesome, size: 16),
                    label: Text(
                      submitting ? 'Generating…' : 'Generate presentation',
                      style: GoogleFonts.poppins(
                          fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyChapterState extends StatelessWidget {
  final bool hasAny;
  const _EmptyChapterState({required this.hasAny});

  @override
  Widget build(BuildContext context) {
    return ListView(
      // ListView so it works with RefreshIndicator
      children: [
        const SizedBox(height: 60),
        Center(
          child: Icon(Icons.library_books_outlined,
              size: 48, color: AppColors.textMuted),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            hasAny
                ? 'No chapters match your filter.'
                : 'No chapters in the school database yet.',
            style: GoogleFonts.poppins(
              fontSize: 13, fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            hasAny
                ? 'Try clearing the filter or upload a new PDF on the next tab.'
                : 'Upload one on the "Upload New PDF" tab, or add it via the Database screen.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 11, color: AppColors.textMuted),
          ),
        ),
      ],
    );
  }
}

// ── Upload new PDF ───────────────────────────────────────────────────────────

class _UploadNewTab extends ConsumerStatefulWidget {
  const _UploadNewTab();

  @override
  ConsumerState<_UploadNewTab> createState() => _UploadNewTabState();
}

class _UploadNewTabState extends ConsumerState<_UploadNewTab> {
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
        const SnackBar(content: Text('Fill subject, chapter, and pick a PDF.')),
      );
      return;
    }
    final bytes = _picked!.bytes;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read PDF bytes — pick again.')),
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
      ref.invalidate(availableChaptersProvider);
      if (!mounted) return;
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
    return ListView(
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
                color: _picked == null ? AppColors.divider : AppColors.primary,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _picked == null
                      ? Icons.picture_as_pdf_outlined
                      : Icons.check_circle_outline,
                  color:
                      _picked == null ? AppColors.textMuted : AppColors.primary,
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
          'Tip: if another teacher has already uploaded this chapter, '
          'use the "Pick from Database" tab to avoid duplicate generations.',
          style: GoogleFonts.poppins(
            fontSize: 11, color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}
