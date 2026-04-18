import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/constants.dart';
import '../providers/database_provider.dart';
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
    _tab = TabController(length: 3, vsync: this);
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
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _OldTestsTab(),
          _ChaptersTab(),
          _SyllabusTab(),
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
    );
    if (result == null || result.files.isEmpty) return;

    setState(() => _uploading = true);
    try {
      final formData = FormData();
      for (final f in result.files) {
        if (f.path != null) {
          formData.files.add(MapEntry(
            'files',
            await MultipartFile.fromFile(f.path!, filename: f.name),
          ));
        } else if (f.bytes != null) {
          formData.files.add(MapEntry(
            'files',
            MultipartFile.fromBytes(f.bytes!, filename: f.name),
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
                  color: AppColors.primary.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.primary.withOpacity(0.15)),
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
        side: BorderSide(color: AppColors.primary.withOpacity(0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.description_outlined,
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
      if (f.path != null) {
        formData.files.add(MapEntry(
          'file',
          await MultipartFile.fromFile(f.path!, filename: f.name),
        ));
      } else if (f.bytes != null) {
        formData.files.add(MapEntry(
          'file',
          MultipartFile.fromBytes(f.bytes!, filename: f.name),
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
              color: AppColors.accent.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.accent.withOpacity(0.2)),
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
              side: BorderSide(color: AppColors.accent.withOpacity(0.2)),
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
        side: BorderSide(color: AppColors.accent.withOpacity(0.15)),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.accent.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.menu_book_outlined, size: 20, color: AppColors.accent),
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
      if (f.path != null) {
        formData.files.add(MapEntry(
          'file',
          await MultipartFile.fromFile(f.path!, filename: f.name),
        ));
      } else if (f.bytes != null) {
        formData.files.add(MapEntry(
          'file',
          MultipartFile.fromBytes(f.bytes!, filename: f.name),
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
              color: AppColors.secondary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.secondary.withOpacity(0.2)),
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
              side: BorderSide(color: AppColors.secondary.withOpacity(0.2)),
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
        side: BorderSide(color: AppColors.secondary.withOpacity(0.2)),
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
                            color: AppColors.secondary.withOpacity(0.08),
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
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}
