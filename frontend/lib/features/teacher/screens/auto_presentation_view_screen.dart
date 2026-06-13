import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/constants.dart';
import '../../../core/widgets/error_view.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/presentation_provider.dart';
import '../widgets/teacher_scaffold.dart';

// ── Grade colour palette ─────────────────────────────────────────────────────
// Same hues the dashboard's Today's Workflow card uses for grade pills, so
// the presentation viewer feels like part of the same colour-coded system.

const _grade8Color = Color(0xFF3B82F6); // blue
const _grade9Color = Color(0xFF8B5CF6); // purple
const _grade10Color = Color(0xFFF97316); // orange

Color _gradeColor(int? grade) {
  switch (grade) {
    case 8:
      return _grade8Color;
    case 9:
      return _grade9Color;
    case 10:
      return _grade10Color;
    default:
      return AppColors.primary;
  }
}

/// Slightly lighter variant used as the second stop in gradients.
Color _gradeColorLight(int? grade) =>
    Color.lerp(_gradeColor(grade), Colors.white, 0.25)!;

String _subjectEmoji(String? subject) {
  final s = (subject ?? '').toLowerCase();
  if (s.contains('phys')) return '⚛️';
  if (s.contains('chem')) return '🧪';
  if (s.contains('bio')) return '🌿';
  if (s.contains('math')) return '🔢';
  if (s.contains('hist') || s.contains('civic')) return '🏛️';
  if (s.contains('geo')) return '🌍';
  if (s.contains('eco')) return '💹';
  if (s.contains('comp') || s.contains('ai')) return '💻';
  if (s.contains('eng')) return '📖';
  if (s.contains('env')) return '🌱';
  return '📚';
}

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

  /// Delete this presentation (uploader/admin only on the backend) and return
  /// to the dashboard list. Used to clear out a deck whose generation failed.
  Future<void> _deletePresentation(String? chapter) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete presentation?'),
        content: Text(
          '"${chapter ?? 'This presentation'}" will be permanently deleted.',
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

    _stopProcessingPoll();
    try {
      await ref.read(apiClientProvider).deletePresentation(widget.presentationId);
      try { ref.invalidate(presentationListProvider); } catch (_) {}
      try { ref.invalidate(presentationLibraryProvider); } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted "${chapter ?? 'presentation'}".')),
      );
      context.go('${RouteNames.teacherDashboard}/presentations');
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
              onDelete: () =>
                  _deletePresentation(data['chapter_name']?.toString()),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(
                presentationDetailProvider(widget.presentationId)),
            child: _ReadyView(
              data: data,
              pageCtrl: _pageCtrl,
              viewerIndex: _viewerIndex,
              onPage: (i) => setState(() => _viewerIndex = i),
            ),
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
  final VoidCallback onDelete;
  const _FailedView({
    required this.reason,
    required this.onRetry,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 40),
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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                  onPressed: onRetry,
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                  ),
                  onPressed: onDelete,
                ),
              ],
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
    final myAdopted = data['my_adopted'] as bool? ?? false;
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
    final presentationId = data['id'] as int;
    final grade = data['grade'] as int?;
    final subject = data['subject']?.toString();
    final gColor = _gradeColor(grade);
    final gColorLight = _gradeColorLight(grade);
    final emoji = _subjectEmoji(subject);

    // Give the slide a generous, screen-proportional height and let the WHOLE
    // page scroll, so a full slide is visible instead of being squeezed into
    // whatever space is left between the banner, progress card and the
    // period-logs strip.
    final slideViewerHeight =
        (MediaQuery.of(context).size.height * 0.72).clamp(420.0, 760.0);

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        children: [
          // ── Plan summary banner ────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [gColor, gColorLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: gColor.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${data['chapter_name']}',
                        style: GoogleFonts.poppins(
                          fontSize: 15, fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Grade ${data['grade']} · ${data['subject']}',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _BannerStat(
                            icon: '⏱️',
                            label: '$recPeriods periods',
                          ),
                          const SizedBox(width: 6),
                          _BannerStat(
                            icon: '🎯',
                            label: '$defaultPerPeriod / period',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // ── Progress card OR adopt prompt ───────────────────────────────
          // Uniform border + ClipRRect + inner 4-px stripe avoid Flutter's
          // "non-uniform Border + BorderRadius silently drops children"
          // bug (which left this box blank on Flutter web).
          Container(
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: gColor.withValues(alpha: 0.18)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: 4, color: gColor),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                        child: myAdopted
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('📈',
                              style: TextStyle(fontSize: 14)),
                          const SizedBox(width: 6),
                          Text(
                            'YOUR PROGRESS',
                            style: GoogleFonts.poppins(
                              fontSize: 11, fontWeight: FontWeight.w800,
                              color: gColor,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progressPct,
                          minHeight: 10,
                          backgroundColor: gColor.withValues(alpha: 0.12),
                          valueColor: AlwaysStoppedAnimation(gColor),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$myCurrent / $total slides   ·   $myPeriods / $recPeriods periods used',
                        style: GoogleFonts.poppins(
                          fontSize: 12, color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
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
                        icon: const Icon(Icons.check_circle_outline,
                            size: 16),
                        label: Text(
                          'Log this period',
                          style: GoogleFonts.poppins(
                              fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: gColor,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 42),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => _unadoptThisDeck(
                            context, ref, presentationId,
                          ),
                          icon: const Icon(Icons.remove_circle_outline,
                              size: 15),
                          label: Text(
                            'Remove from my dashboard',
                            style: GoogleFonts.poppins(
                                fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.error,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 0),
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('🪧',
                              style: TextStyle(fontSize: 14)),
                          const SizedBox(width: 6),
                          Text(
                            'NOT ON YOUR DASHBOARD',
                            style: GoogleFonts.poppins(
                              fontSize: 11, fontWeight: FontWeight.w800,
                              color: gColor,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'You can browse this deck without adopting it. '
                        'Adopt it for your class to track progress and log '
                        'periods.',
                        style: GoogleFonts.poppins(
                          fontSize: 12, color: AppColors.textPrimary,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: () => _adoptThisDeck(context, ref, presentationId),
                        icon: const Icon(Icons.add_to_photos_outlined,
                            size: 16),
                        label: Text(
                          'Adopt for my class',
                          style: GoogleFonts.poppins(
                              fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: gColor,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 42),
                        ),
                      ),
                    ],
                  ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // ── Slide viewer ───────────────────────────────────────────────
          SizedBox(
            height: slideViewerHeight,
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
                    accentColor: gColor,
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
            currentTeacherId: ref.watch(authProvider).userId,
            onEdit: (log) => _showEditPeriodLogDialog(
              context, ref, presentationId, log, total,
            ),
          ),
        ],
      ),
    );
  }
}

class _BannerStat extends StatelessWidget {
  final String icon;
  final String label;
  const _BannerStat({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 10.5, color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
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
  final Color accentColor;

  const _SlideViewer({
    required this.slides,
    required this.pageCtrl,
    required this.viewerIndex,
    required this.onPage,
    required this.onEditSlide,
    required this.accentColor,
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
              accentColor: accentColor,
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
        Center(
          child: TextButton.icon(
            icon: const Icon(Icons.fullscreen, size: 18),
            label: Text(
              'View fullscreen',
              style: GoogleFonts.poppins(
                fontSize: 12, fontWeight: FontWeight.w600,
              ),
            ),
            style: TextButton.styleFrom(foregroundColor: accentColor),
            onPressed: () => Navigator.of(context).push(
              PageRouteBuilder(
                opaque: true,
                barrierColor: Colors.black,
                fullscreenDialog: true,
                transitionDuration: const Duration(milliseconds: 180),
                pageBuilder: (_, __, ___) => _FullscreenSlideOverlay(
                  slides: slides,
                  initialIndex: viewerIndex,
                  accentColor: accentColor,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Fullscreen overlay ───────────────────────────────────────────────────────
//
// Modal route that fills the whole viewport with a single slide at a time.
// Reuses _SlideCard so the look is identical to the inline viewer, just
// scaled up to the available width/height. Prev/next arrows + a close X
// in the corner. Keyboard ←/→/Esc also navigate / dismiss.

class _FullscreenSlideOverlay extends StatefulWidget {
  final List<Map<String, dynamic>> slides;
  final int initialIndex;
  final Color accentColor;

  const _FullscreenSlideOverlay({
    required this.slides,
    required this.initialIndex,
    required this.accentColor,
  });

  @override
  State<_FullscreenSlideOverlay> createState() =>
      _FullscreenSlideOverlayState();
}

class _FullscreenSlideOverlayState extends State<_FullscreenSlideOverlay> {
  late PageController _ctrl;
  late int _idx;
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _idx = widget.initialIndex;
    _ctrl = PageController(initialPage: _idx);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final target = (_idx + delta).clamp(0, widget.slides.length - 1);
    if (target == _idx) return;
    _ctrl.animateToPage(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
      _go(1);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _go(-1);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.slides.length;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 56, 24, 64),
                child: PageView.builder(
                  controller: _ctrl,
                  itemCount: total,
                  onPageChanged: (i) => setState(() => _idx = i),
                  itemBuilder: (_, i) => _SlideCard(
                    index: i,
                    total: total,
                    slide: widget.slides[i],
                    accentColor: widget.accentColor,
                  ),
                ),
              ),
              Positioned(
                top: 12, right: 12,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  tooltip: 'Exit fullscreen',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
              Positioned(
                left: 0, top: 0, bottom: 0,
                child: Center(
                  child: IconButton(
                    iconSize: 36,
                    icon: const Icon(Icons.chevron_left, color: Colors.white70),
                    onPressed: _idx == 0 ? null : () => _go(-1),
                  ),
                ),
              ),
              Positioned(
                right: 0, top: 0, bottom: 0,
                child: Center(
                  child: IconButton(
                    iconSize: 36,
                    icon: const Icon(Icons.chevron_right, color: Colors.white70),
                    onPressed: _idx >= total - 1 ? null : () => _go(1),
                  ),
                ),
              ),
              Positioned(
                bottom: 16, left: 0, right: 0,
                child: Center(
                  child: Text(
                    'Slide ${_idx + 1} of $total   ·   Esc to exit',
                    style: GoogleFonts.poppins(
                      fontSize: 12, color: Colors.white60,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlideBody extends StatelessWidget {
  final String markdown;
  final Color accentColor;
  const _SlideBody({required this.markdown, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    // Gemini's body_md is "- bullet\n- bullet\n…" markdown. Render it as a
    // proper bullet column instead of dumping raw markdown into a Text() —
    // a single long unwrapped line was painting Flutter's yellow-and-black
    // overflow indicator over the slide.
    final raw = markdown.trim();
    if (raw.isEmpty) return const SizedBox.shrink();

    final lines = raw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final blocks = <Widget>[];
    for (final line in lines) {
      String text = line;
      bool bullet = false;
      // Strip common markdown bullet markers
      if (text.startsWith('- ') || text.startsWith('* ')) {
        text = text.substring(2);
        bullet = true;
      } else if (RegExp(r'^\d+[.)]\s').hasMatch(text)) {
        // Numbered list — keep the number but treat as bullet for layout
        bullet = true;
      } else if (text.startsWith('#')) {
        // Drop headings — the slide already has a title
        text = text.replaceAll(RegExp(r'^#+\s*'), '');
      }
      // Strip a few inline markdown markers so they don't appear as raw chars.
      text = text
          .replaceAll(RegExp(r'\*\*(.*?)\*\*'), r'$1')
          .replaceAll(RegExp(r'\*(.*?)\*'), r'$1')
          .replaceAll(RegExp(r'`(.*?)`'), r'$1');

      blocks.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (bullet) ...[
              Padding(
                padding: const EdgeInsets.only(top: 7, right: 8),
                child: Container(
                  width: 7, height: 7,
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
            Expanded(
              child: Text(
                text,
                softWrap: true,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: blocks,
    );
  }
}

class _SlideCard extends StatelessWidget {
  final int index;
  final int total;
  final Map<String, dynamic> slide;
  final Color accentColor;

  const _SlideCard({
    required this.index,
    required this.total,
    required this.slide,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final title = slide['title']?.toString() ?? 'Untitled';
    final body = slide['body_md']?.toString() ?? '';
    final notes = slide['speaker_notes']?.toString() ?? '';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Coloured top accent strip — visual hook that ties the slide
          // card to the grade-coloured banner.
          Container(
            height: 6,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accentColor,
                  Color.lerp(accentColor, Colors.white, 0.4)!,
                ],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Slide ${index + 1} of $total',
                    style: GoogleFonts.poppins(
                      fontSize: 11, fontWeight: FontWeight.w800,
                      color: accentColor,
                    ),
                  ),
                ),
                if ((slide['last_edited_by_username']?.toString() ?? '').isNotEmpty) ...[
                  const Spacer(),
                  Text(
                    '✏️  ${slide['last_edited_by_username']}',
                    style: GoogleFonts.poppins(
                      fontSize: 10, color: AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 22, fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Body + speaker notes share ONE scrollable region. The card can be
          // squeezed very short (the viewer competes with the banner, progress
          // bar and period-logs strip), so anything variable must live inside a
          // single scroll view — otherwise the fixed chrome (title + divider +
          // notes header) alone overflows the card. Notes scroll inline below
          // the body rather than being pinned.
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SlideBody(markdown: body, accentColor: accentColor),
                  if (notes.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Divider(color: accentColor.withValues(alpha: 0.2)),
                    Row(
                      children: [
                        const Text('🎤', style: TextStyle(fontSize: 12)),
                        const SizedBox(width: 6),
                        Text(
                          'SPEAKER NOTES',
                          style: GoogleFonts.poppins(
                            fontSize: 10, fontWeight: FontWeight.w800,
                            color: accentColor,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
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
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodLogsStrip extends StatelessWidget {
  final List<Map<String, dynamic>> logs;
  // The viewing teacher — only their own logs get an edit affordance.
  final int? currentTeacherId;
  final void Function(Map<String, dynamic> log) onEdit;
  const _PeriodLogsStrip({
    required this.logs,
    required this.currentTeacherId,
    required this.onEdit,
  });

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
          final canEdit = currentTeacherId != null &&
              l['teacher_id'] == currentTeacherId;
          return InkWell(
            onTap: canEdit ? () => onEdit(l) : null,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 150,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.iconContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        date != null ? DateFormat('MMM d').format(date) : '—',
                        style: GoogleFonts.poppins(
                          fontSize: 11, fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      if (canEdit) ...[
                        const Spacer(),
                        const Icon(Icons.edit_outlined,
                            size: 13, color: AppColors.textMuted),
                      ],
                    ],
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
            ),
          );
        },
      ),
    );
  }
}

// ── Adopt + dialogs ──────────────────────────────────────────────────────────

Future<void> _adoptThisDeck(
  BuildContext context, WidgetRef ref, int presentationId,
) async {
  try {
    final api = ref.read(apiClientProvider);
    await api.adoptPresentation(presentationId);
    // Refresh the open detail screen so it flips to "adopted" mode, plus
    // the dashboard list and the library tab where adopter counts live.
    ref.invalidate(presentationDetailProvider(presentationId));
    try { ref.invalidate(presentationListProvider); } catch (_) {}
    try { ref.invalidate(presentationLibraryProvider); } catch (_) {}
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Added to your dashboard.')),
    );
  } on DioException catch (e) {
    final body = e.response?.data;
    final msg = body is Map && body['detail'] is String
        ? body['detail'] as String
        : 'Adopt failed: ${e.response?.statusCode ?? '?'}';
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Adopt failed: $e'),
          backgroundColor: AppColors.error),
    );
  }
}

Future<void> _unadoptThisDeck(
  BuildContext context, WidgetRef ref, int presentationId,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        'Remove from dashboard?',
        style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      content: Text(
        'This deck will be taken off your dashboard and your period logs '
        'for it will be cleared. The presentation itself stays in the '
        'library, and you can adopt it again later.',
        style: GoogleFonts.poppins(fontSize: 12, height: 1.35),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  try {
    final api = ref.read(apiClientProvider);
    await api.unadoptPresentation(presentationId);
    ref.invalidate(presentationDetailProvider(presentationId));
    try { ref.invalidate(presentationListProvider); } catch (_) {}
    try { ref.invalidate(presentationLibraryProvider); } catch (_) {}
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Removed from your dashboard.')),
    );
  } on DioException catch (e) {
    final body = e.response?.data;
    final msg = body is Map && body['detail'] is String
        ? body['detail'] as String
        : 'Remove failed: ${e.response?.statusCode ?? '?'}';
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Remove failed: $e'),
          backgroundColor: AppColors.error),
    );
  }
}

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
                      // A quiz is auto-generated for any newly-covered slides;
                      // point the teacher at the Tests tab to watch progress.
                      if (slidesCoveredTo > myCurrent && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Quiz is generating from your slides — '
                                'check the Tests tab.'),
                          ),
                        );
                      }
                    } on DioException catch (e) {
                      final body = e.response?.data;
                      final msg = body is Map && body['detail'] is String
                          ? body['detail'] as String
                          : 'Failed to log period.';
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text(msg),
                              backgroundColor: AppColors.error),
                        );
                      }
                      setSt(() => submitting = false);
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text('Error: $e'),
                              backgroundColor: AppColors.error),
                        );
                      }
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

/// Edit a previously-logged period. Corrects the record only — unlike logging
/// a new period this never generates an online test.
Future<void> _showEditPeriodLogDialog(
  BuildContext context,
  WidgetRef ref,
  int presentationId,
  Map<String, dynamic> log,
  int total,
) async {
  final logId = log['id'] as int;
  // The period's starting slide is fixed; only its end is editable, and it
  // can't drop below where the period began.
  final slidesFrom = log['slides_covered_from'] as int? ?? 0;
  int slidesCoveredTo = (log['slides_covered_to'] as int? ?? slidesFrom)
      .clamp(slidesFrom, total > 0 ? total : slidesFrom);
  final notesCtrl =
      TextEditingController(text: log['notes']?.toString() ?? '');
  bool submitting = false;

  await showDialog<void>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (ctx, setSt) => AlertDialog(
        title: Text(
          'Edit period log',
          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How many slides did this period cover?',
              style: GoogleFonts.poppins(fontSize: 12),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove),
                  onPressed: slidesCoveredTo <= slidesFrom
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
              'This period started at slide $slidesFrom.',
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
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.info_outline, size: 13, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Editing updates this log only — it won\'t generate a new quiz.',
                    style: GoogleFonts.poppins(
                      fontSize: 10.5, color: AppColors.textMuted,
                    ),
                  ),
                ),
              ],
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
                      await api.updatePresentationPeriodLog(
                        presentationId,
                        logId,
                        slidesCoveredTo: slidesCoveredTo,
                        // Always sent (even empty) so notes can be cleared.
                        notes: notesCtrl.text.trim(),
                      );
                      ref.invalidate(
                          presentationDetailProvider(presentationId));
                      ref.invalidate(presentationListProvider);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Period log updated.')),
                        );
                      }
                    } on DioException catch (e) {
                      final body = e.response?.data;
                      final msg = body is Map && body['detail'] is String
                          ? body['detail'] as String
                          : 'Failed to update period log.';
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text(msg),
                              backgroundColor: AppColors.error),
                        );
                      }
                      setSt(() => submitting = false);
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text('Error: $e'),
                              backgroundColor: AppColors.error),
                        );
                      }
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
                : const Text('Save changes'),
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
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text('Save failed: $e'),
                              backgroundColor: AppColors.error),
                        );
                      }
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
