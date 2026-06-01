import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/constants.dart';
import '../providers/database_provider.dart';
import '../providers/presentation_provider.dart';
import '../widgets/teacher_scaffold.dart';

class TeacherDatabaseScreen extends ConsumerStatefulWidget {
  const TeacherDatabaseScreen({super.key});

  @override
  ConsumerState<TeacherDatabaseScreen> createState() =>
      _TeacherDatabaseScreenState();
}

class _TeacherDatabaseScreenState extends ConsumerState<TeacherDatabaseScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TeacherScaffold(
      appBar: AppBar(
        title: const Text('Knowledge Base'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(6)),
              padding: const EdgeInsets.all(3),
              child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: AppColors.accent,
          tabs: const [
            Tab(icon: Icon(Icons.history_edu_outlined, size: 18), text: 'Old Tests'),
            Tab(icon: Icon(Icons.menu_book_outlined, size: 18), text: 'Chapters'),
            Tab(icon: Icon(Icons.list_alt_outlined, size: 18), text: 'Syllabus'),
            Tab(icon: Icon(Icons.slideshow_outlined, size: 18), text: 'Presentations'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _OldTestsTab(),
          _ChaptersTab(),
          _SyllabusTab(),
          _PresentationsTab(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OLD TEST PAPERS TAB
// ─────────────────────────────────────────────────────────────────────────────

class _OldTestsTab extends ConsumerStatefulWidget {
  const _OldTestsTab();

  @override
  ConsumerState<_OldTestsTab> createState() => _OldTestsTabState();
}

class _OldTestsTabState extends ConsumerState<_OldTestsTab> {
  bool _uploading = false;

  Future<void> _upload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    setState(() => _uploading = true);
    try {
      final formData = FormData();
      for (final f in result.files) {
        if (f.bytes != null) {
          formData.files.add(MapEntry(
            'files',
            MultipartFile.fromBytes(f.bytes!, filename: f.name),
          ));
        } else if (!kIsWeb && f.path != null) {
          formData.files.add(MapEntry(
            'files',
            await MultipartFile.fromFile(f.path!, filename: f.name),
          ));
        }
      }
      await ref.read(apiClientProvider).uploadOldTestPapers(formData);
      ref.invalidate(oldTestPapersProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${result.files.length} paper(s) uploaded. AI is classifying them.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _delete(int id) async {
    try {
      await ref.read(apiClientProvider).deleteOldTestPaper(id);
      ref.invalidate(oldTestPapersProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final papersAsync = ref.watch(oldTestPapersProvider((null, null)));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
                ),
                child: const Text(
                  'Upload old/past test papers. AI will automatically scan each file and classify it by Grade, Subject, and Chapter. These will be used as reference when generating new tests.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: _uploading
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.upload_file),
                label: Text(_uploading ? 'Uploading & Scanning...' : 'Upload Old Test Papers'),
                onPressed: _uploading ? null : _upload,
              ),
            ],
          ),
        ),
        Expanded(
          child: papersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (papers) {
              if (papers.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history_edu_outlined, size: 64, color: AppColors.textMuted),
                      SizedBox(height: 12),
                      Text('No old test papers yet.\nUpload some to build your database.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textMuted)),
                    ],
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: papers.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final p = papers[i];
                  return _PaperCard(
                    filename: p.originalFilename,
                    grade: p.grade,
                    subject: p.subject,
                    chapter: p.chapter,
                    title: p.title,
                    summary: p.aiSummary,
                    onDelete: () => _delete(p.id),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PaperCard extends StatelessWidget {
  final String filename;
  final int? grade;
  final String? subject;
  final String? chapter;
  final String? title;
  final String? summary;
  final VoidCallback onDelete;

  const _PaperCard({
    required this.filename,
    this.grade,
    this.subject,
    this.chapter,
    this.title,
    this.summary,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final bool classified = grade != null || subject != null;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child:       Icon(Icons.description_outlined,
                  size: 22, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title ?? filename,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 4),
                  if (classified)
                    Wrap(
                      spacing: 6,
                      children: [
                        if (grade != null) _Tag('Grade $grade', AppColors.primary),
                        if (subject != null) _Tag(subject!, AppColors.accent),
                        if (chapter != null) _Tag(chapter!, AppColors.secondary),
                      ],
                    )
                  else
                    const Text('AI classification pending...',
                        style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  if (summary != null) ...[
                    const SizedBox(height: 4),
                    Text(summary!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.error),
              onPressed: onDelete,
              tooltip: 'Delete',
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CHAPTERS TAB
// ─────────────────────────────────────────────────────────────────────────────

class _ChaptersTab extends ConsumerStatefulWidget {
  const _ChaptersTab();

  @override
  ConsumerState<_ChaptersTab> createState() => _ChaptersTabState();
}

class _ChaptersTabState extends ConsumerState<_ChaptersTab> {
  bool _uploading = false;
  int? _selectedGrade;
  String? _selectedSubject;
  final _chapterCtrl = TextEditingController();
  PlatformFile? _pickedFile;

  @override
  void dispose() {
    _chapterCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() => _pickedFile = result.files.first);
    }
  }

  Future<void> _upload() async {
    if (_selectedGrade == null || _selectedSubject == null ||
        _chapterCtrl.text.isEmpty || _pickedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fill all fields and pick a file.')),
      );
      return;
    }

    setState(() => _uploading = true);
    try {
      final formData = FormData();
      formData.fields.addAll([
        MapEntry('grade', _selectedGrade.toString()),
        MapEntry('subject', _selectedSubject!),
        MapEntry('chapter_name', _chapterCtrl.text.trim()),
      ]);
      final f = _pickedFile!;
      if (f.bytes != null) {
        formData.files.add(MapEntry(
          'file',
          MultipartFile.fromBytes(f.bytes!, filename: f.name),
        ));
      } else if (!kIsWeb && f.path != null) {
        formData.files.add(MapEntry(
          'file',
          await MultipartFile.fromFile(f.path!, filename: f.name),
        ));
      }
      await ref.read(apiClientProvider).uploadChapterDocument(formData);
      ref.invalidate(chapterDocumentsProvider);
      setState(() {
        _pickedFile = null;
        _chapterCtrl.clear();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chapter uploaded successfully.'),
              backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _delete(int id) async {
    try {
      await ref.read(apiClientProvider).deleteChapterDocument(id);
      ref.invalidate(chapterDocumentsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final chaptersAsync = ref.watch(chapterDocumentsProvider((null, null)));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
            ),
            child: const Text(
              'Upload chapter PDFs or images. These will be used by AI to generate questions strictly from chapter content.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 16),

          // Upload form
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: AppColors.accent.withValues(alpha: 0.2)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Add Chapter Document',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w700,
                          )),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: _selectedGrade,
                        decoration: const InputDecoration(labelText: 'Grade', isDense: true),
                        hint: const Text('Grade'),
                        items: AppConstants.grades
                            .map((g) => DropdownMenuItem(value: g, child: Text('Grade $g')))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedGrade = v),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedSubject,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Subject', isDense: true),
                        hint: const Text('Subject'),
                        items: AppConstants.subjects
                            .map((s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(s, overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedSubject = v),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _chapterCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Chapter Name', isDense: true),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.attach_file, size: 18),
                    label: Text(_pickedFile != null
                        ? _pickedFile!.name
                        : 'Pick PDF or Image'),
                    onPressed: _pickFile,
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    icon: _uploading
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.upload),
                    label: Text(_uploading ? 'Uploading...' : 'Upload Chapter'),
                    onPressed: _uploading ? null : _upload,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),
          Text('Uploaded Chapters',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),

          chaptersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
            data: (chapters) {
              if (chapters.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text('No chapters uploaded yet.',
                        style: TextStyle(color: AppColors.textMuted)),
                  ),
                );
              }
              return Column(
                children: chapters.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ChapterCard(
                    filename: c.originalFilename,
                    grade: c.grade,
                    subject: c.subject,
                    chapterName: c.chapterName,
                    onDelete: () => _delete(c.id),
                  ),
                )).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ChapterCard extends StatelessWidget {
  final String filename;
  final int grade;
  final String subject;
  final String chapterName;
  final VoidCallback onDelete;

  const _ChapterCard({
    required this.filename,
    required this.grade,
    required this.subject,
    required this.chapterName,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.accent.withValues(alpha: 0.15)),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child:       Icon(Icons.menu_book_outlined, size: 20, color: AppColors.accent),
        ),
        title: Text(chapterName,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: Text('Grade $grade  •  $subject',
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.error),
          onPressed: onDelete,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SYLLABUS TAB
// ─────────────────────────────────────────────────────────────────────────────

class _SyllabusTab extends ConsumerStatefulWidget {
  const _SyllabusTab();

  @override
  ConsumerState<_SyllabusTab> createState() => _SyllabusTabState();
}

class _SyllabusTabState extends ConsumerState<_SyllabusTab> {
  bool _uploading = false;
  int? _selectedGrade;
  String? _selectedSubject;
  PlatformFile? _pickedFile;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() => _pickedFile = result.files.first);
    }
  }

  Future<void> _upload() async {
    if (_selectedGrade == null || _selectedSubject == null || _pickedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select grade, subject and pick a syllabus file.')),
      );
      return;
    }

    setState(() => _uploading = true);
    try {
      final formData = FormData();
      formData.fields.addAll([
        MapEntry('grade', _selectedGrade.toString()),
        MapEntry('subject', _selectedSubject!),
      ]);
      final f = _pickedFile!;
      if (f.bytes != null) {
        formData.files.add(MapEntry(
          'file',
          MultipartFile.fromBytes(f.bytes!, filename: f.name),
        ));
      } else if (!kIsWeb && f.path != null) {
        formData.files.add(MapEntry(
          'file',
          await MultipartFile.fromFile(f.path!, filename: f.name),
        ));
      }
      await ref.read(apiClientProvider).uploadSyllabus(formData);
      ref.invalidate(syllabusProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Syllabus uploaded. AI extracted the chapter list.'),
            backgroundColor: AppColors.success,
          ),
        );
        setState(() {
          _pickedFile = null;
          _selectedGrade = null;
          _selectedSubject = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _delete(int id) async {
    try {
      await ref.read(apiClientProvider).deleteSyllabus(id);
      ref.invalidate(syllabusProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final syllabusAsync = ref.watch(syllabusProvider((null, null)));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.secondary.withValues(alpha: 0.2)),
            ),
            child: const Text(
              'Upload your syllabus PDF. AI will automatically extract the chapter list for the selected grade and subject.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 16),

          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: AppColors.secondary.withValues(alpha: 0.2)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Upload Syllabus PDF',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: AppColors.secondary,
                            fontWeight: FontWeight.w700,
                          )),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: _selectedGrade,
                        decoration: const InputDecoration(labelText: 'Grade', isDense: true),
                        hint: const Text('Grade'),
                        items: AppConstants.grades
                            .map((g) => DropdownMenuItem(value: g, child: Text('Grade $g')))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedGrade = v),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedSubject,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Subject', isDense: true),
                        hint: const Text('Subject'),
                        items: AppConstants.subjects
                            .map((s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(s, overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedSubject = v),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.upload_file, size: 18),
                    label: Text(
                      _pickedFile != null ? _pickedFile!.name : 'Pick Syllabus PDF or Image',
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: _pickFile,
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    icon: _uploading
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.auto_awesome, size: 18),
                    label: Text(_uploading ? 'Scanning & Saving...' : 'Upload & Extract Chapters'),
                    onPressed: _uploading ? null : _upload,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),
          Text('Saved Syllabus',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),

          syllabusAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
            data: (entries) {
              if (entries.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.list_alt_outlined, size: 64, color: AppColors.textMuted),
                        SizedBox(height: 12),
                        Text('No syllabus uploaded yet.\nUpload a PDF to get started.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                );
              }
              return Column(
                children: entries.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _SyllabusCard(
                    grade: s.grade,
                    subject: s.subject,
                    chapters: s.chapters,
                    originalFilename: s.originalFilename,
                    onDelete: () => _delete(s.id),
                  ),
                )).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SyllabusCard extends StatelessWidget {
  final int grade;
  final String subject;
  final List<String> chapters;
  final String? originalFilename;
  final VoidCallback onDelete;

  const _SyllabusCard({
    required this.grade,
    required this.subject,
    required this.chapters,
    this.originalFilename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.secondary.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Tag('Grade $grade', AppColors.primary),
                const SizedBox(width: 6),
                _Tag(subject, AppColors.secondary),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.error),
                  onPressed: onDelete,
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            if (originalFilename != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.picture_as_pdf, size: 13, color: AppColors.textMuted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(originalFilename!,
                        style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            if (chapters.isEmpty)
              const Text('No chapters extracted yet.',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted))
            else
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: chapters
                    .map((c) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.secondary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(c,
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.textSecondary)),
                        ))
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Shared widget ─────────────────────────────────────────────────────────────

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  const _Tag(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PRESENTATIONS TAB — school-wide presentation library
// ─────────────────────────────────────────────────────────────────────────────

class _PresentationsTab extends ConsumerStatefulWidget {
  const _PresentationsTab();

  @override
  ConsumerState<_PresentationsTab> createState() => _PresentationsTabState();
}

class _PresentationsTabState extends ConsumerState<_PresentationsTab> {
  int? _gradeFilter;
  String _subjectFilter = '';
  int? _adoptingPresentationId;

  @override
  Widget build(BuildContext context) {
    final asyncLib = ref.watch(presentationLibraryProvider);

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
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(presentationLibraryProvider),
            child: asyncLib.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Could not load library.\n$e',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textMuted),
                  ),
                ),
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
                  return ListView(children: [
                    const SizedBox(height: 60),
                    Center(
                      child: Icon(Icons.slideshow_outlined,
                          size: 48, color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        rows.isEmpty
                            ? 'No presentations in the library yet.'
                            : 'No presentations match the filter.',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          rows.isEmpty
                              ? 'When a teacher uploads a chapter PDF and the slides are generated, it shows up here for everyone to adopt.'
                              : 'Try a wider grade or subject filter.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textMuted),
                        ),
                      ),
                    ),
                  ]);
                }
                // Group by lifecycle_state (PENDING / ONGOING / COMPLETED)
                // and sort each bucket sensibly.
                final buckets = <String, List<Map<String, dynamic>>>{
                  'ONGOING': <Map<String, dynamic>>[],
                  'PENDING': <Map<String, dynamic>>[],
                  'COMPLETED': <Map<String, dynamic>>[],
                };
                for (final r in filtered) {
                  final state = (r['lifecycle_state'] as String? ?? 'PENDING')
                      .toUpperCase();
                  buckets.putIfAbsent(state, () => []).add(r);
                }
                // Sort each bucket: completed → by completion date desc,
                // ongoing/pending → by created_at desc.
                int byDateDesc(String key, Map a, Map b) {
                  final av = a[key]?.toString() ?? '';
                  final bv = b[key]?.toString() ?? '';
                  return bv.compareTo(av); // empty strings end up last
                }
                buckets['COMPLETED']!.sort((a, b) {
                  // Primary: last_completion_at desc. Fallback: created_at.
                  final cmp = byDateDesc('last_completion_at', a, b);
                  return cmp != 0 ? cmp : byDateDesc('created_at', a, b);
                });
                buckets['ONGOING']!.sort((a, b) => byDateDesc('created_at', a, b));
                buckets['PENDING']!.sort((a, b) => byDateDesc('created_at', a, b));

                // Flatten into a list of widgets with sticky section
                // headers — keeps ListView lightweight without needing
                // SliverList.
                final widgets = <Widget>[];
                final order = <(String, String, Color)>[
                  ('PENDING', 'Pending', AppColors.warning),
                  ('ONGOING', 'On going', AppColors.primary),
                  ('COMPLETED', 'Completed', AppColors.success),
                ];
                for (final (state, label, color) in order) {
                  final group = buckets[state] ?? const [];
                  if (group.isEmpty) continue;
                  widgets.add(_GroupHeader(
                    label: label,
                    count: group.length,
                    color: color,
                  ));
                  for (final r in group) {
                    widgets.add(Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _LibraryRow(
                        data: r,
                        submitting: _adoptingPresentationId ==
                            r['presentation_id'],
                        onOpen: () => _openOrAdopt(r),
                        onDelete: () => _confirmAndDelete(r),
                      ),
                    ));
                  }
                  widgets.add(const SizedBox(height: 8));
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                  children: widgets,
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmAndDelete(Map<String, dynamic> row) async {
    final id = row['presentation_id'] as int;
    final chapter = row['chapter_name']?.toString() ?? 'this presentation';
    final adopterCount = row['adopter_count'] as int? ?? 0;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete presentation?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('"$chapter" will be permanently deleted.'),
            const SizedBox(height: 8),
            if (adopterCount > 0)
              Text(
                '$adopterCount teacher${adopterCount == 1 ? '' : 's'} currently '
                'use${adopterCount == 1 ? 's' : ''} this deck — their progress '
                'bars and period logs will be removed too.',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.error,
                    fontWeight: FontWeight.w600),
              )
            else
              const Text(
                'No teachers have adopted it yet.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(apiClientProvider).deletePresentation(id);
      ref.invalidate(presentationLibraryProvider);
      try {
        ref.invalidate(presentationListProvider);
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted "$chapter".')),
      );
    } on DioException catch (e) {
      final body = e.response?.data;
      final msg = body is Map && body['detail'] is String
          ? body['detail'] as String
          : 'Delete failed: ${e.response?.statusCode ?? '?'}';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.error),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e'),
            backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _openOrAdopt(Map<String, dynamic> row) async {
    final id = row['presentation_id'] as int;
    final alreadyAdopted =
        row['already_adopted_by_me'] as bool? ?? false;

    if (alreadyAdopted) {
      // Already on your dashboard — just open.
      context.go('${RouteNames.teacherDashboard}/presentations/$id');
      return;
    }

    setState(() => _adoptingPresentationId = id);
    try {
      final api = ref.read(apiClientProvider);
      await api.adoptPresentation(id);
      ref.invalidate(presentationLibraryProvider);
      // refresh dashboard tile too
      try {
        ref.invalidate(presentationListProvider);
      } catch (_) {}
      if (!mounted) return;
      context.go('${RouteNames.teacherDashboard}/presentations/$id');
    } on DioException catch (e) {
      final body = e.response?.data;
      final msg = body is Map && body['detail'] is String
          ? body['detail'] as String
          : 'Failed: ${e.response?.statusCode ?? '?'}';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.error),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'),
            backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _adoptingPresentationId = null);
    }
  }
}

class _LibraryRow extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool submitting;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  const _LibraryRow({
    required this.data,
    required this.submitting,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final adoptedByMe = data['already_adopted_by_me'] as bool? ?? false;
    final adopterCount = data['adopter_count'] as int? ?? 0;
    final completedCount = data['completed_count'] as int? ?? 0;
    final myIsCompleted = data['my_is_completed'] as bool? ?? false;
    final total = data['total_slides'] as int? ?? 0;
    final periods = data['recommended_periods'] as int? ?? 0;
    final status = (data['status'] as String? ?? 'READY').toUpperCase();
    final lifecycle =
        (data['lifecycle_state'] as String? ?? 'PENDING').toUpperCase();
    final isReady = status == 'READY';
    final isProcessing = status == 'PROCESSING';
    final isFailed = status == 'FAILED';

    // Status capsule. PROCESSING/FAILED show their generation status so
    // teachers can spot decks still being made or broken. Otherwise show
    // the lifecycle bucket (Pending / On going / Completed).
    final (statusLabel, statusColor) = isProcessing
        ? ('Generating…', AppColors.warning)
        : isFailed
            ? ('Failed', AppColors.error)
            : switch (lifecycle) {
                'COMPLETED' => ('Completed', AppColors.success),
                'ONGOING' => ('On going', AppColors.primary),
                _ => ('Pending', AppColors.warning),
              };

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
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
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Grade ${data['grade']} · ${data['subject']}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Status pill — always visible so PROCESSING / FAILED rows
              // surface immediately in the library.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isProcessing) ...[
                      SizedBox(
                        width: 9, height: 9,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          valueColor: AlwaysStoppedAnimation(statusColor),
                        ),
                      ),
                      const SizedBox(width: 5),
                    ],
                    Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Per-teacher state pill — completed / in progress / nothing.
              if (myIsCompleted)
                _StatePill(
                  label: '✓ You completed',
                  color: AppColors.success,
                )
              else if (adoptedByMe)
                _StatePill(
                  label: 'On your dashboard',
                  color: AppColors.primary,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            data['chapter_name']?.toString() ?? '—',
            style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'by ${data['created_by_username']}'
            '   ·   $total slides · $periods × 1-hour periods'
            '   ·   ${_adoptionSummary(adopterCount, completedCount)}',
            style: const TextStyle(
              fontSize: 11, color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  // Disable Adopt while the deck is still generating or
                  // has failed — only adopt READY decks.
                  onPressed: (submitting || !isReady) ? null : onOpen,
                  icon: submitting
                      ? const SizedBox(
                          height: 14, width: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(
                          myIsCompleted
                              ? Icons.replay_circle_filled
                              : adoptedByMe
                                  ? Icons.open_in_new
                                  : isProcessing
                                      ? Icons.hourglass_top
                                      : isFailed
                                          ? Icons.error_outline
                                          : Icons.add_to_photos_outlined,
                          size: 16,
                        ),
                  label: Text(
                    submitting
                        ? 'Adopting…'
                        : myIsCompleted
                            ? 'Open completed deck'
                            : adoptedByMe
                                ? 'Open'
                                : isProcessing
                                    ? 'Generating…'
                                    : isFailed
                                        ? 'Failed — delete?'
                                        : 'Adopt for my class',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: myIsCompleted
                        ? AppColors.success
                        : adoptedByMe
                            ? AppColors.primary
                            : AppColors.accent,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: AppColors.error),
                onPressed: submitting ? null : onDelete,
                tooltip: 'Delete presentation',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _adoptionSummary(int adopterCount, int completedCount) {
  final inProgress = (adopterCount - completedCount).clamp(0, adopterCount);
  if (adopterCount == 0) return 'No teachers using it yet';
  final parts = <String>[];
  if (inProgress > 0) {
    parts.add('$inProgress teaching');
  }
  if (completedCount > 0) {
    parts.add('$completedCount completed');
  }
  return parts.join(' · ');
}

class _StatePill extends StatelessWidget {
  final String label;
  final Color color;
  const _StatePill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _GroupHeader({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Row(
        children: [
          Container(
            width: 4, height: 14,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Divider(color: color.withValues(alpha: 0.25), thickness: 1),
            ),
          ),
        ],
      ),
    );
  }
}
