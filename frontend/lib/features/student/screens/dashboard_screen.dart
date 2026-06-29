import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/api/websocket_client.dart';
import '../../../core/models/attendance.dart';
import '../../../core/models/grade.dart';
import '../../../core/models/homework.dart';
import '../../../core/models/timetable.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/constants.dart';
import '../../../core/utils/logout_confirm.dart';
import '../../../core/providers/badge_provider.dart';
import '../../../core/widgets/badge_dot.dart';
import '../../../core/widgets/holiday_banner.dart';
import '../../../core/widgets/report_problem_dialog.dart';
import '../../../core/widgets/shimmer_list.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/student_provider.dart';
import '../providers/xp_provider.dart';
import '../widgets/level_up_dialog.dart';
import '../widgets/student_scaffold.dart';
import '../widgets/xp_progress_bar.dart';

// File-level DateFormat cache — avoids repeated object allocations in build().
final _fmtYMD     = DateFormat('yyyy-MM-dd');
final _fmtEDMon   = DateFormat('EEE, d MMM');
final _fmtDMon    = DateFormat('d MMM');

// Responsive scale helper — base ref width 390 px
double _s(BuildContext ctx, double base, {double min = 0, double max = double.infinity}) {
  final w = MediaQuery.of(ctx).size.width;
  final scaled = base * (w / 390.0);
  return scaled.clamp(min == 0 ? base * 0.75 : min, max == double.infinity ? base * 1.4 : max);
}

double _fs(BuildContext ctx, double base, {double min = 10, double max = 22}) =>
    _s(ctx, base, min: min, max: max);

class StudentDashboardScreen extends ConsumerStatefulWidget {
  const StudentDashboardScreen({super.key});

  @override
  ConsumerState<StudentDashboardScreen> createState() =>
      _StudentDashboardScreenState();
}

