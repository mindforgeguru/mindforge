import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';

// ─── Models ──────────────────────────────────────────────────────────────────

class OldTestPaperModel {
  final int id;
  final String originalFilename;
  final int? grade;
  final String? subject;
  final String? chapter;
  final String? title;
  final String? aiSummary;
  final DateTime createdAt;

  const OldTestPaperModel({
    required this.id,
    required this.originalFilename,
    this.grade,
    this.subject,
    this.chapter,
    this.title,
    this.aiSummary,
    required this.createdAt,
  });

  factory OldTestPaperModel.fromJson(Map<String, dynamic> j) => OldTestPaperModel(
        id: j['id'] as int,
        originalFilename: j['original_filename'] as String? ?? '',
        grade: j['grade'] as int?,
        subject: j['subject'] as String?,
        chapter: j['chapter'] as String?,
        title: j['title'] as String?,
        aiSummary: j['ai_summary'] as String?,
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
      );
}

class ChapterDocumentModel {
  final int id;
  final String originalFilename;
  final int grade;
  final String subject;
  final String chapterName;
  final DateTime createdAt;

  const ChapterDocumentModel({
    required this.id,
    required this.originalFilename,
    required this.grade,
    required this.subject,
    required this.chapterName,
    required this.createdAt,
  });

  factory ChapterDocumentModel.fromJson(Map<String, dynamic> j) => ChapterDocumentModel(
        id: j['id'] as int,
        originalFilename: j['original_filename'] as String? ?? '',
        grade: j['grade'] as int,
        subject: j['subject'] as String,
        chapterName: j['chapter_name'] as String,
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
      );
}

class SyllabusEntryModel {
  final int id;
  final int grade;
  final String subject;
  final List<String> chapters;
  final String? originalFilename;
  final DateTime? updatedAt;

  const SyllabusEntryModel({
    required this.id,
    required this.grade,
    required this.subject,
    required this.chapters,
    this.originalFilename,
    this.updatedAt,
  });

  factory SyllabusEntryModel.fromJson(Map<String, dynamic> j) => SyllabusEntryModel(
        id: j['id'] as int,
        grade: j['grade'] as int,
        subject: j['subject'] as String,
        chapters: (j['chapters'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
        originalFilename: j['original_filename'] as String?,
        updatedAt: j['updated_at'] != null
            ? DateTime.tryParse(j['updated_at'] as String)
            : null,
      );
}

// ─── Providers ────────────────────────────────────────────────────────────────

final oldTestPapersProvider = FutureProvider.family<List<OldTestPaperModel>, (int?, String?)>(
  (ref, params) async {
    final api = ref.watch(apiClientProvider);
    final raw = await api.listOldTestPapers(grade: params.$1, subject: params.$2);
    return raw.map((e) => OldTestPaperModel.fromJson(e as Map<String, dynamic>)).toList();
  },
);

final chapterDocumentsProvider = FutureProvider.family<List<ChapterDocumentModel>, (int?, String?)>(
  (ref, params) async {
    final api = ref.watch(apiClientProvider);
    final raw = await api.listChapterDocuments(grade: params.$1, subject: params.$2);
    return raw.map((e) => ChapterDocumentModel.fromJson(e as Map<String, dynamic>)).toList();
  },
);

class ChapterNameItem {
  final String name;
  final bool hasPdf;
  const ChapterNameItem({required this.name, required this.hasPdf});
}

/// Returns combined chapter names (uploaded PDFs + syllabus) for grade+subject.
final chapterNamesProvider =
    FutureProvider.family<List<ChapterNameItem>, (int, String)>(
  (ref, params) async {
    final api = ref.watch(apiClientProvider);
    final raw = await api.listChapterNames(params.$1, params.$2);
    return raw
        .map((e) => ChapterNameItem(
              name: e['name'] as String,
              hasPdf: e['has_pdf'] as bool? ?? false,
            ))
        .toList();
  },
);

final syllabusProvider = FutureProvider.family<List<SyllabusEntryModel>, (int?, String?)>(
  (ref, params) async {
    final api = ref.watch(apiClientProvider);
    final raw = await api.listSyllabus(grade: params.$1, subject: params.$2);
    return raw.map((e) => SyllabusEntryModel.fromJson(e as Map<String, dynamic>)).toList();
  },
);
