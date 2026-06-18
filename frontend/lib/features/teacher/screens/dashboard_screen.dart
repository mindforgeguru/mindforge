import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/models/grade.dart';

import '../../../core/api/websocket_client.dart';
import '../../../core/models/homework.dart';
import '../../../core/models/timetable.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/constants.dart';
import '../../../core/utils/logout_confirm.dart';
import '../../../core/widgets/report_problem_dialog.dart';
import '../../../core/widgets/holiday_banner.dart';
import '../../../core/providers/badge_provider.dart';
import '../../../core/widgets/badge_dot.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/teacher_provider.dart';
import '../providers/presentation_provider.dart';
import '../widgets/teacher_scaffold.dart';

// File-level DateFormat cache.
final _fmtYMD   = DateFormat('yyyy-MM-dd');
final _fmtEDMon = DateFormat('EEE, d MMM');
final _fmtDMon  = DateFormat('d MMM');

// Responsive scale helper — base ref width 390 px
double _s(BuildContext ctx, double base, {double min = 0, double max = double.infinity}) {
  final w = MediaQuery.of(ctx).size.width;
  final scaled = base * (w / 390.0);
  return scaled.clamp(min == 0 ? base * 0.75 : min, max == double.infinity ? base * 1.4 : max);
}

double _fs(BuildContext ctx, double base, {double min = 10, double max = 22}) =>
    _s(ctx, base, min: min, max: max);

class TeacherDashboardScreen extends ConsumerStatefulWidget {
  const TeacherDashboardScreen({super.key});

