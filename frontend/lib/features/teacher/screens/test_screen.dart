import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/test.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/shimmer_list.dart';
import '../../../core/utils/constants.dart';
import '../../../core/utils/responsive.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/teacher_provider.dart';
import '../providers/database_provider.dart';
import '../widgets/teacher_bottom_nav.dart';
import '../widgets/teacher_scaffold.dart';
import 'test_detail_screen.dart';

class TeacherTestScreen extends ConsumerStatefulWidget {
  const TeacherTestScreen({super.key});

  @override
  ConsumerState<TeacherTestScreen> createState() => _TeacherTestScreenState();
}

class _TeacherTestScreenState extends ConsumerState<TeacherTestScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TeacherScaffold(
      appBar: AppBar(
        title: const Text('Tests'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
              padding: const EdgeInsets.all(3),
              child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: AppColors.accent,
          tabs: const [
            Tab(text: 'Online Tests'),
            Tab(text: 'Offline Tests'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _TestsTab(testType: 'online'),
          _TestsTab(testType: 'offline'),
        ],
      ),
    );
  }
}

class _TestsTab extends ConsumerStatefulWidget {
  final String testType;
  const _TestsTab({required this.testType});

  @override
  ConsumerState<_TestsTab> createState() => _TestsTabState();
}

class _TestsTabState extends ConsumerState<_TestsTab> {
  bool _showGenerator = false;
  int _limit = 20; // Load More tracks how many tests to fetch

  // Generation form state
  final _titleCtrl = TextEditingController();
  int? _selectedGrade;
  String? _selectedSubject;
  String? _selectedChapter;
  int _mcqCount = 0;
  int _fillBlankCount = 0;
  int _trueFalseCount = 0;
  int _matchFollowingCount = 0;
  int _vsaCount = 0;
  int _shortAnswerCount = 0;
  int _longAnswerCount = 0;
  int _diagramCount = 0;
  bool _includeNumericals = false;
  // 'database' | 'upload' | 'none'
  String _sourceMode = 'database';
  PlatformFile? _uploadedChapter;
  bool _useDatabase = true;
  int _srcPctP = 20;
  int _srcPctE = 20;
  int _srcPctNP = 20;
  int _srcPctNE = 20;
  int get _srcPctAI => (100 - _srcPctP - _srcPctE - _srcPctNP - _srcPctNE).clamp(0, 100);
  int _timeLimitMinutes = 0;
  bool _isGenerating = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final testsAsync = ref.watch(teacherTestsProvider((null, _limit)));

