import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/error_view.dart';
import '../providers/presentation_provider.dart';
import '../widgets/teacher_scaffold.dart';

class AutoPresentationViewScreen extends ConsumerStatefulWidget {
  final int presentationId;
  const AutoPresentationViewScreen({super.key, required this.presentationId});

  @override
  ConsumerState<AutoPresentationViewScreen> createState() =>
      _AutoPresentationViewScreenState();
}

class _AutoPresentationViewScreenState
    extends ConsumerState<AutoPresentationViewScreen> {
  late final PageController _pageCtrl = PageController();
  int _viewerIndex = 0;
  Timer? _processingPoll;

  @override
  void dispose() {
    _processingPoll?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  void _startProcessingPoll() {
    _processingPoll?.cancel();
    _processingPoll = Timer.periodic(const Duration(seconds: 4), (_) {
      ref.invalidate(presentationDetailProvider(widget.presentationId));
    });
  }

  void _stopProcessingPoll() {
    _processingPoll?.cancel();
    _processingPoll = null;
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync =
        ref.watch(presentationDetailProvider(widget.presentationId));

    return TeacherScaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Auto Presentation',
          style: GoogleFonts.poppins(
            fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white,
          ),
        ),
        backgroundColor: AppColors.primary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(
                presentationDetailProvider(widget.presentationId)),
          ),
        ],
      ),
      body: detailAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(
              presentationDetailProvider(widget.presentationId)),
        ),
        data: (data) {
          final status = data['status'] as String? ?? 'PROCESSING';
          if (status == 'PROCESSING') {
            _startProcessingPoll();
            return _ProcessingView(chapter: data['chapter_name']?.toString());
          }
          _stopProcessingPoll();
          if (status == 'FAILED') {
            return _FailedView(
              reason: data['failure_reason']?.toString(),
              onRetry: () => ref.invalidate(
                  presentationDetailProvider(widget.presentationId)),
            );
          }
          return _ReadyView(
            data: data,
            pageCtrl: _pageCtrl,
            viewerIndex: _viewerIndex,
            onPage: (i) => setState(() => _viewerIndex = i),
          );
        },
      ),
    );
  }
}