  @override
  ConsumerState<TeacherDashboardScreen> createState() =>
      _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState
    extends ConsumerState<TeacherDashboardScreen>
    with WidgetsBindingObserver {
  StreamSubscription<Map<String, dynamic>>? _wsSub;

  // Safety net for the post-login race: even with the provider-level wait
  // on the auth token, some sessions still surface a transient error on
  // first load (WebSocket reconnect spam, browser back/forward, etc.).
  // Auto-retry once before showing the error UI.
  bool _autoRetryScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _connectWs());
  }

  // Debounce brief resume/pause flaps from notifications or system overlays.
  DateTime? _lastPausedAt;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb) return;
    if (state == AppLifecycleState.paused) {
      _lastPausedAt = DateTime.now();
      return;
    }
    if (state != AppLifecycleState.resumed || !mounted) return;
    final pausedFor = _lastPausedAt == null
        ? Duration.zero
        : DateTime.now().difference(_lastPausedAt!);
    if (pausedFor < const Duration(seconds: 30)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _wsSub?.cancel();
      ref.read(webSocketClientProvider).forceReconnect();
      _connectWs();
      ref.invalidate(teacherDashboardSummaryProvider);
      ref.invalidate(teacherTodayWorkflowProvider);
    });
  }

  void _connectWs() {
    final auth = ref.read(authProvider);
    final userId = auth.userId;
    final token = auth.token;
    if (userId == null || token == null) return;
    final ws = ref.read(webSocketClientProvider);
    _wsSub = ws.connect(userId, token).listen((event) {
      if (!mounted) return;
      final eventType = event['event'] as String?;
      if (eventType == 'profile_updated') {
        _showProfileUpdatedDialog(event['new_username'] as String?);
      } else if (eventType != null) {
        ref.invalidate(teacherDashboardSummaryProvider);
        if (eventType == 'attendance_updated' ||
            eventType == 'homework_added' ||
            eventType == 'homework_completion_updated' ||
            eventType == 'timetable_updated') {
          ref.invalidate(teacherTodayWorkflowProvider);
        }
      }
    });
  }

  Future<void> _refreshDashboard() async {
    ref.invalidate(teacherDashboardSummaryProvider);
    ref.invalidate(teacherTodayWorkflowProvider);
    await ref
        .read(teacherDashboardSummaryProvider.future)
        .catchError((_) => <String, dynamic>{});
  }

  Future<void> _showProfileUpdatedDialog(String? newUsername) async {
    await showDialog<void>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Account Updated'),
        content: Text(newUsername != null
            ? 'Your username has been changed to "$newUsername" by the admin. Please log in again.'
            : 'Your account details have been updated. Please log in again.'),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(authProvider.notifier).logout();
            },
            child: const Text('Log In Again'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wsSub?.cancel();
    super.dispose();
  }

  String get _todayString => _fmtYMD.format(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final summaryAsync = ref.watch(teacherDashboardSummaryProvider);

    // Reset the auto-retry flag on success so a transient failure later
    // in the session (backend hiccup, brief disconnect) can also self-heal
    // once instead of dumping the user to "Try Again".
    if (summaryAsync.hasValue) {
      _autoRetryScheduled = false;
    }

    // ── Error state: show retry UI instead of silently blank sections ─────
    if (summaryAsync.hasError) {
      // First failure → log the underlying error to DevTools, schedule a
      // single auto-retry, and show a spinner instead of the error UI.
      if (!_autoRetryScheduled) {
        _autoRetryScheduled = true;
        debugPrint('[dashboard] first load failed, auto-retrying once. '
            'Error: ${summaryAsync.error}');
        Future.delayed(const Duration(milliseconds: 900), () {
          if (!mounted) return;
          ref.invalidate(teacherDashboardSummaryProvider);
          ref.invalidate(teacherTodayWorkflowProvider);
        });
        return const TeacherScaffold(
          backgroundColor: AppColors.background,
          body: Center(child: CircularProgressIndicator()),
        );
      }
      // Second failure → surface to user.
      debugPrint('[dashboard] retry also failed: ${summaryAsync.error}');
      return TeacherScaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 52,
                    color: AppColors.textMuted),
                const SizedBox(height: 16),
                Text(
                  'Could not load dashboard',
                  style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'The server may be starting up.\nPlease wait a moment and try again.',
                  style: GoogleFonts.poppins(
                      fontSize: 13, color: AppColors.textMuted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _refreshDashboard,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Try Again'),
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Broadcast badge — select() so this boolean is only recomputed when
    // broadcasts or lastSeen actually change, not on every dashboard rebuild.
    final lastSeenBroadcast = ref.watch(teacherBroadcastBadgeNotifier);
    final hasBroadcastBadge = ref.watch(
      teacherDashboardSummaryProvider.select((async) =>
        async.maybeWhen(
          data: (summary) {
            final raw = (summary['broadcasts'] as List<dynamic>? ?? []);
            if (raw.isEmpty) return false;
            DateTime? latest;
            for (final b in raw) {
              final createdAt = DateTime.parse(
                  (b as Map<String, dynamic>)['created_at'] as String);
              if (latest == null || createdAt.isAfter(latest)) latest = createdAt;
            }
            return latest != null &&
                (lastSeenBroadcast == null || latest.isAfter(lastSeenBroadcast));
          },
          orElse: () => false,
        )),
    );

    final mq = MediaQuery.of(context);
    final topPadding = mq.padding.top;
    final screenWidth = mq.size.width;
    final screenHeight = mq.size.height;

    // Filter today's slots from the summary timetable data
    final todaySlots = summaryAsync.maybeWhen(
      data: (summary) {
        final raw = (summary['my_timetable'] as List<dynamic>? ?? []);
        return raw
            .map((e) => TimetableSlotModel.fromJson(e as Map<String, dynamic>))
            .where((s) => s.slotDate == _todayString)
            .toList();
      },
      orElse: () => <TimetableSlotModel>[],
    );

    // Whole-school holiday flag, derived from the grade-wide workflow data.
    // The summary's my_timetable is filtered by teacher_id and a holiday
    // marker carries none, so it never reaches the teacher — the workflow
    // endpoint is the reliable source. True when every grade with today's
    // timetable filled in is a holiday.
    final isSchoolHoliday =
        ref.watch(teacherTodayWorkflowProvider).maybeWhen(
      data: (data) {
        final grades =
            (data['grades'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
        final withTimetable =
            grades.where((g) => g['timetable_created'] == true).toList();
        return withTimetable.isNotEmpty &&
            withTimetable.every((g) => g['is_holiday'] == true);
      },
      orElse: () => false,
    );

    final subjects = summaryAsync.maybeWhen(
      data: (summary) {
        final raw = (summary['my_timetable'] as List<dynamic>? ?? []);
        return raw
            .map((e) =>
                TimetableSlotModel.fromJson(e as Map<String, dynamic>).subject)
            .whereType<String>()
            .map((s) => s.trim())
            // Drop blank subjects (e.g. holiday markers carry subject: '').
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
      },
      orElse: () => <String>[],
    );

    // Responsive layout values
    final double avatarRadius = (screenWidth * 0.114).clamp(36.0, 50.0);
    final double cardRadius = (screenWidth * 0.062).clamp(20.0, 28.0);
    final double cardHMargin = (screenWidth * 0.04).clamp(12.0, 20.0);
    final double cardIntoNavy = (screenHeight * 0.066).clamp(44.0, 60.0);

    // Responsive logo / text sizes for header (logoH governs how far the
    // MIND FORGE wordmark extends down, so it's needed before navyH).
    final double logoH = (screenWidth * 0.142).clamp(42.0, 58.0);
    final double titleFs = (screenWidth * 0.062).clamp(18.0, 25.0);

    // Navy hero height. On a wide-but-short web viewport the proportional
    // value collapses to its minimum while the wordmark stays tall, which let
    // the overlapping avatar ride up into the branding. Floor navyH so the
    // avatar's top (navyH − cardIntoNavy) always clears the wordmark.
    final double brandingBottom = topPadding + 16 + logoH;
    final double navyH = topPadding +
        math.max((screenHeight * 0.165).clamp(95.0, 142.0),
            brandingBottom + cardIntoNavy + 10 - topPadding);
    // Smaller fonts → less height needed. The extra buffer keeps a 2–3 row
    // subject list from overflowing the fixed header height onto the workflow
    // card below.
    final double cardInternalH = subjects.isEmpty
        ? (avatarRadius + 90).clamp(128.0, 155.0)
        : (avatarRadius + 132).clamp(168.0, 215.0);
    final double headerH = navyH + cardInternalH - cardIntoNavy + avatarRadius;

    // Web + mobile use the same sliver-based layout below — same navy hero
    // with MIND FORGE branding + overlapping avatar + "Welcome back" card
    // that the student dashboard uses. TeacherScaffold caps the body at
    // 600 px on web, so it reads as a phone-shaped centred column.
    // (The earlier custom web hero with stat tiles is intentionally retired
    // so all three roles look the same on web.)

    return TeacherScaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: _refreshDashboard,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
          // ── Header ───────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: SizedBox(
              height: headerH,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Navy curved background
                  Positioned(
                    top: 0, left: 0, right: 0,
                    child: Container(
                      height: navyH,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(
                              (screenWidth * 0.113).clamp(36.0, 48.0)),
                          bottomRight: Radius.circular(
                              (screenWidth * 0.113).clamp(36.0, 48.0)),
                        ),
                      ),
                    ),
                  ),

                  // ── Logo + wordmark + tagline ────────────────────────
                  Positioned(
                    top: topPadding + _s(context, 16, min: 10, max: 22),
                    left: 0,
                    right: 0,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              height: logoH,
                              width: logoH,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(logoH * 0.15),
                              ),
                              padding: EdgeInsets.all(logoH * 0.08),
                              child: Image.asset(
                                'assets/images/logo.png',
                                fit: BoxFit.contain,
                              ),
                            ),
                            SizedBox(width: _s(context, 10, min: 6, max: 14)),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'MIND FORGE',
                                  style: GoogleFonts.poppins(
                                    fontSize: titleFs,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: 1.2,
                                    height: 1,
                                  ),
                                ),
                                SizedBox(height: _s(context, 3, min: 2, max: 5)),
                                Text(
                                  'AI Assisted Learning',
                                  style: GoogleFonts.poppins(
                                    fontSize: (screenWidth * 0.040).clamp(13.0, 16.0),
                                    fontWeight: FontWeight.w400,
                                    color: Colors.white.withValues(alpha: 0.72),
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Report a problem moved to a small button at the bottom of
                  // the page (see the _ReportProblemButton below the content)
                  // so it no longer crowds the centred MIND FORGE wordmark.

                  // ── Logout icon — min 48×48 tap target ───────────────
                  Positioned(
                    top: topPadding + _s(context, 10, min: 6, max: 14),
                    right: _s(context, 4, min: 2, max: 8),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: IconButton(
                        icon: Icon(Icons.logout,
                            color: Colors.white,
                            size: _s(context, 22, min: 18, max: 26)),
                        onPressed: () => confirmLogout(context, ref),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ),

                  // White profile card
                  Positioned(
                    top: navyH - cardIntoNavy,
                    left: cardHMargin,
                    right: cardHMargin,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.topCenter,
                      children: [
                        Container(
                          width: double.infinity,
                          margin: EdgeInsets.only(top: avatarRadius),
                          padding: EdgeInsets.fromLTRB(
                            _s(context, 20, min: 14, max: 28),
                            avatarRadius + _s(context, 10, min: 8, max: 14),
                            _s(context, 20, min: 14, max: 28),
                            _s(context, 18, min: 12, max: 24),
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(cardRadius),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'Welcome back, ${auth.username ?? 'Teacher'}',
                                  style: GoogleFonts.poppins(
                                      fontSize: _fs(context, 14, min: 12, max: 17),
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              SizedBox(height: _s(context, 8, min: 6, max: 10)),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                alignment: WrapAlignment.center,
                                children: [
                                  const _Badge(label: 'TEACHER'),
                                  ...subjects.whereType<String>().map((s) => _SubjectChip(subject: s)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          top: 0,
                          child: GestureDetector(
                            onTap: () => context.go(
                                '${RouteNames.teacherDashboard}/profile'),
                            child: Stack(
                              alignment: Alignment.bottomRight,
                              children: [
                                _ProfileAvatar(
                                  username: auth.username ?? 'T',
                                  photoUrl: auth.profilePicUrl,
                                  radius: avatarRadius,
                                ),
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration:       BoxDecoration(
                                    color: AppColors.accent,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.edit,
                                      size: 12, color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Today's workflow card ─────────────────────────────────────
          SliverToBoxAdapter(
              child: SizedBox(height: _s(context, 12, min: 8, max: 16))),
          const SliverToBoxAdapter(
            child: _DashSectionHeader(
              icon: Icons.map_outlined,
              title: "Today's Workflow",
            ),
          ),
          SliverToBoxAdapter(
            child: Consumer(
              builder: (context, ref, _) {
                final workflowAsync = ref.watch(teacherTodayWorkflowProvider);
                return workflowAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (data) => _TodayWorkflowCard(data: data),
                );
              },
            ),
          ),

          // ── Presentation progress (school-wide) ───────────────────────
          SliverToBoxAdapter(
            child: _DashSectionHeader(
              icon: Icons.slideshow_outlined,
              title: 'Presentation progress',
              onSeeAll: () =>
                  context.go('${RouteNames.teacherDashboard}/presentations'),
            ),
          ),
          SliverToBoxAdapter(
            child: Consumer(
              builder: (context, ref, _) {
                final presAsync = ref.watch(presentationListProvider);
                return presAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: LinearProgressIndicator(),
                  ),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (rows) {
                    if (rows.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Text(
                          'No presentations yet',
                          style: GoogleFonts.poppins(
                              fontSize: 11, color: AppColors.textMuted),
                          textAlign: TextAlign.center,
                        ),
                      );
                    }
                    final cards = _buildTeacherRingsCards(
                      rows.cast<Map<String, dynamic>>(),
                    );
                    return Column(children: cards);
                  },
                );
              },
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: _s(context, 8, min: 6, max: 12))),

          // ── Today's timetable header ──────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                _s(context, 20, min: 14, max: 26),
                _s(context, 10, min: 8, max: 14),
                _s(context, 12, min: 8, max: 16),
                _s(context, 8, min: 6, max: 10),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_rounded,
                      size: _s(context, 15, min: 13, max: 17), color: AppColors.primary),
                  SizedBox(width: _s(context, 8, min: 6, max: 10)),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Today's Timetable",
                        style: GoogleFonts.poppins(
                          fontSize: _fs(context, 14, min: 12, max: 16),
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _fmtEDMon.format(DateTime.now()),
                      style: GoogleFonts.poppins(
                          fontSize: _fs(context, 12, min: 10, max: 14),
                          color: AppColors.textMuted),
                    ),
                  ),
                  TextButton(
                    onPressed: () => context
                        .go('${RouteNames.teacherDashboard}/timetable'),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                          horizontal: _s(context, 8, min: 6, max: 10),
                          vertical: 4),
                      minimumSize: const Size(48, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'See all →',
                      style: GoogleFonts.poppins(
                        fontSize: _fs(context, 11, min: 9, max: 12),
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Timetable slots — horizontal scroll ───────────────────────
          summaryAsync.when(
            loading: () => const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: LinearProgressIndicator(),
              ),
            ),
            error: (e, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
            data: (_) {
              // A local holiday day has slots, all flagged as holiday. A
              // whole-school holiday won't reach my_timetable at all (the
              // holiday marker has no teacher_id), so fall back to the
              // grade-wide flag — otherwise the teacher just sees an empty box.
              final localHoliday = todaySlots.isNotEmpty &&
                  todaySlots.every((s) => s.isHoliday);
              final holidayReason = localHoliday
                  ? todaySlots
                      .map((s) => (s.comment ?? '').trim())
                      .firstWhere((c) => c.isNotEmpty, orElse: () => '')
                  : '';
              return SliverToBoxAdapter(
                child: (localHoliday || isSchoolHoliday)
                    ? HolidayBanner(reason: holidayReason)
                    : todaySlots.isEmpty
                        ? _TimetableEmpty()
                        : _TimetableHScroll(slots: todaySlots),
              );
            },
          ),

          // ── Recent Homework ───────────────────────────────────────────
          SliverToBoxAdapter(
            child: _DashSectionHeader(
              icon: Icons.assignment_outlined,
              title: 'Recent Homework',
              onSeeAll: () => context.go('${RouteNames.teacherDashboard}/homework'),
            ),
          ),
          SliverToBoxAdapter(
            child: summaryAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: LinearProgressIndicator(),
              ),
              error: (_, __) => const SizedBox.shrink(),
              data: (summary) {
                final rawHw = (summary['homework'] as List<dynamic>? ?? []);
                final list = rawHw
                    .map((e) => HomeworkModel.fromJson(e as Map<String, dynamic>))
                    .toList();
                return list.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Text('No homework yet',
                          style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textMuted),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : Column(
                        children: list.take(3).map((h) => _DashHomeworkTile(hw: h)).toList(),
                      );
              },
            ),
          ),

          // ── Recent Announcements ──────────────────────────────────────
          SliverToBoxAdapter(
            child: _DashSectionHeader(
              icon: Icons.campaign_outlined,
              title: 'Announcements',
              showBadge: hasBroadcastBadge,
              onSeeAll: () {
                ref.read(teacherBroadcastBadgeNotifier.notifier).markSeen();
                context.go('${RouteNames.teacherDashboard}/broadcasts');
              },
            ),
          ),
          SliverToBoxAdapter(
            child: summaryAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: LinearProgressIndicator(),
              ),
              error: (_, __) => const SizedBox.shrink(),
              data: (summary) {
                final rawBc = (summary['broadcasts'] as List<dynamic>? ?? []);
                final list = rawBc
                    .map((e) => BroadcastModel.fromJson(e as Map<String, dynamic>))
                    .toList();
                return list.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Text('No announcements yet',
                          style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textMuted),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : Column(
                        children: list.take(2).map((b) => _DashBroadcastTile(broadcast: b, lastSeen: lastSeenBroadcast)).toList(),
                      );
              },
            ),
          ),
          // ── Report a problem — small button at the bottom of the page ──
          SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: TextButton.icon(
                  onPressed: () => showReportProblemDialog(context, ref),
                  icon: const Icon(Icons.bug_report_outlined, size: 16),
                  label: const Text('Report a problem'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: _s(context, 16, min: 12, max: 24))),

        ],
        ),
      ),
    );
  }
}