class _StudentDashboardScreenState
    extends ConsumerState<StudentDashboardScreen>
    with WidgetsBindingObserver {
  StreamSubscription<Map<String, dynamic>>? _wsSub;

  String get _todayString => _fmtYMD.format(DateTime.now());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _connectWs());
  }

  // When the app last entered the paused state. Used to debounce brief
  // resume/pause flaps (notification shade, system overlays) that would
  // otherwise force a full WS reconnect every few seconds.
  DateTime? _lastPausedAt;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // On web, AppLifecycleState.resumed fires on every window-focus event and
    // on GoRouter navigations — both cause needless invalidations that keep the
    // dashboard in a permanent loading state. Skip lifecycle refreshes on web.
    if (kIsWeb) return;
    if (state == AppLifecycleState.paused) {
      _lastPausedAt = DateTime.now();
      return;
    }
    if (state != AppLifecycleState.resumed || !mounted) return;
    // Brief resume flaps (< 30 s) don't need a fresh socket — the underlying
    // WS is almost certainly still alive and the dashboard data is fresh.
    // Only after a real backgrounding (Doze territory) do we tear down and
    // refetch.
    final pausedFor = _lastPausedAt == null
        ? Duration.zero
        : DateTime.now().difference(_lastPausedAt!);
    if (pausedFor < const Duration(seconds: 30)) return;
    // Defer one frame so we don't pile WS reconnect + provider invalidate +
    // Dio request onto the very frame Android is restoring after unlock.
    // Doing it inline freezes the UI thread on some devices.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _wsSub?.cancel();
      // Force a fresh socket — Doze can leave `_channel` non-null with a
      // dead underlying socket, so reusing it silently drops events.
      ref.read(webSocketClientProvider).forceReconnect();
      _connectWs();
      // Only invalidate — do NOT await the network call here.
      // The provider rebuilds in the background; waiting for the network on
      // resume can freeze the UI while WiFi/cellular reconnects after unlock.
      ref.invalidate(studentDashboardSummaryProvider(_todayString));
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
      } else if (eventType == 'level_up') {
        // Refresh the XP card data behind the dialog so the new level
        // shows when the user dismisses.
        ref.invalidate(studentXpProvider);
        LevelUpDialog.show(
          context,
          newLevel: (event['level'] as num?)?.toInt() ?? 0,
          newTitle: event['title'] as String? ?? '',
          totalXp: (event['total_xp'] as num?)?.toInt() ?? 0,
        );
      } else if (eventType != null) {
        // Any relevant event → refresh the single summary
        ref.invalidate(studentDashboardSummaryProvider(_todayString));
        // Most XP-relevant events also imply XP changed — refresh the card.
        if (eventType == 'attendance_updated' ||
            eventType == 'grade_added' ||
            eventType == 'test_submitted') {
          ref.invalidate(studentXpProvider);
        }
        // New test published → also refresh the tests screen
        if (eventType == 'new_test_available' || eventType == 'test_status_changed') {
          ref.invalidate(pendingTestsProvider);
          ref.invalidate(offlineTestsProvider);
        }
      }
    });
  }

  Future<void> _refreshDashboard() async {
    ref.invalidate(studentDashboardSummaryProvider(_todayString));
    await ref
        .read(studentDashboardSummaryProvider(_todayString).future)
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
            ? 'Your username has been changed to "$newUsername" by the admin. Please log in again with your new credentials.'
            : 'Your account details have been updated by the admin. Please log in again.'),
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

  @override
  Widget build(BuildContext context) {
    // The dashboard uses the same single-column sliver layout on every form
    // factor. On web, StudentScaffold caps it at a 600 px centred column —
    // identical to the parent dashboard so all three roles look consistent.
    // (The earlier 2-column `_buildWebLayout` is intentionally retired; its
    // helper widgets remain in this file so we can revive a wide layout
    // later without re-implementing the test/timetable/attendance/HW boxes.)

    final auth = ref.watch(authProvider);
    final summaryAsync = ref.watch(studentDashboardSummaryProvider(_todayString));

    // Full-screen error state — keeps the header rendered but shows a retry
    // button so users aren't silently stuck on a blank dashboard.
    if (summaryAsync.hasError && !summaryAsync.hasValue) {
      return StudentScaffold(
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
                      fontSize: 17, fontWeight: FontWeight.w600,
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
    final lastSeenBroadcast = ref.watch(studentBroadcastBadgeNotifier);
    final hasBroadcastBadge = ref.watch(
      studentDashboardSummaryProvider(_todayString).select((async) =>
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

    // Responsive layout values
    final double avatarRadius = (screenWidth * 0.114).clamp(36.0, 50.0);
    final double cardRadius = (screenWidth * 0.062).clamp(20.0, 28.0);
    final double cardHMargin = (screenWidth * 0.04).clamp(12.0, 20.0);
    final double cardIntoNavy = (screenHeight * 0.066).clamp(44.0, 60.0);
    final double navyH = topPadding + (screenHeight * 0.165).clamp(95.0, 142.0);
    // Card must fit: avatarRadius + 14 (top pad) + text+badges ~70 + 26 (bottom pad)
    final double cardInternalH = (avatarRadius + 88).clamp(132.0, 162.0);
    final double headerH = navyH + cardInternalH - cardIntoNavy + avatarRadius;

    // Responsive logo / text sizes for header
    final double logoH = (screenWidth * 0.142).clamp(42.0, 58.0);
    final double titleFs = (screenWidth * 0.062).clamp(18.0, 25.0);

    return StudentScaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: _refreshDashboard,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [

          // ── Header block: navy + white card ──────────────────────────
          SliverToBoxAdapter(
            child: SizedBox(
              height: headerH,
              child: Stack(
                clipBehavior: Clip.none,
                children: [

                  // ── Curved navy background ──────────────────────────
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

                  // ── Small logout icon top-right ──────────────────────
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
                        padding: EdgeInsets.zero,
                        onPressed: () => confirmLogout(context, ref),
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

                  // ── White profile card ──────────────────────────────
                  Positioned(
                    // Card starts inside the navy (cardIntoNavy px from navy bottom)
                    top: navyH - cardIntoNavy,
                    left: cardHMargin,
                    right: cardHMargin,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.topCenter,
                      children: [

                        // White card body — top margin reserves space for avatar
                        Container(
                          width: double.infinity,
                          margin: EdgeInsets.only(top: avatarRadius),
                          padding: EdgeInsets.fromLTRB(
                            _s(context, 20, min: 14, max: 28),
                            avatarRadius + _s(context, 8, min: 6, max: 12),
                            _s(context, 20, min: 14, max: 28),
                            _s(context, 12, min: 8, max: 16),
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
                          child: _WelcomeContent(
                            username: auth.username ?? 'Student',
                            onProfile: () => context.go(
                                '${RouteNames.studentDashboard}/profile'),
                          ),
                        ),

                        // Avatar sitting on top of the card — tappable
                        Positioned(
                          top: 0,
                          child: GestureDetector(
                            onTap: () => context.go(
                                '${RouteNames.studentDashboard}/profile'),
                            child: Stack(
                              alignment: Alignment.bottomRight,
                              children: [
                                _ProfileAvatar(
                                  username: auth.username ?? 'S',
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

          // ── XP card ────────────────────────────────────────────────────
          const SliverToBoxAdapter(child: _XpHomeCard()),

          // ── Today's timetable header ──────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                _s(context, 20, min: 14, max: 26),
                _s(context, 4, min: 2, max: 6),
                _s(context, 12, min: 8, max: 16),
                _s(context, 8, min: 6, max: 10),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_rounded,
                      size: _s(context, 15, min: 13, max: 17),
                      color: AppColors.primary),
                  SizedBox(width: _s(context, 8, min: 6, max: 10)),
                  Text(
                    "Today's Timetable",
                    style: GoogleFonts.poppins(
                      fontSize: _fs(context, 14, min: 12, max: 16),
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _fmtEDMon.format(DateTime.now()),
                          style: GoogleFonts.poppins(
                              fontSize: _fs(context, 12, min: 10, max: 14),
                              color: AppColors.textMuted),
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => context
                        .go('${RouteNames.studentDashboard}/timetable'),
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
            skipLoadingOnReload: true,
            loading: () => const SliverToBoxAdapter(
              child: ShimmerCards(count: 1, cardHeight: 110),
            ),
            error: (e, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
            data: (summary) {
              final rawSlots = (summary['timetable'] as List<dynamic>? ?? []);
              final slots = rawSlots
                  .map((e) =>
                      TimetableSlotModel.fromJson(e as Map<String, dynamic>))
                  .toList();
              // A holiday day has slots, all flagged as holiday.
              final isHoliday =
                  slots.isNotEmpty && slots.every((s) => s.isHoliday);
              final holidayReason = isHoliday
                  ? slots
                      .map((s) => (s.comment ?? '').trim())
                      .firstWhere((c) => c.isNotEmpty, orElse: () => '')
                  : '';
              return SliverToBoxAdapter(
                child: slots.isEmpty
                    ? _TimetableEmpty()
                    : isHoliday
                        ? HolidayBanner(reason: holidayReason)
                        : _TimetableHScroll(slots: slots),
              );
            },
          ),

          // ── Recent Test Marks (latest 10, oldest → newest) ────────────
          SliverToBoxAdapter(
            child: _DashSectionHeader(
              icon: Icons.bar_chart_rounded,
              title: 'Recent Test Marks',
              onSeeAll: () => context.go('${RouteNames.studentDashboard}/grades'),
            ),
          ),
          SliverToBoxAdapter(
            child: summaryAsync.when(
              skipLoadingOnReload: true,
              loading: () => const ShimmerCards(count: 1, cardHeight: 200),
              error: (_, __) => const SizedBox.shrink(),
              data: (summary) {
                final raw = (summary['grades'] as List<dynamic>? ?? []);
                final list = raw
                    .map((e) =>
                        GradeModel.fromJson(e as Map<String, dynamic>))
                    .toList();
                return _RecentMarksChart(grades: list);
              },
            ),
          ),

          // ── Attendance breakdown (full / partial / absent days) ───────
          SliverToBoxAdapter(
            child: _DashSectionHeader(
              icon: Icons.pie_chart_rounded,
              title: 'Attendance Breakdown',
              onSeeAll: () =>
                  context.go('${RouteNames.studentDashboard}/attendance'),
            ),
          ),
          SliverToBoxAdapter(
            child: Consumer(builder: (context, ref, _) {
              final attAsync = ref.watch(studentAttendanceProvider);
              return attAsync.when(
                skipLoadingOnReload: true,
                loading: () =>
                    const ShimmerCards(count: 1, cardHeight: 220),
                error: (_, __) => const SizedBox.shrink(),
                data: (records) =>
                    _AttendancePieChart(records: records),
              );
            }),
          ),

          // ── Homework completion (ring pie) ────────────────────────────
          SliverToBoxAdapter(
            child: _DashSectionHeader(
              icon: Icons.donut_large_rounded,
              title: 'Homework Status',
              onSeeAll: () => context.go(
                  '${RouteNames.studentDashboard}/homework'),
            ),
          ),
          SliverToBoxAdapter(
            child: Consumer(builder: (context, ref, _) {
              final completionsAsync = ref.watch(
                  studentHomeworkCompletionsProvider);
              return summaryAsync.when(
                skipLoadingOnReload: true,
                loading: () =>
                    const ShimmerCards(count: 1, cardHeight: 220),
                error: (_, __) => const SizedBox.shrink(),
                data: (summary) {
                  final hwIds = (summary['homework'] as List<dynamic>? ?? [])
                      .map((e) =>
                          (e as Map<String, dynamic>)['id'] as int)
                      .toSet();
                  final map = completionsAsync.maybeWhen(
                    data: (m) => m,
                    orElse: () =>
                        <int, StudentHomeworkCompletion>{},
                  );
                  return _HomeworkCompletionPie(
                      homeworkIds: hwIds, completions: map);
                },
              );
            }),
          ),

          // ── Recent Homework ───────────────────────────────────────────
          SliverToBoxAdapter(
            child: _DashSectionHeader(
              icon: Icons.assignment_outlined,
              title: 'Recent Homework',
              onSeeAll: () => context.go('${RouteNames.studentDashboard}/homework'),
            ),
          ),
          SliverToBoxAdapter(
            child: summaryAsync.when(
              skipLoadingOnReload: true,
              loading: () => const ShimmerCards(count: 2, cardHeight: 68),
              error: (_, __) => const SizedBox.shrink(),
              data: (summary) {
                final rawHw = (summary['homework'] as List<dynamic>? ?? []);
                final list = rawHw
                    .map((e) =>
                        HomeworkModel.fromJson(e as Map<String, dynamic>))
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
                        children: list.take(2).map((h) => _DashHomeworkTile(hw: h)).toList(),
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
                ref.read(studentBroadcastBadgeNotifier.notifier).markSeen();
                context.go('${RouteNames.studentDashboard}/broadcasts');
              },
            ),
          ),
          SliverToBoxAdapter(
            child: summaryAsync.when(
              skipLoadingOnReload: true,
              loading: () => const ShimmerCards(count: 2, cardHeight: 68),
              error: (_, __) => const SizedBox.shrink(),
              data: (summary) {
                final rawBc = (summary['broadcasts'] as List<dynamic>? ?? []);
                final list = rawBc
                    .map((e) =>
                        BroadcastModel.fromJson(e as Map<String, dynamic>))
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
                        children: list.take(2).map((b) => _DashBroadcastTile(
                          broadcast: b,
                          lastSeen: lastSeenBroadcast,
                        )).toList(),
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

// ─── Profile Avatar ──────────────────────────────────────────────────────────

class _ProfileAvatar extends StatelessWidget {
  final String username;
  final String? photoUrl;
  final double radius;

  const _ProfileAvatar(
      {required this.username, this.photoUrl, required this.radius});

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
        child: Builder(
          builder: (_) {
            final fallback = Container(
              color: AppColors.iconContainer,
              child: Center(
                child: Text(
                  username.isNotEmpty ? username[0].toUpperCase() : 'S',
                  style: GoogleFonts.poppins(
                    fontSize: radius * 0.75,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            );
            return photoUrl != null
                ? CachedNetworkImage(
                    imageUrl: photoUrl!,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => fallback,
                  )
                : fallback;
          },
        ),
      ),
    );
  }
}

// ─── Welcome Card Content ────────────────────────────────────────────────────

class _WelcomeContent extends ConsumerWidget {
  final String username;
  final VoidCallback onProfile;

  const _WelcomeContent(
      {required this.username, required this.onProfile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gradeAsync = ref.watch(studentGradeProvider);

    return GestureDetector(
      onTap: onProfile,
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'Welcome back, $username',
              style: GoogleFonts.poppins(
                fontSize: _fs(context, 14, min: 12, max: 17),
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(height: _s(context, 8, min: 6, max: 10)),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              const _Badge(label: 'STUDENT'),
              gradeAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (grade) => grade == null
                    ? const SizedBox.shrink()
                    : _Badge(label: 'Grade $grade'),
              ),
            ],
          ),
        ],
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
          color: AppColors.primary,
        ),
      ),
    );
  }
}

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
    final onDark  = isNow ? Colors.white : AppColors.primary;
    final onMuted = isNow ? Colors.white.withValues(alpha: 0.72) : AppColors.textMuted;

    return Container(
      width: cardW,
      height: cardH,
      padding: EdgeInsets.all((sw * 0.024).clamp(8.0, 11.0)),
      decoration: BoxDecoration(
        color: isNow ? AppColors.primary : Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: Color(0x0E1D3557), blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Period badge + time range. Time lives here (not stacked below the
          // subject) so a holiday card still shows when the period would have
          // been, and free periods read "P3  09:30 – 10:15" cleanly.
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
                    fontSize: (sw * 0.025).clamp(9.0, 11.0),
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
                      fontSize: (sw * 0.018).clamp(7.0, 8.5),
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
                : (slot.subject?.isNotEmpty == true
                    ? slot.subject!
                    : slot.teacherUsername ?? 'Period ${slot.periodNumber}'),
            style: GoogleFonts.poppins(
              fontSize: (sw * 0.031).clamp(11.0, 14.0),
              fontWeight: FontWeight.w700,
              color: onDark,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          // Teacher (time moved into the badge row above)
          Text(
            slot.isHoliday
                ? (slot.comment ?? '')
                : slot.subject?.isNotEmpty == true
                    ? (slot.teacherUsername ?? 'Grade ${slot.grade}')
                    : '',
            style: GoogleFonts.poppins(
              fontSize: (sw * 0.024).clamp(8.5, 10.5),
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

// ─── Timetable Tile ──────────────────────────────────────────────────────────

// ── _DashSectionHeader ────────────────────────────────────────────
class _DashSectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onSeeAll;
  final bool showBadge;
  const _DashSectionHeader({
    required this.icon,
    required this.title,
    required this.onSeeAll,
    this.showBadge = false,
  });

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
                  Text(hw.subject,
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
      onTap: () => context.go('${RouteNames.studentDashboard}/homework'),
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

// ═══════════════════════════════════════════════════════════════════════════════
// WEB LAYOUT WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════
// ─── Mobile dashboard: rolling 20-test marks chart ─────────────────────────────
//
// Reads the `grades` list straight from the dashboard summary (already loaded —
// no extra network call) and shows a bar chart of the latest 20 results. The
// backend returns grades newest-first; we take(20) and reverse so the bars read
// left-to-right oldest → newest, matching how a timeline is normally read.
// When a 21st result arrives, take(20) naturally drops the oldest of the
// previous window — i.e. the leftmost bar shifts off as a new one appears
// on the right.

class _RecentMarksChart extends StatelessWidget {
  final List<GradeModel> grades;
  const _RecentMarksChart({required this.grades});

  // 10 distinct hues so each of the 10 bars gets its own color.
  static const _palette = <Color>[
    Color(0xFF3B82F6), // blue
    Color(0xFF10B981), // emerald
    Color(0xFFF59E0B), // amber
    Color(0xFFEF4444), // red
    Color(0xFF8B5CF6), // violet
    Color(0xFF14B8A6), // teal
    Color(0xFFF97316), // orange
    Color(0xFFEC4899), // pink
    Color(0xFF22C55E), // green
    Color(0xFF6366F1), // indigo
  ];

  @override
  Widget build(BuildContext context) {
    if (grades.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Text(
          'No test marks yet',
          style: GoogleFonts.poppins(
              fontSize: 11, color: AppColors.textMuted),
          textAlign: TextAlign.center,
        ),
      );
    }

    final window = grades.take(20).toList().reversed.toList();
    // With up to 20 bars, thin them so they don't overlap on narrow screens.
    final barWidth = window.length > 10 ? 8.0 : 16.0;
    // Y-axis is percentage, fixed 0–100 so bars are comparable across tests
    // even when raw maxMarks differ (a 10/10 quiz vs a 70/100 exam render at
    // the same height of 100% rather than the small bar dominating the big
    // bar at raw value).
    const yCeiling = 100.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEAEEF3)),
        ),
        padding: const EdgeInsets.fromLTRB(8, 16, 12, 12),
        child: SizedBox(
          height: 200,
          child: BarChart(
            BarChartData(
              maxY: yCeiling,
              minY: 0,
              alignment: BarChartAlignment.spaceAround,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: yCeiling / 4,
                getDrawingHorizontalLine: (_) =>
                    const FlLine(color: Color(0xFFE5E7EB), strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    interval: yCeiling / 4,
                    getTitlesWidget: (v, _) => Text(
                      '${v.toInt()}%',
                      style: GoogleFonts.poppins(
                          fontSize: 9, color: AppColors.textMuted),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= window.length) {
                        return const SizedBox.shrink();
                      }
                      final s = window[i].subject;
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          s.length > 4 ? s.substring(0, 4) : s,
                          style: GoogleFonts.poppins(
                              fontSize: 9, color: AppColors.textMuted),
                        ),
                      );
                    },
                  ),
                ),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
              ),
              barGroups: List.generate(window.length, (i) {
                return BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: window[i].percentage.clamp(0.0, 100.0),
                      color: _palette[i % _palette.length],
                      width: barWidth,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4)),
                    ),
                  ],
                );
              }),
            ),
            swapAnimationDuration: const Duration(milliseconds: 350),
          ),
        ),
      ),
    );
  }
}

// ─── Mobile dashboard: day-level attendance breakdown pie chart ────────────────
//
// Period-level rows are grouped by date. Each day falls into one of three
// buckets:
//   • full    — every period that day was marked present
//   • partial — at least one present and at least one absent
//   • absent  — every period was marked absent
//
// The schema only stores per-period present/absent (see
// backend/app/models/attendance.py) so "partial" is derived here, not stored.

class _AttendancePieChart extends StatelessWidget {
  final List<AttendanceModel> records;
  const _AttendancePieChart({required this.records});

  static const _fullColor = Color(0xFF10B981);    // emerald — full day
  static const _partialColor = Color(0xFFF59E0B); // amber  — partial day
  static const _absentColor = Color(0xFFEF4444);  // red    — fully absent day

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Text(
          'No attendance recorded yet',
          style: GoogleFonts.poppins(
              fontSize: 11, color: AppColors.textMuted),
          textAlign: TextAlign.center,
        ),
      );
    }

    // Defense in depth: dedupe by (date, period) before counting. Past
    // races could leave duplicate rows for the same slot; counting both
    // would double-count a single class as both present and absent and
    // incorrectly bucket the day as "partial".
    final perSlot = <String, AttendanceModel>{};
    for (final r in records) {
      final slotKey = '${_fmtYMD.format(r.date)}_${r.period}';
      final existing = perSlot[slotKey];
      if (existing == null || r.id > existing.id) {
        perSlot[slotKey] = r;
      }
    }
    // Group periods by calendar day (yyyy-MM-dd) and tally present/absent
    // counts. Then bucket the day based on the tallies.
    final byDay = <String, (int present, int absent)>{};
    for (final r in perSlot.values) {
      final key = _fmtYMD.format(r.date);
      final cur = byDay[key] ?? (0, 0);
      byDay[key] = r.isPresent
          ? (cur.$1 + 1, cur.$2)
          : (cur.$1, cur.$2 + 1);
    }
    var fullDays = 0, partialDays = 0, absentDays = 0;
    for (final entry in byDay.values) {
      if (entry.$1 > 0 && entry.$2 == 0) {
        fullDays++;
      } else if (entry.$1 == 0 && entry.$2 > 0) {
        absentDays++;
      } else {
        partialDays++;
      }
    }
    final totalDays = fullDays + partialDays + absentDays;

    // Build sections, skipping zero-value buckets so fl_chart doesn't draw
    // invisible slivers that still take up legend space.
    final sections = <PieChartSectionData>[];
    void addSection(int count, Color color) {
      if (count == 0) return;
      final pct = count / totalDays * 100;
      sections.add(PieChartSectionData(
        value: count.toDouble(),
        color: color,
        radius: 58,
        title: '${pct.toStringAsFixed(0)}%',
        titleStyle: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ));
    }
    addSection(fullDays, _fullColor);
    addSection(partialDays, _partialColor);
    addSection(absentDays, _absentColor);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEAEEF3)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
        child: Column(
          children: [
            SizedBox(
              height: 160,
              child: PieChart(
                PieChartData(
                  startDegreeOffset: -90,
                  sectionsSpace: 2,
                  centerSpaceRadius: 36,
                  sections: sections,
                ),
                swapAnimationDuration:
                    const Duration(milliseconds: 350),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                _PieLegendDot(
                    color: _fullColor,
                    label: 'Present  ·  $fullDays'),
                _PieLegendDot(
                    color: _partialColor,
                    label: 'Partial  ·  $partialDays'),
                _PieLegendDot(
                    color: _absentColor,
                    label: 'Absent  ·  $absentDays'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PieLegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _PieLegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }
}

// ─── Mobile dashboard: homework completion ring pie ────────────────────────────
//
// Buckets active homework into Complete / Incomplete / Pending using the
// completion provider. Distinct color palette from the attendance pie so
// the two charts don't look like the same chart twice.

class _HomeworkCompletionPie extends StatelessWidget {
  final Set<int> homeworkIds;
  final Map<int, StudentHomeworkCompletion> completions;
  const _HomeworkCompletionPie({
    required this.homeworkIds,
    required this.completions,
  });

  static const _completeColor = Color(0xFF6366F1);   // indigo
  static const _incompleteColor = Color(0xFFEC4899); // pink
  static const _pendingColor = Color(0xFF94A3B8);    // slate-400

  @override
  Widget build(BuildContext context) {
    if (homeworkIds.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Text(
          'No homework assigned yet',
          style: GoogleFonts.poppins(
              fontSize: 11, color: AppColors.textMuted),
          textAlign: TextAlign.center,
        ),
      );
    }

    var complete = 0, incomplete = 0, pending = 0;
    for (final hwId in homeworkIds) {
      final c = completions[hwId];
      if (c == null) {
        pending++;
      } else if (c.completed) {
        complete++;
      } else {
        incomplete++;
      }
    }
    final total = complete + incomplete + pending;

    final sections = <PieChartSectionData>[];
    void addSection(int count, Color color) {
      if (count == 0) return;
      final pct = count / total * 100;
      sections.add(PieChartSectionData(
        value: count.toDouble(),
        color: color,
        radius: 42,
        title: '${pct.toStringAsFixed(0)}%',
        titleStyle: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ));
    }
    addSection(complete, _completeColor);
    addSection(incomplete, _incompleteColor);
    addSection(pending, _pendingColor);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEAEEF3)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
        child: Column(
          children: [
            SizedBox(
              height: 160,
              child: PieChart(
                PieChartData(
                  startDegreeOffset: -90,
                  sectionsSpace: 2,
                  // Larger center hole = ring/donut style.
                  centerSpaceRadius: 50,
                  sections: sections,
                ),
                swapAnimationDuration:
                    const Duration(milliseconds: 350),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                _PieLegendDot(
                    color: _completeColor,
                    label: 'Complete  ·  $complete'),
                _PieLegendDot(
                    color: _incompleteColor,
                    label: 'Incomplete  ·  $incomplete'),
                _PieLegendDot(
                    color: _pendingColor,
                    label: 'Pending  ·  $pending'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
// ─── XP card on the home dashboard ────────────────────────────────────────────
//
// Small clickable card showing the student's current level and progress to
// next level. Uses the shared XPProgressBar widget in compact mode. Taps
// route to the full XP dashboard at /student/xp.

class _XpHomeCard extends ConsumerWidget {
  const _XpHomeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final xpAsync = ref.watch(studentXpProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.go('${RouteNames.studentDashboard}/xp'),
          child: xpAsync.when(
            // Skeleton-ish placeholder while we load — mirrors the bar height
            // so the home doesn't reflow when XP arrives.
            loading: () => Container(
              height: 92,
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.divider),
              ),
              child: const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            // Silent on error so the rest of the dashboard stays clean.
            // Tapping still opens the full XP screen, which surfaces the error.
            error: (_, __) => const SizedBox.shrink(),
            data: (xp) => XPProgressBar(
              currentLevel: xp.currentLevel,
              currentLevelTitle: xp.currentLevelTitle,
              xpIntoLevel: xp.xpIntoLevel,
              xpForNextLevel: xp.xpForNextLevel,
              progress: xp.progressToNextLevel,
              compact: true,
            ),
          ),
        ),
      ),
    );
  }
}