class _ProcessingView extends StatelessWidget {
  final String? chapter;
  const _ProcessingView({this.chapter});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 18),
            Text(
              'Gemini is generating slides for ${chapter ?? "this chapter"}…',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Usually finishes in 30-90 seconds. This page will refresh automatically.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 11, color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FailedView extends StatelessWidget {
  final String? reason;
  final VoidCallback onRetry;
  const _FailedView({required this.reason, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: AppColors.error, size: 40),
            const SizedBox(height: 14),
            Text(
              'Generation failed.',
              style: GoogleFonts.poppins(
                fontSize: 14, fontWeight: FontWeight.w700,
                color: AppColors.error,
              ),
            ),
            if (reason != null && reason!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                reason!,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 11, color: AppColors.textMuted,
                ),
              ),
            ],
            const SizedBox(height: 14),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadyView extends ConsumerWidget {
  final Map<String, dynamic> data;
  final PageController pageCtrl;
  final int viewerIndex;
  final ValueChanged<int> onPage;

  const _ReadyView({
    required this.data,
    required this.pageCtrl,
    required this.viewerIndex,
    required this.onPage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slides = (data['slides'] as List<dynamic>? ?? <dynamic>[])
        .cast<Map<String, dynamic>>();
    final total = data['total_slides'] as int? ?? slides.length;
    final myCurrent = data['my_current_slide_index'] as int? ?? 0;
    final myPeriods = data['my_periods_used'] as int? ?? 0;
    final recPeriods = data['recommended_periods'] as int? ?? 0;
    final defaultPerPeriod = data['default_slides_per_period'] as int? ?? 0;
    final slidesLeft = data['my_slides_left'] as int? ?? 0;
    final periodsLeft = data['my_periods_left'] as int? ?? 0;
    final perPeriodSuggested =
        data['my_slides_per_period_suggested'] as int? ?? defaultPerPeriod;

    final progressPct =
        total > 0 ? (myCurrent / total).clamp(0.0, 1.0) : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        children: [
          // ── Plan summary banner ────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primaryLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, color: Colors.amberAccent, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${data['chapter_name']}',
                        style: GoogleFonts.poppins(
                          fontSize: 14, fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Grade ${data['grade']} · ${data['subject']}',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Plan: $recPeriods × 1-hour periods · $defaultPerPeriod slides per period',
                        style: GoogleFonts.poppins(
                          fontSize: 11, color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // ── Progress bar + period log button ────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your progress',
                  style: GoogleFonts.poppins(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progressPct,
                    minHeight: 8,
                    backgroundColor: AppColors.divider,
                    valueColor: AlwaysStoppedAnimation(AppColors.primary),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$myCurrent / $total slides   ·   $myPeriods / $recPeriods periods used',
                  style: GoogleFonts.poppins(
                    fontSize: 12, color: AppColors.textPrimary,
                  ),
                ),
                if (slidesLeft > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '$periodsLeft periods left · aim for ~$perPeriodSuggested slides next period',
                    style: GoogleFonts.poppins(
                      fontSize: 11, color: AppColors.textMuted,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: () => _showPeriodLogDialog(
                    context, ref, data, viewerIndex,
                  ),
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: Text(
                    'Log this period',
                    style: GoogleFonts.poppins(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    minimumSize: const Size(double.infinity, 40),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // ── Slide viewer ───────────────────────────────────────────────
          Expanded(
            child: slides.isEmpty
                ? Center(
                    child: Text(
                      'No slides yet.',
                      style: GoogleFonts.poppins(
                          color: AppColors.textMuted, fontSize: 12),
                    ),
                  )
                : _SlideViewer(
                    slides: slides,
                    pageCtrl: pageCtrl,
                    viewerIndex: viewerIndex,
                    onPage: onPage,
                    onEditSlide: (slide) => _showEditSlideDialog(
                      context, ref, data['id'] as int, slide,
                    ),
                  ),
          ),
          // ── Period logs at the bottom ──────────────────────────────────
          const SizedBox(height: 8),
          _PeriodLogsStrip(
            logs: (data['period_logs'] as List<dynamic>? ?? <dynamic>[])
                .cast<Map<String, dynamic>>(),
          ),
        ],
      ),
    );
  }
}

class _SlideViewer extends StatelessWidget {
  final List<Map<String, dynamic>> slides;
  final PageController pageCtrl;
  final int viewerIndex;
  final ValueChanged<int> onPage;
  final void Function(Map<String, dynamic>) onEditSlide;

  const _SlideViewer({
    required this.slides,
    required this.pageCtrl,
    required this.viewerIndex,
    required this.onPage,
    required this.onEditSlide,
  });

  @override
  Widget build(BuildContext context) {
    final cur = slides[viewerIndex.clamp(0, slides.length - 1)];
    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: pageCtrl,
            itemCount: slides.length,
            onPageChanged: onPage,
            itemBuilder: (_, i) => _SlideCard(
              index: i,
              total: slides.length,
              slide: slides[i],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: viewerIndex == 0
                  ? null
                  : () => pageCtrl.previousPage(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                      ),
            ),
            Expanded(
              child: Text(
                'Slide ${viewerIndex + 1} of ${slides.length}',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 12, color: AppColors.textSecondary,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              tooltip: 'Edit slide',
              onPressed: () => onEditSlide(cur),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: viewerIndex >= slides.length - 1
                  ? null
                  : () => pageCtrl.nextPage(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                      ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SlideCard extends StatelessWidget {
  final int index;
  final int total;
  final Map<String, dynamic> slide;

  const _SlideCard({
    required this.index,
    required this.total,
    required this.slide,
  });

  @override
  Widget build(BuildContext context) {
    final title = slide['title']?.toString() ?? 'Untitled';
    final body = slide['body_md']?.toString() ?? '';
    final notes = slide['speaker_notes']?.toString() ?? '';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  '${index + 1} / $total',
                  style: GoogleFonts.poppins(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
              if ((slide['last_edited_by_username']?.toString() ?? '').isNotEmpty) ...[
                const Spacer(),
                Text(
                  'edited by ${slide['last_edited_by_username']}',
                  style: GoogleFonts.poppins(
                    fontSize: 10, color: AppColors.textMuted,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 22, fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                body,
                style: GoogleFonts.poppins(
                  fontSize: 14, color: AppColors.textPrimary,
                  height: 1.5,
                ),
              ),
            ),
          ),
          if (notes.trim().isNotEmpty) ...[
            const Divider(),
            Text(
              'SPEAKER NOTES',
              style: GoogleFonts.poppins(
                fontSize: 10, fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              notes,
              style: GoogleFonts.poppins(
                fontSize: 12, color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PeriodLogsStrip extends StatelessWidget {
  final List<Map<String, dynamic>> logs;
  const _PeriodLogsStrip({required this.logs});

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 78,
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: logs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final l = logs[i];
          final date = DateTime.tryParse(l['period_date']?.toString() ?? '');
          return Container(
            width: 150,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.iconContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  date != null ? DateFormat('MMM d').format(date) : '—',
                  style: GoogleFonts.poppins(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  l['teacher_username']?.toString() ?? '—',
                  style: GoogleFonts.poppins(
                    fontSize: 10, color: AppColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'slides ${l['slides_covered_from']}–${l['slides_covered_to']}',
                  style: GoogleFonts.poppins(
                    fontSize: 10, color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Dialogs ──────────────────────────────────────────────────────────────────

Future<void> _showPeriodLogDialog(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> data,
  int viewerIndex,
) async {
  final id = data['id'] as int;
  final total = data['total_slides'] as int? ?? 0;
  final myCurrent = data['my_current_slide_index'] as int? ?? 0;
  // Default to the slide currently displayed in the viewer, or the suggested
  // end of next period, whichever is larger.
  final suggested = (data['my_slides_per_period_suggested'] as int? ?? 0);
  int slidesCoveredTo = (viewerIndex + 1).clamp(
    myCurrent,
    total > 0 ? total : 0,
  );
  if (slidesCoveredTo < myCurrent + suggested && suggested > 0) {
    slidesCoveredTo =
        (myCurrent + suggested).clamp(myCurrent, total > 0 ? total : 0);
  }
  final notesCtrl = TextEditingController();
  bool submitting = false;

  await showDialog<void>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (ctx, setSt) => AlertDialog(
        title: Text(
          'Log period',
          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How many slides did you teach today?',
              style: GoogleFonts.poppins(fontSize: 12),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove),
                  onPressed: slidesCoveredTo <= myCurrent
                      ? null
                      : () => setSt(() => slidesCoveredTo--),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      'Cover up to slide $slidesCoveredTo of $total',
                      style: GoogleFonts.poppins(
                        fontSize: 14, fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: slidesCoveredTo >= total
                      ? null
                      : () => setSt(() => slidesCoveredTo++),
                ),
              ],
            ),
            Text(
              'You were at slide $myCurrent before this period.',
              style: GoogleFonts.poppins(
                fontSize: 11, color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesCtrl,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: submitting ? null : () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: submitting
                ? null
                : () async {
                    setSt(() => submitting = true);
                    try {
                      final api = ref.read(apiClientProvider);
                      final today = DateFormat('yyyy-MM-dd')
                          .format(DateTime.now());
                      await api.logPresentationPeriod(
                        id,
                        periodDate: today,
                        slidesCoveredTo: slidesCoveredTo,
                        notes: notesCtrl.text.trim().isEmpty
                            ? null
                            : notesCtrl.text.trim(),
                      );
                      ref.invalidate(presentationDetailProvider(id));
                      ref.invalidate(presentationListProvider);
                      if (ctx.mounted) Navigator.pop(ctx);
                    } on DioException catch (e) {
                      final body = e.response?.data;
                      final msg = body is Map && body['detail'] is String
                          ? body['detail'] as String
                          : 'Failed to log period.';
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text(msg),
                            backgroundColor: AppColors.error),
                      );
                      setSt(() => submitting = false);
                    } catch (e) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text('Error: $e'),
                            backgroundColor: AppColors.error),
                      );
                      setSt(() => submitting = false);
                    }
                  },
            child: submitting
                ? const SizedBox(
                    height: 16, width: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white,
                    ),
                  )
                : const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _showEditSlideDialog(
  BuildContext context,
  WidgetRef ref,
  int presentationId,
  Map<String, dynamic> slide,
) async {
  final titleCtrl =
      TextEditingController(text: slide['title']?.toString() ?? '');
  final bodyCtrl =
      TextEditingController(text: slide['body_md']?.toString() ?? '');
  final notesCtrl =
      TextEditingController(text: slide['speaker_notes']?.toString() ?? '');
  bool submitting = false;

  await showDialog<void>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (ctx, setSt) => AlertDialog(
        title: Text(
          'Edit slide',
          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: bodyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Body (markdown)',
                  ),
                  maxLines: 6,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: notesCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Speaker notes'),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: submitting ? null : () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: submitting
                ? null
                : () async {
                    setSt(() => submitting = true);
                    try {
                      final api = ref.read(apiClientProvider);
                      await api.patchPresentationSlide(
                        presentationId,
                        slide['id'] as int,
                        title: titleCtrl.text.trim(),
                        bodyMd: bodyCtrl.text,
                        speakerNotes: notesCtrl.text,
                      );
                      ref.invalidate(presentationDetailProvider(presentationId));
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text('Save failed: $e'),
                            backgroundColor: AppColors.error),
                      );
                      setSt(() => submitting = false);
                    }
                  },
            child: submitting
                ? const SizedBox(
                    height: 16, width: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white,
                    ),
                  )
                : const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