// ─── Shared Widgets ───────────────────────────────────────────────────────────

// ── _DashSectionHeader ────────────────────────────────────────────
class _DashSectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback? onSeeAll;
  final bool showBadge;
  const _DashSectionHeader({required this.icon, required this.title, this.onSeeAll, this.showBadge = false});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final sw = constraints.maxWidth;
      return Padding(
        padding: EdgeInsets.fromLTRB(
          (sw * 0.05).clamp(14.0, 22.0), 0,
          (sw * 0.02).clamp(4.0, 8.0), 6,
        ),
        child: Row(
          children: [
            BadgeDot(
              show: showBadge,
              child: Icon(icon, size: (sw * 0.038).clamp(13.0, 16.0), color: AppColors.primary),
            ),
            SizedBox(width: (sw * 0.02).clamp(5.0, 8.0)),
            Text(title, style: GoogleFonts.poppins(
              fontSize: (sw * 0.033).clamp(11.0, 14.0),
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            )),
            const Spacer(),
            if (onSeeAll != null)
              TextButton(
                onPressed: onSeeAll,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: const Size(48, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text('See all →', style: GoogleFonts.poppins(
                  fontSize: (sw * 0.028).clamp(10.0, 12.0),
                  color: AppColors.accent,
                )),
              ),
          ],
        ),
      );
    });
  }
}

