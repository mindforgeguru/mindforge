import 'dart:async';

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
import '../../../core/providers/badge_provider.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/badge_dot.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/teacher_provider.dart';
import '../widgets/teacher_bottom_nav.dart';
import '../widgets/teacher_scaffold.dart';

// File-level DateFormat cache.
final _fmtYMD   = DateFormat('yyyy-MM-dd');
final _fmtEDMon = DateFormat('EEE, d MMM');
final _fmtDMon  = DateFormat('d MMM');
final _fmtEEEE  = DateFormat('EEEE');
final _fmtDMonY = DateFormat('d MMMM yyyy');

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
    final userId = ref.read(authProvider).userId;
    if (userId == null) return;
    final ws = ref.read(webSocketClientProvider);
    _wsSub = ws.connect(userId).listen((event) {
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

    // ── Error state: show retry UI instead of silently blank sections ─────
    if (summaryAsync.hasError) {
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

    final subjects = summaryAsync.maybeWhen(
      data: (summary) {
        final raw = (summary['my_timetable'] as List<dynamic>? ?? []);
        return raw
            .map((e) =>
                TimetableSlotModel.fromJson(e as Map<String, dynamic>).subject)
            .whereType<String>()
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
    final double navyH = topPadding + (screenHeight * 0.165).clamp(95.0, 142.0);
    // Smaller fonts → less height needed
    final double cardInternalH = subjects.isEmpty
        ? (avatarRadius + 90).clamp(128.0, 155.0)
        : (avatarRadius + 116).clamp(152.0, 185.0);
    final double headerH = navyH + cardInternalH - cardIntoNavy + avatarRadius;

    // ── Web layout ─────────────────────────────────────────────────────────
    if (screenWidth >= 900) {
      final hour = DateTime.now().hour;
      final greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';
      return TeacherScaffold(
        backgroundColor: const Color(0xFFF0F4F8),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Hero section ───────────────────────────────────────────
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0A1628), Color(0xFF1D3557), Color(0xFF1A4A6E)],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
              child: Stack(
                children: [
                  Positioned(top: -50, right: 180,
                    child: Container(width: 220, height: 220,
                      decoration: BoxDecoration(shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.04)))),
                  Positioned(bottom: -70, right: -40,
                    child: Container(width: 260, height: 260,
                      decoration: BoxDecoration(shape: BoxShape.circle,
                        color: AppColors.accent.withOpacity(0.08)))),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 22, 28, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Row 1: avatar + greeting + date
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: () => context.go('${RouteNames.teacherDashboard}/profile'),
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white.withOpacity(0.3), width: 2.5),
                                ),
                                child: _ProfileAvatar(
                                  username: auth.username ?? 'T',
                                  photoUrl: auth.profilePicUrl,
                                  radius: 26,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$greeting, ${auth.username ?? 'Teacher'}!',
                                    style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700,
                                      color: Colors.white, letterSpacing: -0.3),
                                  ),
                                  if (subjects.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      subjects.join('  ·  '),
                                      style: GoogleFonts.poppins(fontSize: 12, color: Colors.white.withOpacity(0.6)),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(_fmtEEEE.format(DateTime.now()),
                                  style: GoogleFonts.poppins(fontSize: 12, color: Colors.white.withOpacity(0.5))),
                                Text(_fmtDMonY.format(DateTime.now()),
                                  style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // Row 2: stat cards + quick actions
                        // Wrap is used so the quick-action chips fall to a
                        // second line on narrower web widths instead of
                        // overflowing past the hero card.
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                _HeroStatCard(
                                  value: '${todaySlots.length}',
                                  label: 'Classes Today',
                                  icon: Icons.today_rounded,
                                  accent: const Color(0xFF64B5F6),
                                  onTap: () => context.go('${RouteNames.teacherDashboard}/timetable'),
                                ),
                                Builder(builder: (ctx) {
                                  final count = summaryAsync.maybeWhen(
                                    data: (s) => ((s['grades'] as List<dynamic>?)?.length ?? 0),
                                    orElse: () => 0,
                                  );
                                  return _HeroStatCard(
                                    value: '$count',
                                    label: 'Grade Records',
                                    icon: Icons.grade_rounded,
                                    accent: const Color(0xFFFFB74D),
                                    onTap: () => context.go('${RouteNames.teacherDashboard}/grades'),
                                  );
                                }),
                                Builder(builder: (ctx) {
                                  final count = summaryAsync.maybeWhen(
                                    data: (s) => (s['test_count'] as int? ?? 0),
                                    orElse: () => 0,
                                  );
                                  return _HeroStatCard(
                                    value: '$count',
                                    label: 'Tests',
                                    icon: Icons.quiz_rounded,
                                    accent: AppColors.secondary,
                                    onTap: () => context.go('${RouteNames.teacherDashboard}/tests'),
                                  );
                                }),
                                Builder(builder: (ctx) {
                                  final count = summaryAsync.maybeWhen(
                                    data: (s) => ((s['broadcasts'] as List<dynamic>?)?.length ?? 0),
                                    orElse: () => 0,
                                  );
                                  return _HeroStatCard(
                                    value: '$count',
                                    label: 'Broadcasts',
                                    icon: Icons.campaign_rounded,
                                    accent: const Color(0xFFCE93D8),
                                    showBadge: hasBroadcastBadge,
                                    onTap: () {
                                      ref.read(teacherBroadcastBadgeNotifier.notifier).markSeen();
                                      context.go('${RouteNames.teacherDashboard}/broadcasts');
                                    },
                                  );
                                }),
                              ],
                            ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _WebQuickAction(
                                  icon: Icons.how_to_reg_outlined,
                                  label: 'Attendance',
                                  onTap: () => context.go('${RouteNames.teacherDashboard}/attendance'),
                                ),
                                _WebQuickAction(
                                  icon: Icons.assignment_outlined,
                                  label: 'Add Homework',
                                  onTap: () => context.go('${RouteNames.teacherDashboard}/homework'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Content ────────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Grade Analysis Chart
                    summaryAsync.maybeWhen(
                      data: (summary) {
                        final rawGrades = (summary['grades'] as List<dynamic>? ?? []);
                        final grades = rawGrades
                            .map((e) => GradeModel.fromJson(e as Map<String, dynamic>))
                            .toList();
                        if (grades.isEmpty) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: _GradeAnalysisChart(grades: grades),
                        );
                      },
                      orElse: () => const SizedBox.shrink(),
                    ),

                    // Two columns
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 6,
                          child: _WebSection(
                            icon: Icons.calendar_today_rounded,
                            title: "Today's Timetable",
                            trailing: Text(
                              _fmtEDMon.format(DateTime.now()),
                              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textMuted),
                            ),
                            onSeeAll: () => context.go('${RouteNames.teacherDashboard}/timetable'),
                            child: summaryAsync.when(
                              loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
                              error: (_, __) => const SizedBox.shrink(),
                              data: (_) => todaySlots.isEmpty
                                  ? _WebEmptyState(icon: Icons.event_busy_rounded, message: 'No classes scheduled for today')
                                  : Wrap(
                                      spacing: 12,
                                      runSpacing: 12,
                                      children: todaySlots.map((slot) => SizedBox(
                                        width: 180,
                                        child: _WebTimetableCard(slot: slot),
                                      )).toList(),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          flex: 4,
                          child: Column(
                            children: [
                              _WebSection(
                                icon: Icons.assignment_outlined,
                                title: 'Recent Homework',
                                onSeeAll: () => context.go('${RouteNames.teacherDashboard}/homework'),
                                child: summaryAsync.when(
                                  loading: () => const LinearProgressIndicator(),
                                  error: (_, __) => const SizedBox.shrink(),
                                  data: (summary) {
                                    final rawHw = (summary['homework'] as List<dynamic>? ?? []);
                                    final list = rawHw.map((e) => HomeworkModel.fromJson(e as Map<String, dynamic>)).toList();
                                    return list.isEmpty
                                        ? _WebEmptyState(icon: Icons.assignment_outlined, message: 'No homework assigned yet')
                                        : Column(children: list.take(3).map((h) => _DashHomeworkTile(hw: h)).toList());
                                  },
                                ),
                              ),
                              const SizedBox(height: 16),
                              _WebSection(
                                icon: Icons.campaign_outlined,
                                title: 'Announcements',
                                showBadge: hasBroadcastBadge,
                                onSeeAll: () {
                                  ref.read(teacherBroadcastBadgeNotifier.notifier).markSeen();
                                  context.go('${RouteNames.teacherDashboard}/broadcasts');
                                },
                                child: summaryAsync.when(
                                  loading: () => const LinearProgressIndicator(),
                                  error: (_, __) => const SizedBox.shrink(),
                                  data: (summary) {
                                    final rawBc = (summary['broadcasts'] as List<dynamic>? ?? []);
                                    final list = rawBc.map((e) => BroadcastModel.fromJson(e as Map<String, dynamic>)).toList();
                                    return list.isEmpty
                                        ? _WebEmptyState(icon: Icons.campaign_outlined, message: 'No announcements yet')
                                        : Column(children: list.take(3).map((b) => _DashBroadcastTile(broadcast: b, lastSeen: lastSeenBroadcast)).toList());
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Responsive logo / text sizes for header
    final double logoH = (screenWidth * 0.142).clamp(42.0, 58.0);
    final double titleFs = (screenWidth * 0.062).clamp(18.0, 25.0);

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
                                    color: Colors.white.withOpacity(0.72),
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
                                color: Colors.black.withOpacity(0.08),
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
            data: (_) => SliverToBoxAdapter(
              child: todaySlots.isEmpty
                  ? _TimetableEmpty()
                  : _TimetableHScroll(slots: todaySlots),
            ),
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
  final VoidCallback onSeeAll;
  final bool showBadge;
  const _DashSectionHeader({required this.icon, required this.title, required this.onSeeAll, this.showBadge = false});

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
                    ? AppColors.accent.withOpacity(0.12)
                    : AppColors.primary.withOpacity(0.08),
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
          color: isNew ? AppColors.accent.withOpacity(0.07) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: isNew ? Border.all(color: AppColors.accent.withOpacity(0.30), width: 1) : null,
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
            color: Colors.black.withOpacity(0.12),
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
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular((sw * 0.028).clamp(8.0, 12.0)),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
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

class _BroadcastIconButton extends ConsumerWidget {
  const _BroadcastIconButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iconSz = R.fluid(context, 20, min: 18, max: 24);
    return Tooltip(
      message: 'Send Broadcast',
      child: SizedBox(
        width: 40,
        height: 40,
        child: Material(
          color: AppColors.accent.withOpacity(0.12),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => context.go('${RouteNames.teacherDashboard}/broadcasts'),
            child: Center(
              child: Icon(Icons.campaign_outlined,
                  size: iconSz, color: AppColors.accent),
            ),
          ),
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
    final onDark = isNow ? Colors.white : AppColors.primary;
    final onMuted = isNow
        ? Colors.white.withOpacity(0.72)
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
                      ? Colors.white.withOpacity(0.18)
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

// ─── Timetable Tile ──────────────────────────────────────────────────────────

class _TimetableTile extends StatelessWidget {
  final TimetableSlotModel slot;
  const _TimetableTile({required this.slot});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    bool isNow = false;
    if (!slot.isHoliday && slot.startTime != null && slot.endTime != null) {
      try {
        final start = _parseTime(slot.startTime!, now);
        final end = _parseTime(slot.endTime!, now);
        isNow = now.isAfter(start) && now.isBefore(end);
      } catch (_) {}
    }

    final accent = slot.isHoliday
        ? AppColors.warning
        : isNow
            ? AppColors.accent
            : AppColors.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: isNow ? Border.all(color: AppColors.accent, width: 1.5) : null,
        boxShadow: const [
          BoxShadow(
              color: Color(0x0C1D3557), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: R.fluid(context, 42, min: 36, max: 50),
            height: R.fluid(context, 42, min: 36, max: 50),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                'P${slot.periodNumber}',
                style: GoogleFonts.poppins(
                  fontSize: R.fs(context, 11, min: 10, max: 13),
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  slot.isHoliday
                      ? 'Holiday'
                      : (slot.subject?.isNotEmpty == true ? slot.subject! : slot.teacherUsername ?? 'Period ${slot.periodNumber}'),
                  style: GoogleFonts.poppins(
                    fontSize: R.fs(context, 14, min: 12, max: 16),
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (!slot.isHoliday && slot.startTime != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${slot.startTime}  –  ${slot.endTime}',
                    style: GoogleFonts.poppins(
                        fontSize: R.fs(context, 11, min: 10, max: 13),
                        color: AppColors.textMuted),
                  ),
                ],
                if (!slot.isHoliday) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Grade ${slot.grade}',
                    style: GoogleFonts.poppins(
                        fontSize: R.fs(context, 11, min: 10, max: 13),
                        color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          if (isNow)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('NOW',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  )),
            ),
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

// ─── Web-only widgets ─────────────────────────────────────────────────────────

class _WebSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onSeeAll;
  final Widget child;
  final Widget? trailing;
  final bool showBadge;

  const _WebSection({
    required this.icon,
    required this.title,
    required this.onSeeAll,
    required this.child,
    this.trailing,
    this.showBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: mindForgeCardDecoration(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              BadgeDot(
                show: showBadge,
                child: Icon(icon, size: 16, color: AppColors.primary),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              if (trailing != null) ...[trailing!, const SizedBox(width: 8)],
              TextButton(
                onPressed: onSeeAll,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: const Size(48, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'See all →',
                  style: GoogleFonts.poppins(fontSize: 12, color: AppColors.accent),
                ),
              ),
            ],
          ),
          const Divider(height: 16),
          child,
        ],
      ),
    );
  }
}

class _WebQuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _WebQuickAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

class _WebTimetableCard extends StatelessWidget {
  final TimetableSlotModel slot;
  const _WebTimetableCard({required this.slot});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.iconContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'P${slot.periodNumber}',
              style: GoogleFonts.poppins(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            slot.subject?.isNotEmpty == true ? slot.subject! : slot.teacherUsername ?? 'Period ${slot.periodNumber}',
            style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
          Text(
            'Grade ${slot.grade}',
            style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary),
          ),
          if (slot.startTime != null)
            Text(
              '${slot.startTime} – ${slot.endTime ?? ''}',
              style: GoogleFonts.poppins(fontSize: 10, color: AppColors.textMuted, fontStyle: FontStyle.italic),
            ),
        ],
      ),
    );
  }
}

class _HeroStatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;
  final bool showBadge;

  const _HeroStatCard({
    required this.value,
    required this.label,
    required this.icon,
    required this.accent,
    required this.onTap,
    this.showBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.2),
                borderRadius: BorderRadius.circular(9),
              ),
              child: BadgeDot(
                show: showBadge,
                child: Icon(icon, size: 19, color: accent),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w800,
                    color: Colors.white, height: 1.1),
                ),
                Text(
                  label,
                  style: GoogleFonts.poppins(fontSize: 11, color: Colors.white.withOpacity(0.6)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WebNavCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool showBadge;
  const _WebNavCard({required this.icon, required this.label, required this.color, required this.onTap, this.showBadge = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BadgeDot(
                  show: showBadge,
                  child: Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 22, color: color),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  label,
                  style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WebEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _WebEmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: AppColors.divider),
          const SizedBox(height: 10),
          Text(
            message,
            style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
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
            color: isTouched ? color : color.withOpacity(0.75),
            width: isTouched ? 22 : 18,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: 100,
              color: Colors.white.withOpacity(0.05),
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
                  getDrawingHorizontalLine: (_) => FlLine(color: AppColors.divider, strokeWidth: 1),
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
    final isHoliday = data['is_holiday_for_teacher'] == true;
    final grades = (data['grades'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🗺️', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text("Today's Workflow",
                    style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
              ],
            ),
            const SizedBox(height: 10),
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
              _holidayBanner(context)
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
              Row(
                children: [
                  _LegendDot(color: _doneColor, label: 'Done'),
                  const SizedBox(width: 16),
                  _LegendDot(color: _pendingColor, label: 'Pending'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _holidayBanner(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.beach_access_rounded,
                size: 18, color: AppColors.success),
            const SizedBox(width: 8),
            Text('Today is a holiday — no classes scheduled.',
                style: GoogleFonts.poppins(
                    fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
      );
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
        color: color.withOpacity(0.12),
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

      // Solid colored line ends at the last completed milestone.
      double doneEndX;
      if (currentIdx == 0) {
        doneEndX = leftPad; // nothing done yet — no solid line
      } else if (currentIdx >= n) {
        doneEndX = xAt(n - 1);
      } else {
        doneEndX = xAt(currentIdx - 1);
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
              color: fill.withOpacity(0.35),
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