    return RefreshIndicator(
      onRefresh: () async {
        setState(() => _limit = 20);
        ref.invalidate(teacherTestsProvider((null, _limit)));
      },
      child: SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Generator panel toggle ─────────────────────────────────────
          ElevatedButton.icon(
            icon: Icon(_showGenerator ? Icons.close : Icons.auto_awesome),
            label: Text(_showGenerator
                ? 'Close Generator'
                : 'Generate ${widget.testType == "online" ? "Online" : "Offline"} Test'),
            onPressed: () =>
                setState(() => _showGenerator = !_showGenerator),
          ),

          if (_showGenerator) ...[
            const SizedBox(height: 16),
            _buildGeneratorForm(),
          ],

          const SizedBox(height: 24),

          Text(
            'Existing ${widget.testType == "online" ? "Online" : "Offline"} Tests',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),

          // ── Tests list ───────────────────────────────────────────────────
          testsAsync.when(
            loading: () => const ShimmerCards(count: 5, cardHeight: 72),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(teacherTestsProvider((null, _limit)))),

            data: (tests) {
              final filtered = tests
                  .where((t) => t.testType == widget.testType)
                  .toList();
              if (filtered.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('No tests generated yet.')),
                );
              }
              final hasMore = tests.length >= _limit;
              return Column(
                children: [
                  ...filtered.map((t) => _TestTile(test: t)),
                  if (hasMore)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.expand_more),
                        label: const Text('Load More'),
                        onPressed: () => setState(() => _limit += 20),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildGeneratorForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: mindForgeCardDecoration(
          color: AppColors.primary.withOpacity(0.04)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('AI Test Generator',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.primary,
                  )),
          const SizedBox(height: 12),

          TextField(controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Test Title')),
          const SizedBox(height: 8),

          Row(children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                value: _selectedGrade,
                decoration: const InputDecoration(labelText: 'Grade'),
                hint: const Text('Select Grade'),
                items: AppConstants.grades
                    .map((g) => DropdownMenuItem(
                          value: g,
                          child: Text('Grade $g'),
                        ))
                    .toList(),
                onChanged: (v) => setState(() {
                  _selectedGrade = v;
                  _selectedChapter = null; // reset chapter when grade changes
                }),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _selectedSubject,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Subject'),
                hint: const Text('Select Subject'),
                items: AppConstants.subjects
                    .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(s, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) => setState(() {
                  _selectedSubject = v;
                  _selectedChapter = null; // reset chapter when subject changes
                }),
              ),
            ),
          ]),
          const SizedBox(height: 12),

          // ── Chapter picker from database ──────────────────────────────
          if (_selectedGrade != null && _selectedSubject != null)
            _ChapterPicker(
              grade: _selectedGrade!,
              subject: _selectedSubject!,
              value: _selectedChapter,
              onChanged: (v) => setState(() => _selectedChapter = v),
            )
          else
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Chapter',
                border: OutlineInputBorder(),
              ),
              child: Text(
                'Select Grade and Subject first',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ),
          const SizedBox(height: 12),

          // Question type counts
          Text('Question Types',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _CountRow(label: 'MCQ (1 mark)', value: _mcqCount,
              onChanged: (v) => setState(() => _mcqCount = v)),
          _CountRow(label: 'True/False (1 mark)', value: _trueFalseCount,
              onChanged: (v) => setState(() => _trueFalseCount = v)),
          _CountRow(label: 'Fill in the Blank (1 mark)', value: _fillBlankCount,
              onChanged: (v) => setState(() => _fillBlankCount = v)),
          _CountRow(label: 'Match the Following (1 mark/pair)', value: _matchFollowingCount,
              onChanged: (v) => setState(() => _matchFollowingCount = v)),
          _CountRow(label: 'VSA / One Word (1 mark)', value: _vsaCount,
              onChanged: (v) => setState(() => _vsaCount = v)),

          if (widget.testType == 'offline') ...[
            _CountRow(label: 'Short Answer (2 marks)', value: _shortAnswerCount,
                onChanged: (v) => setState(() => _shortAnswerCount = v)),
            _CountRow(label: 'Long Answer (3 marks)', value: _longAnswerCount,
                onChanged: (v) => setState(() => _longAnswerCount = v)),
            _CountRow(label: 'Diagram Based (5 marks)', value: _diagramCount,
                onChanged: (v) => setState(() => _diagramCount = v)),
          ],

          SwitchListTile(
            value: _includeNumericals,
            title: const Text('Include Numericals'),
            onChanged: (v) => setState(() => _includeNumericals = v),
            contentPadding: EdgeInsets.zero,
          ),
          _buildSourceModePicker(),

          const SizedBox(height: 8),
          if (widget.testType == 'online')
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.info.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.timer_outlined, size: 16, color: AppColors.info),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Time limit auto-set: 1 min per question (${_mcqCount + _fillBlankCount + _trueFalseCount + _matchFollowingCount + _vsaCount} questions = ${_mcqCount + _fillBlankCount + _trueFalseCount + _matchFollowingCount + _vsaCount} min)',
                      style: const TextStyle(fontSize: 12, color: AppColors.info),
                    ),
                  ),
                ],
              ),
            )
          else
            Row(children: [
              const Text('Time limit: '),
              Expanded(
                child: Slider(
                  value: _timeLimitMinutes.toDouble(),
                  min: 0,
                  max: 180,
                  divisions: 36,
                  label: _timeLimitMinutes == 0 ? 'Not set' : '$_timeLimitMinutes min',
                  onChanged: (v) =>
                      setState(() => _timeLimitMinutes = v.round()),
                ),
              ),
              Text(_timeLimitMinutes == 0 ? '—' : '$_timeLimitMinutes min'),
            ]),

          const SizedBox(height: 12),

          // ── Total marks display ──────────────────────────────────────
          Builder(builder: (_) {
            final total = _mcqCount * 1 +
                _trueFalseCount * 1 +
                _fillBlankCount * 1 +
                _matchFollowingCount * 1 +
                _vsaCount * 1 +
                _shortAnswerCount * 2 +
                _longAnswerCount * 3 +
                _diagramCount * 5 +
                (_includeNumericals ? 4 : 0); // 2 numericals × 2 marks
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.primary.withOpacity(0.2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total Marks',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: R.fs(context, 14, min: 12, max: 16),
                      color: AppColors.primary,
                    ),
                  ),
                  Text(
                    '$total marks',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: R.fs(context, 16, min: 13, max: 18),
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 12),
          ElevatedButton.icon(
            icon: _isGenerating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.auto_awesome),
            label: Text(_isGenerating ? 'Generating...' : 'Generate Test'),
            onPressed: _isGenerating ? null : _generateTest,
          ),
        ],
      ),
    );
  }

  Widget _buildSourceModePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Source Material', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),

        // ── 3 option cards ────────────────────────────────────────────────────
        _SourceOptionCard(
          value: 'database',
          groupValue: _sourceMode,
          icon: Icons.storage_rounded,
          title: 'Knowledge Base',
          subtitle: 'Use your uploaded chapter PDFs, old tests & syllabus',
          onTap: () => setState(() {
            _sourceMode = 'database';
            _useDatabase = true;
            _uploadedChapter = null;
          }),
        ),
        const SizedBox(height: 6),
        _SourceOptionCard(
          value: 'upload',
          groupValue: _sourceMode,
          icon: Icons.upload_file_rounded,
          title: 'Upload Chapter',
          subtitle: 'Pick a PDF or image — test generated from that file only',
          onTap: () => setState(() {
            _sourceMode = 'upload';
            _useDatabase = false;
          }),
        ),
        const SizedBox(height: 6),
        _SourceOptionCard(
          value: 'none',
          groupValue: _sourceMode,
          icon: Icons.auto_awesome_outlined,
          title: 'AI Only',
          subtitle: 'No source material — fully AI-generated questions',
          onTap: () => setState(() {
            _sourceMode = 'none';
            _useDatabase = false;
            _uploadedChapter = null;
          }),
        ),

        // ── Upload picker (shown when 'upload' selected) ───────────────────
        if (_sourceMode == 'upload') ...[
          const SizedBox(height: 10),
          _buildUploadPicker(),
        ],

        // ── Source distribution (shown when 'database' selected) ──────────
        if (_sourceMode == 'database') ...[
          const SizedBox(height: 10),
          _buildSourceDistribution(),
        ],
      ],
    );
  }

  Future<void> _pickChapterFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() => _uploadedChapter = result.files.first);
  }

  Widget _buildUploadPicker() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accent.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.accent.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_uploadedChapter == null)
            OutlinedButton.icon(
              icon: const Icon(Icons.attach_file, size: 18),
              label: const Text('Pick PDF / Image'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: BorderSide(color: AppColors.accent.withOpacity(0.5)),
              ),
              onPressed: _pickChapterFile,
            )
          else
            Row(
              children: [
                const Icon(Icons.picture_as_pdf, size: 18, color: AppColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _uploadedChapter!.name,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: _pickChapterFile,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Change', style: TextStyle(fontSize: 12)),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16, color: AppColors.error),
                  onPressed: () => setState(() => _uploadedChapter = null),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          if (_uploadedChapter == null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Supported: PDF, JPG, PNG',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSourceDistribution() {
    final remaining = _srcPctAI;
    final overLimit = (_srcPctP + _srcPctE + _srcPctNP + _srcPctNE) > 100;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pie_chart_outline, size: 15, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                'Source Distribution',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppColors.primary,
                ),
              ),
              const Spacer(),
              if (overLimit)
                Text('Over 100%!',
                    style: const TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.w600))
              else
                Text('Total: 100%',
                    style: TextStyle(color: Colors.green.shade700, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          _SrcSlider(
            label: '[P]', sublabel: 'Exact — past test paper',
            color: const Color(0xFF1565C0),
            value: _srcPctP,
            max: (100 - _srcPctE - _srcPctNP - _srcPctNE).clamp(0, 100),
            onChanged: (v) => setState(() => _srcPctP = v),
          ),
          _SrcSlider(
            label: '[E]', sublabel: 'Exact — back exercise',
            color: const Color(0xFF2E7D32),
            value: _srcPctE,
            max: (100 - _srcPctP - _srcPctNP - _srcPctNE).clamp(0, 100),
            onChanged: (v) => setState(() => _srcPctE = v),
          ),
          _SrcSlider(
            label: '[~P]', sublabel: 'AI-style of past paper',
            color: const Color(0xFF1976D2),
            value: _srcPctNP,
            max: (100 - _srcPctP - _srcPctE - _srcPctNE).clamp(0, 100),
            onChanged: (v) => setState(() => _srcPctNP = v),
          ),
          _SrcSlider(
            label: '[~E]', sublabel: 'AI-style of exercise',
            color: const Color(0xFF388E3C),
            value: _srcPctNE,
            max: (100 - _srcPctP - _srcPctE - _srcPctNP).clamp(0, 100),
            onChanged: (v) => setState(() => _srcPctNE = v),
          ),
          // AI remainder — read-only
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Container(
                  width: 36,
                  alignment: Alignment.center,
                  child: Text(
                    '[AI]',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        color: Color(0xFF6A1B9A)),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Fully AI-generated',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ),
                Text(
                  '$remaining%',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: overLimit ? Colors.red : const Color(0xFF6A1B9A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _generateTest() async {
    if (_titleCtrl.text.isEmpty || _selectedGrade == null ||
        _selectedSubject == null || _selectedChapter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please fill in title, grade, subject, and select a chapter.')),
      );
      return;
    }
    if (_sourceMode == 'upload' && _uploadedChapter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please pick a chapter file to upload.')),
      );
      return;
    }

    setState(() => _isGenerating = true);
    final api = ref.read(apiClientProvider);

    final formData = FormData();
    formData.fields.addAll([
      MapEntry('title', _titleCtrl.text),
      MapEntry('grade', _selectedGrade!.toString()),
      MapEntry('subject', _selectedSubject!),
      MapEntry('chapter', _selectedChapter!),
      MapEntry('test_type', widget.testType),
      MapEntry('mcq_count', _mcqCount.toString()),
      MapEntry('fill_blank_count', _fillBlankCount.toString()),
      MapEntry('true_false_count', _trueFalseCount.toString()),
      MapEntry('match_following_count', _matchFollowingCount.toString()),
      MapEntry('vsa_count', _vsaCount.toString()),
      MapEntry('short_answer_count', _shortAnswerCount.toString()),
      MapEntry('long_answer_count', _longAnswerCount.toString()),
      MapEntry('diagram_count', _diagramCount.toString()),
      MapEntry('include_numericals', _includeNumericals.toString()),
      MapEntry('use_database', _useDatabase.toString()),
      MapEntry('src_pct_p', _srcPctP.toString()),
      MapEntry('src_pct_e', _srcPctE.toString()),
      MapEntry('src_pct_np', _srcPctNP.toString()),
      MapEntry('src_pct_ne', _srcPctNE.toString()),
      MapEntry('src_pct_ai', _srcPctAI.toString()),
      MapEntry('time_limit_minutes', _timeLimitMinutes.toString()),
    ]);

    // Attach uploaded chapter file if in upload mode
    if (_sourceMode == 'upload' && _uploadedChapter != null) {
      final f = _uploadedChapter!;
      final mf = f.path != null
          ? await MultipartFile.fromFile(f.path!, filename: f.name)
          : MultipartFile.fromBytes(f.bytes!, filename: f.name);
      formData.files.add(MapEntry('source_files', mf));
    }
    try {
      final result = await api.generateTest(formData);
      ref.invalidate(teacherTestsProvider);
      final generatedTest = TestModel.fromJson(result);
      setState(() {
        _isGenerating = false;
        _showGenerator = false;
        _selectedChapter = null;
      });
      if (mounted) {
        // Navigate to detail screen immediately after generation
        await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => TestDetailScreen(test: generatedTest)),
        );
      }
    } catch (e) {
      setState(() => _isGenerating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Generation failed: $e'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }
}

// ─── Chapter picker that loads from the knowledge base ────────────────────────

class _ChapterPicker extends ConsumerWidget {
  final int grade;
  final String subject;
  final String? value;
  final ValueChanged<String?> onChanged;

  const _ChapterPicker({
    required this.grade,
    required this.subject,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chaptersAsync = ref.watch(chapterNamesProvider((grade, subject)));

    return chaptersAsync.when(
      loading: () => const InputDecorator(
        decoration: InputDecoration(labelText: 'Chapter', border: OutlineInputBorder()),
        child: SizedBox(
          height: 20,
          child: LinearProgressIndicator(),
        ),
      ),
      error: (_, __) => TextField(
        decoration: const InputDecoration(labelText: 'Chapter / Topic'),
        onChanged: (v) => onChanged(v.isEmpty ? null : v),
      ),
      data: (chapters) {
        if (chapters.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Chapter',
                  border: const OutlineInputBorder(),
                  suffixIcon: Icon(Icons.warning_amber_rounded,
                      color: AppColors.warning, size: 20),
                ),
                child: Text(
                  'No chapters in database for $subject Grade $grade',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Upload chapter PDFs or a syllabus PDF in the Database tab first.',
                style: TextStyle(fontSize: 11, color: AppColors.warning),
              ),
            ],
          );
        }

        // Ensure current value is still valid (e.g. after grade/subject change)
        final validValue = chapters.any((c) => c.name == value) ? value : null;
        if (validValue != value) {
          WidgetsBinding.instance.addPostFrameCallback((_) => onChanged(validValue));
        }

        return DropdownButtonFormField<String>(
          value: validValue,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Chapter',
            border: OutlineInputBorder(),
          ),
          hint: const Text('Select Chapter'),
          items: chapters.map((c) {
            return DropdownMenuItem<String>(
              value: c.name,
              child: Row(
                children: [
                  Icon(
                    c.hasPdf ? Icons.picture_as_pdf : Icons.list_alt_outlined,
                    size: 15,
                    color: c.hasPdf ? AppColors.accent : AppColors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(c.name, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: onChanged,
        );
      },
    );
  }
}

class _CountRow extends StatelessWidget {
  final String label;
  final int value;
  final void Function(int) onChanged;

  const _CountRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: R.fs(context, 13, min: 11, max: 15)),
                  overflow: TextOverflow.ellipsis)),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            onPressed: value > 0 ? () => onChanged(value - 1) : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          SizedBox(
            width: 32,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 20),
            onPressed: () => onChanged(value + 1),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

// ─── Source mode option card ──────────────────────────────────────────────────

class _SourceOptionCard extends StatelessWidget {
  final String value;
  final String groupValue;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SourceOptionCard({
    required this.value,
    required this.groupValue,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    final color = selected ? AppColors.primary : AppColors.textSecondary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withOpacity(0.07)
              : Colors.grey.withOpacity(0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? AppColors.primary.withOpacity(0.4)
                : Colors.grey.withOpacity(0.18),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: color)),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textMuted)),
                ],
              ),
            ),
            Radio<String>(
              value: value,
              groupValue: groupValue,
              onChanged: (_) => onTap(),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              activeColor: AppColors.primary,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Source distribution slider row ──────────────────────────────────────────

class _SrcSlider extends StatelessWidget {
  final String label;
  final String sublabel;
  final Color color;
  final int value;
  final int max;
  final void Function(int) onChanged;

  const _SrcSlider({
    required this.label,
    required this.sublabel,
    required this.color,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              label,
              style: TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 11, color: color),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sublabel,
                    style: const TextStyle(fontSize: 10, color: Colors.black54)),
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    activeTrackColor: color,
                    inactiveTrackColor: color.withOpacity(0.18),
                    thumbColor: color,
                  ),
                  child: Slider(
                    value: value.toDouble(),
                    min: 0,
                    max: max.toDouble().clamp(0, 100),
                    divisions: max > 0 ? (max ~/ 5).clamp(1, 20) : 1,
                    onChanged: max > 0 ? (v) => onChanged((v / 5).round() * 5) : null,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              '$value%',
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 12, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _TestTile extends ConsumerStatefulWidget {
  final TestModel test;
  const _TestTile({required this.test});

  @override
  ConsumerState<_TestTile> createState() => _TestTileState();
}

class _TestTileState extends ConsumerState<_TestTile> {
  bool _publishing = false;
  bool _deleting = false;

  Future<void> _togglePublish() async {
    if (widget.test.isPublished) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Unpublish Test?'),
          content: const Text(
            'Students will no longer be able to see this test. Are you sure?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Unpublish'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() => _publishing = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.publishTest(widget.test.id);
      ref.invalidate(teacherTestsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _deleteTest() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Test?'),
        content: Text(
          'Delete "${widget.test.title}"? This will also remove all grades and submissions linked to it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _deleting = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.deleteTest(widget.test.id);
      ref.invalidate(teacherTestsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final test = widget.test;
    final isOnline = test.testType == 'online';
    final accentColor = isOnline ? AppColors.secondary : AppColors.accent;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: mindForgeCardDecoration(),
      child: Column(
        children: [
          ListTile(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => TestDetailScreen(test: test)),
            ),
            leading: CircleAvatar(
              backgroundColor: accentColor.withOpacity(0.15),
              child: Icon(
                isOnline ? Icons.computer : Icons.print_outlined,
                color: accentColor,
              ),
            ),
            title: Text(test.title,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
                '${test.subject} • Grade ${test.grade} • ${test.questionCount} Qs • ${test.totalMarks.toInt()} marks',
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
            ),
            trailing: const Icon(Icons.chevron_right, size: 16, color: AppColors.textMuted),
          ),

          // ── Action bar (status + publish + delete) ────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Status label
                if (isOnline && test.expiresAt != null)
                  Text(
                    (test.isGraded || test.isExpired)
                        ? 'Completed'
                        : test.isPublished
                            ? 'Active • expires ${_expiryStr(test.expiresAt!)}'
                            : 'Draft',
                    style: TextStyle(
                      fontSize: 11,
                      color: (test.isGraded || test.isExpired)
                          ? AppColors.success
                          : test.isPublished
                              ? AppColors.success
                              : AppColors.warning,
                    ),
                  )
                else if (!isOnline)
                  Text(
                    test.isGraded
                        ? 'Completed'
                        : test.isPublished
                            ? 'Published'
                            : 'Draft',
                    style: TextStyle(
                      fontSize: 11,
                      color: test.isGraded
                          ? AppColors.success
                          : test.isPublished
                              ? AppColors.success
                              : AppColors.warning,
                    ),
                  ),

                const SizedBox(height: 6),

                // Buttons — right-aligned, always on their own row
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Publish / Unpublish — only for the creator, hidden once completed
                    if (ref.watch(authProvider).userId == test.teacherId &&
                        !(test.isGraded || test.isExpired))
                      if (_publishing)
                        const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                      else
                        OutlinedButton.icon(
                          icon: Icon(
                            test.isPublished
                                ? Icons.visibility_off
                                : Icons.publish,
                            size: 14,
                          ),
                          label: Text(
                            test.isPublished ? 'Unpublish' : 'Publish',
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            foregroundColor: test.isPublished
                                ? AppColors.error
                                : AppColors.success,
                            side: BorderSide(
                              color: test.isPublished
                                  ? AppColors.error
                                  : AppColors.success,
                            ),
                          ),
                          onPressed: _togglePublish,
                        ),

                    const SizedBox(width: 8),

                    // Delete button
                    if (_deleting)
                      const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      OutlinedButton.icon(
                        icon: const Icon(Icons.delete_outline, size: 14),
                        label: const Text('Delete',
                            style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error),
                        ),
                        onPressed: _deleteTest,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _expiryStr(DateTime dt) {
    final diff = dt.difference(DateTime.now());
    if (diff.inDays > 0) return '${diff.inDays}d';
    if (diff.inHours > 0) return '${diff.inHours}h';
    return '${diff.inMinutes}m';
  }
}