// ── _DashHomeworkTile ─────────────────────────────────────────────
class _DashHomeworkTile extends StatelessWidget {
  final HomeworkModel hw;
  const _DashHomeworkTile({required this.hw});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final sw = constraints.maxWidth;
      final hPad = (sw * 0.05).clamp(14.0, 22.0);
      final vPad = (sw * 0.022).clamp(8.0, 12.0);
      return Container(
        margin: EdgeInsets.fromLTRB(hPad, 0, hPad, (sw * 0.018).clamp(5.0, 8.0)),
        padding: EdgeInsets.symmetric(horizontal: (sw * 0.035).clamp(10.0, 14.0), vertical: vPad),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [BoxShadow(color: Color(0x0C1D3557), blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: (sw * 0.02).clamp(5.0, 8.0),
                vertical: (sw * 0.01).clamp(2.0, 4.0),
              ),
              decoration: BoxDecoration(
                color: hw.isOnlineTest
                    ? AppColors.accent.withValues(alpha: 0.12)
                    : AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                hw.isOnlineTest ? 'Test' : 'HW',
                style: GoogleFonts.poppins(
                  fontSize: (sw * 0.025).clamp(9.0, 11.0),
                  fontWeight: FontWeight.w700,
                  color: hw.isOnlineTest ? AppColors.accent : AppColors.primary,
                ),
              ),
            ),
            SizedBox(width: (sw * 0.025).clamp(7.0, 10.0)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(hw.title,
                    style: GoogleFonts.poppins(
                      fontSize: (sw * 0.03).clamp(11.0, 13.0),
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text('${hw.subject} · Grade ${hw.grade}',
                    style: GoogleFonts.poppins(
                      fontSize: (sw * 0.026).clamp(9.0, 11.0),
                      color: AppColors.textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Text(
              _fmtDMon.format(hw.createdAt),
              style: GoogleFonts.poppins(
                fontSize: (sw * 0.025).clamp(9.0, 11.0),
                color: AppColors.accent,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    });
  }
}

// ── _DashBroadcastTile ────────────────────────────────────────────
class _DashBroadcastTile extends StatelessWidget {
  final BroadcastModel broadcast;
  final DateTime? lastSeen;
  const _DashBroadcastTile({required this.broadcast, this.lastSeen});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go('${RouteNames.teacherDashboard}/broadcasts'),
      child: _buildTile(context),
    );
  }

  Widget _buildTile(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final sw = constraints.maxWidth;
      final hPad = (sw * 0.05).clamp(14.0, 22.0);
      final vPad = (sw * 0.022).clamp(8.0, 12.0);
      final isNew = lastSeen == null || broadcast.createdAt.isAfter(lastSeen!);
      return Container(
        margin: EdgeInsets.fromLTRB(hPad, 0, hPad, (sw * 0.018).clamp(5.0, 8.0)),
        padding: EdgeInsets.symmetric(horizontal: (sw * 0.035).clamp(10.0, 14.0), vertical: vPad),
        decoration: BoxDecoration(
          color: isNew ? AppColors.accent.withValues(alpha: 0.07) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: isNew ? Border.all(color: AppColors.accent.withValues(alpha: 0.30), width: 1) : null,
          boxShadow: const [BoxShadow(color: Color(0x0C1D3557), blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: Row(
          children: [
            Icon(Icons.campaign_outlined,
              size: (sw * 0.038).clamp(13.0, 17.0),
              color: AppColors.accent,
            ),
            SizedBox(width: (sw * 0.025).clamp(7.0, 10.0)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(broadcast.title,
                    style: GoogleFonts.poppins(
                      fontSize: (sw * 0.03).clamp(11.0, 13.0),
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(broadcast.message,
                    style: GoogleFonts.poppins(
                      fontSize: (sw * 0.026).clamp(9.0, 11.0),
                      color: AppColors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text(
              _fmtDMon.format(broadcast.createdAt),
              style: GoogleFonts.poppins(
                fontSize: (sw * 0.025).clamp(9.0, 11.0),
                color: AppColors.accent,
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _ProfileAvatar extends StatelessWidget {
  final String username;
  final String? photoUrl;
  final double radius;
  const _ProfileAvatar({required this.username, this.photoUrl, required this.radius});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: photoUrl != null
            ? CachedNetworkImage(imageUrl: photoUrl!, fit: BoxFit.cover)
            : Container(
                color: AppColors.iconContainer,
                child: Center(
                  child: Text(
                    username.isNotEmpty ? username[0].toUpperCase() : 'T',
                    style: GoogleFonts.poppins(
                      fontSize: radius * 0.75,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  const _Badge({required this.label});

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: (sw * 0.026).clamp(8.0, 14.0),
        vertical: (sw * 0.010).clamp(3.0, 6.0),
      ),
      decoration: BoxDecoration(
        color: AppColors.iconContainer,
        borderRadius: BorderRadius.circular((sw * 0.038).clamp(12.0, 18.0)),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
            fontSize: _fs(context, 10, min: 9, max: 12),
            fontWeight: FontWeight.w500,
            color: AppColors.primary),
      ),
    );
  }
}

class _SubjectChip extends StatelessWidget {
  final String subject;
  const _SubjectChip({required this.subject});

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: (sw * 0.02).clamp(6.0, 10.0),
        vertical: (sw * 0.008).clamp(2.0, 4.0),
      ),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular((sw * 0.028).clamp(8.0, 12.0)),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Text(subject,
          style: GoogleFonts.poppins(
              fontSize: _fs(context, 10, min: 9, max: 11),
              fontWeight: FontWeight.w500,
              color: AppColors.primary)),
    );
  }
}

// ─── Broadcast Icon Button (dashboard header) ─────────────────────────────────

// ─── Horizontal Timetable ────────────────────────────────────────────────────

class _TimetableEmpty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final sw = constraints.maxWidth;
      return Container(
        margin: EdgeInsets.fromLTRB(
          (sw * 0.04).clamp(12.0, 20.0), 0,
          (sw * 0.04).clamp(12.0, 20.0), 16,
        ),
        padding: EdgeInsets.symmetric(vertical: (sw * 0.065).clamp(20.0, 28.0)),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [BoxShadow(color: Color(0x0E1D3557), blurRadius: 8, offset: Offset(0, 3))],
        ),
        child: Center(
          child: Text('No classes today',
              style: GoogleFonts.poppins(
                  fontSize: (sw * 0.033).clamp(11.0, 14.0),
                  color: AppColors.textMuted)),
        ),
      );
    });
  }
}
class _TimetableHScroll extends StatelessWidget {
  final List<TimetableSlotModel> slots;
  const _TimetableHScroll({required this.slots});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final sw = constraints.maxWidth;
      final hPad = (sw * 0.04).clamp(12.0, 18.0);
      final gap  = (sw * 0.018).clamp(5.0, 8.0);
      final n    = slots.length;
      // Divide available width equally so all cards fit with no scroll
      final cardW = ((sw - hPad * 2 - gap * (n - 1)) / n).clamp(44.0, 160.0);
      final cardH = (sw * 0.28).clamp(95.0, 122.0);
      return Padding(
        padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 12),
        child: Row(
          children: [
            for (int i = 0; i < n; i++) ...[
              if (i > 0) SizedBox(width: gap),
              _TimetableCard(slot: slots[i], cardW: cardW, cardH: cardH),
            ],
          ],
        ),
      );
    });
  }
}

class _TimetableCard extends StatelessWidget {
  final TimetableSlotModel slot;
  final double cardW;
  final double cardH;
  const _TimetableCard(
      {required this.slot, required this.cardW, required this.cardH});

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    final now = DateTime.now();
    bool isNow = false;
    if (!slot.isHoliday && slot.startTime != null && slot.endTime != null) {
      try {
        final start = _parseTime(slot.startTime!, now);
        final end   = _parseTime(slot.endTime!, now);
        isNow = now.isAfter(start) && now.isBefore(end);
      } catch (_) {}
    }
    final onDark = isNow ? Colors.white : AppColors.primary;
    final onMuted = isNow
        ? Colors.white.withValues(alpha: 0.72)
        : AppColors.textMuted;

    return Container(
      width: cardW,
      height: cardH,
      padding: EdgeInsets.all((sw * 0.024).clamp(8.0, 11.0)),
      decoration: BoxDecoration(
        color: isNow ? AppColors.primary : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Color(0x0E1D3557), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Period badge + time range. Time lives here so even holiday cards
          // still show when the period would have run.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: (sw * 0.018).clamp(6.0, 9.0),
                  vertical: (sw * 0.008).clamp(2.0, 4.0),
                ),
                decoration: BoxDecoration(
                  color: isNow
                      ? Colors.white.withValues(alpha: 0.18)
                      : AppColors.iconContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'P${slot.periodNumber}',
                  style: GoogleFonts.poppins(
                    fontSize: (sw * 0.024).clamp(9.0, 11.0),
                    fontWeight: FontWeight.w700,
                    color: onDark,
                  ),
                ),
              ),
              if (slot.startTime != null) ...[
                SizedBox(width: (sw * 0.014).clamp(4.0, 7.0)),
                Expanded(
                  child: Text(
                    slot.endTime != null
                        ? '${slot.startTime} – ${slot.endTime}'
                        : slot.startTime!,
                    style: GoogleFonts.poppins(
                      fontSize: (sw * 0.017).clamp(6.5, 8.0),
                      fontWeight: FontWeight.w600,
                      color: onMuted,
                    ),
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
          const Spacer(),
          // Subject
          Text(
            slot.isHoliday
                ? 'Holiday'
                : (slot.subject?.isNotEmpty == true ? slot.subject! : slot.teacherUsername ?? 'Period ${slot.periodNumber}'),
            style: GoogleFonts.poppins(
              fontSize: (sw * 0.031).clamp(11.0, 14.0),
              fontWeight: FontWeight.w700,
              color: onDark,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          // Grade (time moved into the badge row above)
          Text(
            slot.isHoliday
                ? (slot.comment ?? '')
                : 'Grade ${slot.grade}',
            style: GoogleFonts.poppins(
              fontSize: (sw * 0.023).clamp(8.0, 10.0),
              color: onMuted,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          if (!slot.isHoliday && slot.comment != null && slot.comment!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              slot.comment!,
              style: GoogleFonts.poppins(
                fontSize: (sw * 0.020).clamp(7.0, 9.0),
                color: Colors.orange,
                fontStyle: FontStyle.italic,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  DateTime _parseTime(String t, DateTime base) {
    final parts = t.split(':');
    return DateTime(base.year, base.month, base.day,
        int.parse(parts[0]), int.parse(parts[1]));
  }
}

// ─── Grade Analysis Chart (web only) ─────────────────────────────────────────

class _GradeAnalysisChart extends StatefulWidget {
  final List<GradeModel> grades;
  const _GradeAnalysisChart({required this.grades});

  @override
  State<_GradeAnalysisChart> createState() => _GradeAnalysisChartState();
}

class _GradeAnalysisChartState extends State<_GradeAnalysisChart> {
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    // Compute average percentage per subject
    final Map<String, List<double>> bySubject = {};
    for (final g in widget.grades) {
      bySubject.putIfAbsent(g.subject, () => []).add(g.percentage);
    }
    final subjects = bySubject.keys.toList()..sort();
    final averages = subjects
        .map((s) => bySubject[s]!.reduce((a, b) => a + b) / bySubject[s]!.length)
        .toList();

    if (subjects.isEmpty) return const SizedBox.shrink();

    // Bar colors cycle through a palette
    const palette = [
      Color(0xFF457B9D),
      Color(0xFFD4653B),
      Color(0xFF2E7D52),
      Color(0xFFB07A20),
      Color(0xFF6A3B9E),
      Color(0xFF1D3557),
      Color(0xFF2E5F8A),
      Color(0xFFAA4A27),
    ];

    final bars = subjects.asMap().entries.map((e) {
      final i = e.key;
      final isTouched = i == _touchedIndex;
      final color = palette[i % palette.length];
      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: averages[i],
            color: isTouched ? color : color.withValues(alpha: 0.75),
            width: isTouched ? 22 : 18,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: 100,
              color: Colors.white.withValues(alpha: 0.05),
            ),
          ),
        ],
      );
    }).toList();

    return Container(
      decoration: mindForgeCardDecoration(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
                    Icon(Icons.bar_chart_rounded, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('Grade Analysis — Average % by Subject',
                  style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.iconContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${widget.grades.length} records',
                    style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Tap a bar for details',
              style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textMuted)),
          const SizedBox(height: 16),

          // Chart
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                maxY: 100,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => AppColors.primaryDark,
                    tooltipRoundedRadius: 8,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final subject = subjects[group.x];
                      final count = bySubject[subject]!.length;
                      return BarTooltipItem(
                        '$subject\n',
                        GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                        children: [
                          TextSpan(
                            text: '${rod.toY.toStringAsFixed(1)}%  ·  $count tests',
                            style: GoogleFonts.poppins(color: Colors.white70, fontSize: 11),
                          ),
                        ],
                      );
                    },
                  ),
                  touchCallback: (event, response) {
                    setState(() {
                      _touchedIndex = (event is FlTapUpEvent || event is FlPointerHoverEvent)
                          ? (response?.spot?.touchedBarGroupIndex ?? -1)
                          : -1;
                    });
                  },
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (val, meta) {
                        final i = val.toInt();
                        if (i < 0 || i >= subjects.length) return const SizedBox.shrink();
                        final label = subjects[i].length > 8
                            ? '${subjects[i].substring(0, 7)}…'
                            : subjects[i];
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(label,
                              style: GoogleFonts.poppins(fontSize: 9, color: AppColors.textMuted),
                              textAlign: TextAlign.center),
                        );
                      },
                      reservedSize: 30,
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      interval: 25,
                      getTitlesWidget: (val, meta) => Text(
                        '${val.toInt()}%',
                        style: GoogleFonts.poppins(fontSize: 9, color: AppColors.textMuted),
                      ),
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  horizontalInterval: 25,
                  getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.divider, strokeWidth: 1),
                  drawVerticalLine: false,
                ),
                borderData: FlBorderData(show: false),
                barGroups: bars,
                groupsSpace: 12,
              ),
              swapAnimationDuration: const Duration(milliseconds: 400),
              swapAnimationCurve: Curves.easeOut,
            ),
          ),

          // Legend
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: subjects.asMap().entries.map((e) {
              final color = palette[e.key % palette.length];
              final avg = averages[e.key];
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 10, height: 10,
                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 5),
                  Text('${e.value}  ${avg.toStringAsFixed(0)}%',
                      style: GoogleFonts.poppins(fontSize: 10, color: AppColors.textSecondary)),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ─── Today's workflow card ────────────────────────────────────────────────────
//
// Surfaces the daily teacher workflow as a "road" per grade with four
// milestones: Timetable → Attendance → HW Review → Homework. A car icon
// marks the boundary between completed (solid colored line) and pending
// (dashed grey line) sections. Each milestone is tappable and navigates
// to the relevant screen. Backed by GET /teacher/today-workflow.

class _TodayWorkflowCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _TodayWorkflowCard({required this.data});

  static const _doneColor = Color(0xFF22C55E);    // green
  static const _pendingColor = Color(0xFFF59E0B); // amber

  static Color gradeColor(int grade) {
    switch (grade) {
      case 8:
        return const Color(0xFF3B82F6); // blue
      case 9:
        return const Color(0xFF8B5CF6); // purple
      case 10:
        return const Color(0xFFF97316); // orange
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final grades = (data['grades'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    // Whole-school holiday: among the grades that have today's timetable
    // filled in, every one is a holiday. (Grades with no timetable yet are
    // "not created", not a contradiction.) Marking a holiday strips the
    // teacher_id off slots, so the dashboard summary's my_timetable can't see
    // it — this grade-wide workflow data is the reliable holiday signal.
    final gradesWithTimetable =
        grades.where((g) => g['timetable_created'] == true).toList();
    final isHoliday = data['is_holiday_for_teacher'] == true ||
        (gradesWithTimetable.isNotEmpty &&
            gradesWithTimetable.every((g) => g['is_holiday'] == true));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (grades.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final g in grades)
                    _GradePill(
                      grade: g['grade'] as int,
                      color: gradeColor(g['grade'] as int),
                    ),
                ],
              ),
            const SizedBox(height: 4),
            if (isHoliday || grades.isEmpty)
              const HolidayBanner(margin: EdgeInsets.only(top: 4))
            else
              ...grades.map((g) => _GradeRoadRow(
                    grade: g,
                    color: gradeColor(g['grade'] as int),
                    doneColor: _doneColor,
                    pendingColor: _pendingColor,
                  )),
            if (!isHoliday && grades.isNotEmpty) ...[
              const SizedBox(height: 6),
              const Divider(height: 1, color: AppColors.divider),
              const SizedBox(height: 10),
              const Row(
                children: [
                  _LegendDot(color: _doneColor, label: 'Done'),
                  SizedBox(width: 16),
                  _LegendDot(color: _pendingColor, label: 'Pending'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

}

class _GradePill extends StatelessWidget {
  final int grade;
  final Color color;
  const _GradePill({required this.grade, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 4,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Text('Gr. $grade',
              style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary)),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.primary)),
      ],
    );
  }
}

class _RoadStep {
  final String label;
  final bool done;
  final bool na;
  final bool enabled;
  final VoidCallback? onTap;
  const _RoadStep({
    required this.label,
    required this.done,
    required this.na,
    required this.enabled,
    required this.onTap,
  });
}

class _GradeRoadRow extends StatelessWidget {
  final Map<String, dynamic> grade;
  final Color color;
  final Color doneColor;
  final Color pendingColor;
  const _GradeRoadRow({
    required this.grade,
    required this.color,
    required this.doneColor,
    required this.pendingColor,
  });

  @override
  Widget build(BuildContext context) {
    final g = grade['grade'] as int;
    final isHoliday = grade['is_holiday'] == true;
    final timetableCreated = grade['timetable_created'] == true;
    final attendanceTaken = grade['attendance_taken'] == true;
    // Backend signals N/A for the attendance step when there are no
    // non-holiday periods today (full holiday or no class today). In
    // that case the car should skip attendance, and HW review / HW
    // assignment must not require it. Default to true so older API
    // payloads keep their old behavior.
    final attendanceApplicable = grade['attendance_applicable'] != false;
    final attendanceSatisfied = attendanceTaken || !attendanceApplicable;
    final reviewApplicable = grade['review_applicable'] == true;
    final reviewComplete = grade['review_complete'] == true;
    final canAssignNew = grade['can_assign_new_homework'] == true;
    final tomorrowHwAssigned = grade['tomorrow_hw_assigned'] == true;

    final reviewDone =
        reviewApplicable && reviewComplete && attendanceSatisfied;

    // Every milestone is tappable regardless of workflow gating — the
    // gating only controls visual emphasis (active/dimmed). The
    // destination screens enforce their own preconditions.
    final steps = <_RoadStep>[
      _RoadStep(
        label: 'Timetable',
        done: timetableCreated,
        na: false,
        enabled: true,
        onTap: () =>
            context.go('${RouteNames.teacherDashboard}/timetable'),
      ),
      _RoadStep(
        label: 'Attendance',
        done: attendanceTaken,
        na: !attendanceApplicable,
        enabled: timetableCreated && attendanceApplicable,
        onTap: () =>
            context.go('${RouteNames.teacherDashboard}/attendance'),
      ),
      _RoadStep(
        label: 'HW Review',
        done: reviewDone,
        na: !reviewApplicable,
        enabled: attendanceSatisfied && reviewApplicable,
        onTap: () =>
            context.go('${RouteNames.teacherDashboard}/homework'),
      ),
      _RoadStep(
        label: 'Homework',
        done: tomorrowHwAssigned,
        na: false,
        enabled: canAssignNew,
        onTap: () =>
            context.go('${RouteNames.teacherDashboard}/homework'),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('Gr.$g',
                style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 78,
              child: _WorkflowRoad(
                steps: steps,
                color: color,
                doneColor: doneColor,
                pendingColor: pendingColor,
                isHoliday: isHoliday,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkflowRoad extends StatelessWidget {
  final List<_RoadStep> steps;
  final Color color;
  final Color doneColor;
  final Color pendingColor;
  final bool isHoliday;
  const _WorkflowRoad({
    required this.steps,
    required this.color,
    required this.doneColor,
    required this.pendingColor,
    required this.isHoliday,
  });

  @override
  Widget build(BuildContext context) {
    final n = steps.length;
    // First non-done, non-na step. If everything is done/na, currentIdx == n
    // and the car parks past the final milestone.
    var currentIdx = n;
    for (var i = 0; i < n; i++) {
      if (!steps[i].done && !steps[i].na) {
        currentIdx = i;
        break;
      }
    }

    return LayoutBuilder(builder: (context, constraints) {
      const radius = 11.0;
      const carRadius = 16.0;
      const labelHeight = 18.0;
      const labelWidth = 80.0;
      // Padding on each side so the milestone circles and their labels
      // don't crash into the row's left/right edges.
      const leftPad = 32.0;
      const rightPad = 32.0;
      final width = constraints.maxWidth;
      final innerWidth = (width - leftPad - rightPad).clamp(1.0, double.infinity);
      double xAt(int i) => leftPad + innerWidth * i / (n - 1);

      final centerY = constraints.maxHeight / 2;

      // Solid colored line spans EVERY pixel the car has driven over —
      // i.e. from the start of the road all the way to the car's current
      // position (or the final milestone if all tasks are done). Previously
      // this stopped at the last completed milestone, which left the
      // segment between the last-done milestone and the car looking like
      // remaining road.
      double doneEndX;
      if (currentIdx == 0) {
        doneEndX = leftPad; // nothing done yet — no solid line
      } else if (currentIdx >= n) {
        doneEndX = xAt(n - 1);
      } else {
        doneEndX = xAt(currentIdx);
      }

      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _RoadPainter(
                color: color,
                pendingColor: AppColors.divider,
                startX: leftPad,
                doneEndX: doneEndX,
                allEndX: xAt(n - 1),
                centerY: centerY,
              ),
            ),
          ),
          for (var i = 0; i < n; i++) ...[
            // Current step is rendered as a tappable car instead of a
            // pending dot; other steps render the standard milestone.
            if (i == currentIdx)
              Positioned(
                left: xAt(i) - carRadius,
                top: centerY - carRadius,
                child: GestureDetector(
                  onTap: steps[i].onTap,
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: carRadius * 2,
                    height: carRadius * 2,
                    child: Center(
                      child: Icon(
                        Icons.directions_car_rounded,
                        size: 26,
                        color: color,
                      ),
                    ),
                  ),
                ),
              )
            else
              Positioned(
                left: xAt(i) - radius,
                top: centerY - radius,
                child: GestureDetector(
                  onTap: steps[i].onTap,
                  behavior: HitTestBehavior.opaque,
                  child: _Milestone(
                    step: steps[i],
                    doneColor: doneColor,
                    pendingColor: pendingColor,
                    radius: radius,
                  ),
                ),
              ),
            // Label (above for even index, below for odd) — also tappable.
            Positioned(
              left: xAt(i) - labelWidth / 2,
              width: labelWidth,
              top: i.isEven
                  ? centerY - radius - labelHeight - 2
                  : centerY + radius + 2,
              child: GestureDetector(
                onTap: steps[i].onTap,
                child: Text(
                  steps[i].label,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: steps[i].enabled
                        ? AppColors.primary
                        : AppColors.textMuted,
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    });
  }
}

class _Milestone extends StatelessWidget {
  final _RoadStep step;
  final Color doneColor;
  final Color pendingColor;
  final double radius;
  const _Milestone({
    required this.step,
    required this.doneColor,
    required this.pendingColor,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final fill = step.na
        ? AppColors.textMuted
        : (step.done ? doneColor : pendingColor);
    return Opacity(
      opacity: step.enabled || step.done ? 1 : 0.6,
      child: Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: fill.withValues(alpha: 0.35),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: step.done
            ? const Icon(Icons.check_rounded,
                size: 14, color: Colors.white)
            : null,
      ),
    );
  }
}

class _RoadPainter extends CustomPainter {
  final Color color;
  final Color pendingColor;
  final double startX;
  final double doneEndX;
  final double allEndX;
  final double centerY;
  _RoadPainter({
    required this.color,
    required this.pendingColor,
    required this.startX,
    required this.doneEndX,
    required this.allEndX,
    required this.centerY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final solidPaint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final dashPaint = Paint()
      ..color = pendingColor
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    if (doneEndX > startX) {
      canvas.drawLine(
          Offset(startX, centerY), Offset(doneEndX, centerY), solidPaint);
    }
    // Dashed remainder
    const dashLen = 6.0;
    const gapLen = 4.0;
    var x = doneEndX;
    while (x < allEndX) {
      final next = (x + dashLen).clamp(x, allEndX);
      canvas.drawLine(
          Offset(x, centerY), Offset(next, centerY), dashPaint);
      x += dashLen + gapLen;
    }
  }

  @override
  bool shouldRepaint(covariant _RoadPainter old) =>
      old.doneEndX != doneEndX ||
      old.allEndX != allEndX ||
      old.startX != startX ||
      old.centerY != centerY ||
      old.color != color ||
      old.pendingColor != pendingColor;
}

// ── _DashPresentationTile ─────────────────────────────────────────────────────
// Single row in the dashboard's "Presentation progress" section. Shows one
// teacher's pace through one chapter as a thin progress bar with caption.

/// Fixed palette of distinct, accessible colours used to give each teacher a
/// consistent visual identity across the dashboard. Index is teacher_id %
/// palette.length so the same teacher always lands on the same colour, no
/// matter which presentation row is being rendered.
const List<Color> _teacherPalette = <Color>[
  Color(0xFF3B82F6), // blue
  Color(0xFF8B5CF6), // purple
  Color(0xFFF97316), // orange
  Color(0xFF22C55E), // green
  Color(0xFFEF4444), // red
  Color(0xFF06B6D4), // cyan
  Color(0xFFD946EF), // fuchsia
  Color(0xFFEAB308), // amber
  Color(0xFF14B8A6), // teal
  Color(0xFFEC4899), // pink
];

Color _teacherColor(int? teacherId) =>
    _teacherPalette[(teacherId ?? 0).abs() % _teacherPalette.length];

// ignore: unused_element
class _DashPresentationTile extends StatelessWidget {
  final Map<String, dynamic> row;
  const _DashPresentationTile({required this.row});

  // Subject → tiny pictogram. Mirrors the palette used inside the
  // presentation viewer so dashboard, library, and detail screens all share
  // the same emoji vocabulary.
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

  @override
  Widget build(BuildContext context) {
    final id = row['presentation_id'] as int;
    final status = (row['status'] as String? ?? 'PROCESSING');
    final isProcessing = status == 'PROCESSING';
    final isFailed = status == 'FAILED';
    final periodsUsed = (row['periods_used'] as int?) ?? 0;
    final periodsRec = (row['recommended_periods'] as int?) ?? 0;
    final current = (row['current_slide_index'] as int?) ?? 0;
    final total = (row['total_slides'] as int?) ?? 0;
    final teacherId = row['teacher_id'] as int?;
    final tColor = _teacherColor(teacherId);
    final emoji = _subjectEmoji(row['subject']?.toString());

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: GestureDetector(
        onTap: isProcessing
            ? null
            : () => context.go(
                '${RouteNames.teacherDashboard}/presentations/$id'),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: tColor.withValues(alpha: 0.18)),
            boxShadow: [
              BoxShadow(
                color: tColor.withValues(alpha: 0.10),
                blurRadius: 8, offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Teacher-coloured left stripe.
                  Container(width: 4, color: tColor),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title row: subject emoji + chapter name + status.
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: tColor.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: Text(emoji,
                                    style: const TextStyle(fontSize: 14)),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  row['chapter_name']?.toString() ?? '—',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.poppins(
                                    fontSize: 13, fontWeight: FontWeight.w700,
                                    color: tColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              if (isProcessing)
                                SizedBox(
                                  width: 12, height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                        AlwaysStoppedAnimation(tColor),
                                  ),
                                )
                              else if (isFailed)
                                const Icon(Icons.error_outline,
                                    size: 14, color: AppColors.error),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Padding(
                            padding: const EdgeInsets.only(left: 32),
                            child: Text(
                              '${row['teacher_username']}  ·  Grade ${row['grade']} ${row['subject']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 10.5,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                          if (!isProcessing && !isFailed
                              && periodsRec > 0) ...[
                            const SizedBox(height: 10),
                            // Segmented progress: one block per period.
                            // Filled = period taught; the "current" block
                            // shows a partial fill based on slide ratio
                            // within that period.
                            _PresentationSegments(
                              periodsTotal: periodsRec,
                              periodsDone: periodsUsed,
                              slidesDone: current,
                              slidesTotal: total,
                              color: tColor,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '$periodsUsed / $periodsRec periods'
                              '   ·   $current / $total slides',
                              style: GoogleFonts.poppins(
                                fontSize: 10.5,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ] else if (isFailed) ...[
                            const SizedBox(height: 6),
                            Padding(
                              padding: const EdgeInsets.only(left: 32),
                              child: Text(
                                'Generation failed — tap to view.',
                                style: GoogleFonts.poppins(
                                  fontSize: 10.5, color: AppColors.error,
                                ),
                              ),
                            ),
                          ] else if (isProcessing) ...[
                            const SizedBox(height: 6),
                            Padding(
                              padding: const EdgeInsets.only(left: 32),
                              child: Text(
                                'Generating slides…',
                                style: GoogleFonts.poppins(
                                  fontSize: 10.5, color: AppColors.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Segmented progress bar for the dashboard presentation-progress tile.
/// One block per recommended period, laid out as equal-width rounded
/// rectangles with a small gap between each. Three states per block:
///   - taught:       solid teacher colour
///   - in-progress:  partial fill based on slide ratio (current period)
///   - remaining:    soft tinted background with a 1-px coloured border
///
/// Reads as a series of milestones without the visual noise of a road +
/// dots + car icon — easier to scan at a glance.
class _PresentationSegments extends StatelessWidget {
  final int periodsTotal;
  final int periodsDone;
  final int slidesDone;
  final int slidesTotal;
  final Color color;
  const _PresentationSegments({
    required this.periodsTotal,
    required this.periodsDone,
    required this.slidesDone,
    required this.slidesTotal,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final n = periodsTotal.clamp(1, 30);
    final done = periodsDone.clamp(0, n);

    // Partial fill ratio for the in-progress period: slides covered inside
    // the current period divided by slides expected in that period.
    // Defaults to 0 (block stays empty) if we can't infer.
    double inProgressRatio = 0.0;
    if (done < n && slidesTotal > 0) {
      final slidesPerPeriod = slidesTotal / periodsTotal;
      final slidesIntoCurrent = slidesDone - (done * slidesPerPeriod);
      if (slidesPerPeriod > 0) {
        inProgressRatio =
            (slidesIntoCurrent / slidesPerPeriod).clamp(0.0, 1.0);
      }
    }

    return SizedBox(
      height: 12,
      child: Row(
        children: [
          for (var i = 0; i < n; i++) ...[
            Expanded(
              child: _ProgressBlock(
                color: color,
                fillRatio: i < done
                    ? 1.0
                    : i == done
                        ? inProgressRatio
                        : 0.0,
              ),
            ),
            if (i < n - 1) const SizedBox(width: 3),
          ],
        ],
      ),
    );
  }
}

class _ProgressBlock extends StatelessWidget {
  final Color color;
  final double fillRatio; // 0..1
  const _ProgressBlock({required this.color, required this.fillRatio});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          border: Border.all(color: color.withValues(alpha: 0.45), width: 1),
          borderRadius: BorderRadius.circular(3),
        ),
        // Fill from the left using a FractionallySizedBox so the partial
        // state on the in-progress block reads as a familiar "filling up"
        // motion.
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: fillRatio,
            child: Container(color: color),
          ),
        ),
      ),
    );
  }
}

// ── _TeacherRingsCard ────────────────────────────────────────────────────────
// One card per teacher on the dashboard. Concentric circular rings — one per
// the teacher's active presentation — show slide-progress as an arc. Center
// shows the aggregate %. Legend below maps each ring colour back to its
// chapter name and period count.

const List<Color> _ringPalette = <Color>[
  Color(0xFF8B5CF6), // purple
  Color(0xFFF97316), // orange
  Color(0xFF14B8A6), // teal
  Color(0xFFEC4899), // pink
  Color(0xFF06B6D4), // cyan
  Color(0xFFEAB308), // yellow
  Color(0xFF22C55E), // green
  Color(0xFFEF4444), // red
];

/// Group dashboard rows by teacher and emit one ring card per teacher.
/// Caller supplies an optional `take` to cap the number of teachers shown.
List<Widget> _buildTeacherRingsCards(
  List<Map<String, dynamic>> rows, {
  int? take,
}) {
  final byTeacher = <int, List<Map<String, dynamic>>>{};
  for (final r in rows) {
    final tid = r['teacher_id'] as int? ?? -1;
    byTeacher.putIfAbsent(tid, () => []).add(r);
  }
  // Stable sort teachers by username.
  final entries = byTeacher.entries.toList()
    ..sort((a, b) {
      final au = a.value.first['teacher_username']?.toString() ?? '';
      final bu = b.value.first['teacher_username']?.toString() ?? '';
      return au.compareTo(bu);
    });
  final limited = take == null ? entries : entries.take(take);
  return limited
      .map((e) => _TeacherRingsCard(rows: e.value))
      .toList();
}

class _TeacherRingsCard extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  const _TeacherRingsCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final teacherUsername =
        rows.first['teacher_username']?.toString() ?? 'teacher';
    final teacherId = rows.first['teacher_id'] as int? ?? 0;
    final tColor = _teacherColor(teacherId);

    // Sort the teacher's decks by chapter name so the ring order is
    // stable across rebuilds.
    final decks = [...rows]..sort((a, b) =>
        (a['chapter_name']?.toString() ?? '')
            .compareTo(b['chapter_name']?.toString() ?? ''));
    final visibleDecks = decks.take(_ringPalette.length).toList();
    final hiddenCount = decks.length - visibleDecks.length;

    // Aggregate slide progress across the visible rings.
    int slidesDone = 0;
    int slidesTotal = 0;
    for (final r in visibleDecks) {
      slidesDone += (r['current_slide_index'] as int? ?? 0);
      slidesTotal += (r['total_slides'] as int? ?? 0);
    }
    final aggregatePct = slidesTotal > 0
        ? (slidesDone / slidesTotal).clamp(0.0, 1.0)
        : 0.0;

    // Compute per-deck slide ratio for the rings.
    final ringSpecs = <_RingSpec>[];
    for (var i = 0; i < visibleDecks.length; i++) {
      final r = visibleDecks[i];
      final t = r['total_slides'] as int? ?? 0;
      final c = r['current_slide_index'] as int? ?? 0;
      final pct = t > 0 ? (c / t).clamp(0.0, 1.0) : 0.0;
      ringSpecs.add(_RingSpec(color: _ringPalette[i], progress: pct));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tColor.withValues(alpha: 0.20)),
          boxShadow: [
            BoxShadow(
              color: tColor.withValues(alpha: 0.08),
              blurRadius: 8, offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: teacher pill
            Row(
              children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: tColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      teacherUsername.isNotEmpty
                          ? teacherUsername.substring(0, 1).toUpperCase()
                          : '?',
                      style: GoogleFonts.poppins(
                        fontSize: 13, fontWeight: FontWeight.w800,
                        color: tColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    teacherUsername,
                    style: GoogleFonts.poppins(
                      fontSize: 14, fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: tColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${decks.length} active',
                    style: GoogleFonts.poppins(
                      fontSize: 10.5, fontWeight: FontWeight.w700,
                      color: tColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Rings + centre text
            Center(
              child: SizedBox(
                width: 150, height: 150,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _ConcentricRingsPainter(
                          rings: ringSpecs,
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${(aggregatePct * 100).round()}%',
                          style: GoogleFonts.poppins(
                            fontSize: 22, fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          '$slidesDone / $slidesTotal slides',
                          style: GoogleFonts.poppins(
                            fontSize: 10.5, color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Legend
            for (var i = 0; i < visibleDecks.length; i++)
              _RingLegendRow(
                color: _ringPalette[i],
                row: visibleDecks[i],
              ),
            if (hiddenCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 18),
                child: Text(
                  '+ $hiddenCount more — see all →',
                  style: GoogleFonts.poppins(
                    fontSize: 11, color: AppColors.textMuted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RingSpec {
  final Color color;
  final double progress; // 0..1
  const _RingSpec({required this.color, required this.progress});
}

class _RingLegendRow extends StatelessWidget {
  final Color color;
  final Map<String, dynamic> row;
  const _RingLegendRow({required this.color, required this.row});

  /// Trim a trailing "(by foo)" suffix off the chapter name — the teacher
  /// is already named at the top of the card, so repeating it in the
  /// legend just adds noise.
  String _cleanChapter(String raw) =>
      raw.replaceFirst(RegExp(r'\s*\(by\s+[^)]+\)\s*$'), '').trim();

  @override
  Widget build(BuildContext context) {
    final id = row['presentation_id'] as int;
    final chapter = _cleanChapter(row['chapter_name']?.toString() ?? '—');
    final grade = row['grade'];
    return InkWell(
      onTap: () =>
          context.go('${RouteNames.teacherDashboard}/presentations/$id'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Container(
              width: 10, height: 10,
              decoration: BoxDecoration(
                color: color, shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RichText(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: GoogleFonts.poppins(
                    fontSize: 12, color: AppColors.textPrimary,
                  ),
                  children: [
                    TextSpan(
                      text: 'Grade $grade  ',
                      style: GoogleFonts.poppins(
                        fontSize: 11, color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(
                      text: chapter,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints concentric rings — outermost ring first, each inner ring drawn
/// at a smaller radius. Each ring has a faint background full circle plus
/// a darker arc representing progress.
class _ConcentricRingsPainter extends CustomPainter {
  final List<_RingSpec> rings;
  _ConcentricRingsPainter({required this.rings});

  static const double _strokeWidth = 9.0;
  static const double _gap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (rings.isEmpty) return;
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.shortestSide / 2 - _strokeWidth / 2;
    for (var i = 0; i < rings.length; i++) {
      final r = maxR - i * (_strokeWidth + _gap);
      if (r < _strokeWidth) break;
      final spec = rings[i];
      // background ring
      final bg = Paint()
        ..color = spec.color.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth;
      canvas.drawCircle(center, r, bg);
      // progress arc — starts at top (-90°), sweeps clockwise.
      if (spec.progress > 0) {
        final fg = Paint()
          ..color = spec.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = _strokeWidth
          ..strokeCap = StrokeCap.round;
        final sweep = (spec.progress.clamp(0.0, 1.0)) * 2 * math.pi;
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: r),
          -math.pi / 2,
          sweep,
          false,
          fg,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ConcentricRingsPainter old) {
    if (old.rings.length != rings.length) return true;
    for (var i = 0; i < rings.length; i++) {
      if (old.rings[i].color != rings[i].color ||
          old.rings[i].progress != rings[i].progress) {
        return true;
      }
    }
    return false;
  }
}
