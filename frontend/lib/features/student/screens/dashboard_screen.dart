import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/api/websocket_client.dart';
import '../../../core/models/homework.dart';
import '../../../core/models/timetable.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/constants.dart';
import '../../../core/utils/logout_confirm.dart';
import '../../../core/providers/badge_provider.dart';
import '../../../core/widgets/badge_dot.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/student_provider.dart';
import '../widgets/student_bottom_nav.dart';

// File-level DateFormat cache — avoids repeated object allocations in build().
final _fmtYMD     = DateFormat('yyyy-MM-dd');
final _fmtEDMon   = DateFormat('EEE, d MMM');
final _fmtDMon    = DateFormat('d MMM');
final _fmtEEEE    = DateFormat('EEEE');
final _fmtMMMd    = DateFormat('MMM d');

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _wsSub?.cancel();
      _connectWs();
      _refreshDashboard();
    }
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
        // Any relevant event → refresh the single summary
        ref.invalidate(studentDashboardSummaryProvider(_todayString));
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
    final isWide = MediaQuery.of(context).size.width >= 900;
    if (isWide) return _buildWebLayout(context);

    final auth = ref.watch(authProvider);
    final summaryAsync = ref.watch(studentDashboardSummaryProvider(_todayString));

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

    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: const StudentBottomNav(),
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
                                color: Colors.black.withOpacity(0.08),
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
                                  decoration: const BoxDecoration(
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
            loading: () => const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: LinearProgressIndicator(),
              ),
            ),
            error: (e, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
            data: (summary) {
              final rawSlots = (summary['timetable'] as List<dynamic>? ?? []);
              final slots = rawSlots
                  .map((e) =>
                      TimetableSlotModel.fromJson(e as Map<String, dynamic>))
                  .toList();
              return SliverToBoxAdapter(
                child: slots.isEmpty
                    ? _TimetableEmpty()
                    : _TimetableHScroll(slots: slots),
              );
            },
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
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: LinearProgressIndicator(),
              ),
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
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: LinearProgressIndicator(),
              ),
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
          SliverToBoxAdapter(child: SizedBox(height: _s(context, 16, min: 12, max: 24))),

        ],
        ),
      ),
    );
  }

  // ── Web Layout ────────────────────────────────────────────────────────────
  Widget _buildWebLayout(BuildContext context) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      body: Column(
        children: [
          _StudentWebTopNav(auth: auth),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Hero: greeting + fee capsules ─────────────────────
                  _StudentWebHeroSection(auth: auth),
                  const SizedBox(height: 24),
                  // ── Dashboard grid ────────────────────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            _StudentWebTestChart(),
                            const SizedBox(height: 20),
                            _StudentWebTimetableBox(
                                todayString: _todayString),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          children: [
                            const _StudentWebAttendanceBox(),
                            const SizedBox(height: 20),
                            const _StudentWebBroadcastsBox(),
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
                    username.isNotEmpty ? username[0].toUpperCase() : 'S',
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
    final onMuted = isNow ? Colors.white.withOpacity(0.72) : AppColors.textMuted;

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
          // Period badge
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
                fontSize: (sw * 0.025).clamp(9.0, 11.0),
                fontWeight: FontWeight.w700,
                color: onDark,
              ),
            ),
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
          // Teacher • time
          Text(
            slot.isHoliday
                ? (slot.comment ?? '')
                : slot.subject?.isNotEmpty == true
                    ? '${slot.teacherUsername ?? 'Grade ${slot.grade}'}${slot.startTime != null ? ' • ${slot.startTime}' : ''}'
                    : slot.startTime != null ? slot.startTime! : '',
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
                color: onMuted,
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
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                'P${slot.periodNumber}',
                style: GoogleFonts.poppins(
                  fontSize: 11,
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
                      : (slot.subject?.isNotEmpty == true
                          ? slot.subject!
                          : slot.teacherUsername ?? 'Period ${slot.periodNumber}'),
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                if (!slot.isHoliday && slot.startTime != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${slot.startTime}  –  ${slot.endTime}',
                    style: GoogleFonts.poppins(
                        fontSize: 11, color: AppColors.textMuted),
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

// ═══════════════════════════════════════════════════════════════════════════════
// WEB LAYOUT WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

// ─── Top navigation bar ────────────────────────────────────────────────────────

class _StudentWebTopNav extends ConsumerWidget {
  final AuthState auth;
  const _StudentWebTopNav({required this.auth});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPath = GoRouterState.of(context).uri.toString();

    return Container(
      height: 60,
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Row(
          children: [
            // Logo
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(4),
              child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
            ),
            const SizedBox(width: 10),
            Text(
              'MIND FORGE',
              style: GoogleFonts.poppins(
                fontSize: 13, fontWeight: FontWeight.w800,
                color: AppColors.primary, letterSpacing: 1,
              ),
            ),
            const SizedBox(width: 32),
            // Nav links
            ..._navItems(context, currentPath),
            const Spacer(),
            // Profile icon
            GestureDetector(
              onTap: () => context.go('${RouteNames.studentDashboard}/profile'),
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppColors.iconContainer,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    (auth.username ?? 'S').substring(0, 1).toUpperCase(),
                    style: GoogleFonts.poppins(
                      fontSize: 14, fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _navItems(BuildContext context, String currentPath) {
    final items = [
      ('Home', Icons.home_outlined, RouteNames.studentDashboard, RouteNames.studentDashboard),
      ('Grades', Icons.grade_outlined, '${RouteNames.studentDashboard}/grades', '/grades'),
      ('Tests', Icons.quiz_outlined, '${RouteNames.studentDashboard}/tests', '/tests'),
      ('Attendance', Icons.how_to_reg_outlined, '${RouteNames.studentDashboard}/attendance', '/attendance'),
      ('Timetable', Icons.calendar_month_outlined, '${RouteNames.studentDashboard}/timetable', '/timetable'),
      ('Homework', Icons.assignment_outlined, '${RouteNames.studentDashboard}/homework', '/homework'),
      ('Broadcasts', Icons.campaign_outlined, '${RouteNames.studentDashboard}/broadcasts', '/broadcasts'),
    ];

    return items.map((item) {
      final label = item.$1;
      final route = item.$3;
      final match = item.$4;
      final isActive = label == 'Home'
          ? (currentPath == RouteNames.studentDashboard)
          : currentPath.contains(match);

      return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: TextButton(
          onPressed: () => context.go(route),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            backgroundColor: isActive ? AppColors.primary.withOpacity(0.08) : null,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              color: isActive ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ),
      );
    }).toList();
  }
}

// ─── Hero section: greeting + photo + fee capsules ────────────────────────────

class _StudentWebHeroSection extends ConsumerWidget {
  final AuthState auth;
  const _StudentWebHeroSection({required this.auth});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final username = auth.username ?? 'Student';
    final photoUrl = auth.profilePicUrl;
    final gradeAsync = ref.watch(studentGradeProvider);
    final feesAsync = ref.watch(studentFeesProvider);

    final fmt = NumberFormat('#,##0', 'en_IN');

    double baseFees = 0, extraFees = 0, paidFees = 0, balance = 0;
    feesAsync.whenData((fees) {
      baseFees = (fees['base_amount'] as num? ?? 0).toDouble();
      extraFees = ((fees['economics_fee'] as num? ?? 0) +
              (fees['computer_fee'] as num? ?? 0) +
              (fees['ai_fee'] as num? ?? 0))
          .toDouble();
      paidFees = (fees['total_paid'] as num? ?? 0).toDouble();
      balance = (fees['balance_due'] as num? ?? 0).toDouble();
    });

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Color(0x0E000000), blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Greeting row ──────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar
              GestureDetector(
                onTap: () => context.go('${RouteNames.studentDashboard}/profile'),
                child: Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.iconContainer,
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 3))],
                  ),
                  child: ClipOval(
                    child: photoUrl != null
                        ? CachedNetworkImage(imageUrl: photoUrl, fit: BoxFit.cover)
                        : Center(
                            child: Text(
                              username.isNotEmpty ? username[0].toUpperCase() : 'S',
                              style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.primary),
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome in, $username',
                    style: GoogleFonts.poppins(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.textPrimary, height: 1.1),
                  ),
                  gradeAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (grade) => grade == null
                        ? const SizedBox.shrink()
                        : Text('Grade $grade · Student',
                            style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 22),

          // ── Fee capsule row ───────────────────────────────────────
          Row(
            children: [
              _FeeCapsule(
                label: 'Base Fees',
                value: '₹${fmt.format(baseFees)}',
                style: _CapsuleStyle.darkNavy,
              ),
              const SizedBox(width: 10),
              _FeeCapsule(
                label: 'Extra Fees',
                value: '₹${fmt.format(extraFees)}',
                style: _CapsuleStyle.darkNavy,
              ),
              const SizedBox(width: 10),
              _FeeCapsule(
                label: 'Paid Fees',
                value: '₹${fmt.format(paidFees)}',
                style: _CapsuleStyle.blue,
              ),
              const SizedBox(width: 10),
              _FeeCapsule(
                label: 'Balance Due',
                value: '₹${fmt.format(balance)}',
                style: balance > 0 ? _CapsuleStyle.outline : _CapsuleStyle.outline,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _CapsuleStyle { darkNavy, blue, outline }

class _FeeCapsule extends StatelessWidget {
  final String label;
  final String value;
  final _CapsuleStyle style;

  const _FeeCapsule({required this.label, required this.value, required this.style});

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor;
    Border? border;

    switch (style) {
      case _CapsuleStyle.darkNavy:
        bgColor = const Color(0xFF1D3557);
        textColor = Colors.white;
        border = null;
      case _CapsuleStyle.blue:
        bgColor = const Color(0xFF3B82F6);
        textColor = Colors.white;
        border = null;
      case _CapsuleStyle.outline:
        bgColor = Colors.white;
        textColor = AppColors.textPrimary;
        border = Border.all(color: const Color(0xFFE2E8F0), width: 1.5);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.poppins(
                fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(50),
            border: border,
            boxShadow: style != _CapsuleStyle.outline
                ? [BoxShadow(color: bgColor.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))]
                : null,
          ),
          child: Text(value,
              style: GoogleFonts.poppins(
                  fontSize: 13, fontWeight: FontWeight.w700, color: textColor)),
        ),
      ],
    );
  }
}

// ─── Shared dashboard card shell ────────────────────────────────────────────────

class _DashCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final String? seeAllRoute;
  const _DashCard({required this.title, required this.icon, required this.child, this.seeAllRoute});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x0E000000), blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 0),
            child: Row(
              children: [
                Icon(icon, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(title, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
                const Spacer(),
                if (seeAllRoute != null)
                  TextButton(
                    onPressed: () => context.go(seeAllRoute!),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: const Size(40, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text('See all →', style: GoogleFonts.poppins(fontSize: 11, color: AppColors.accent)),
                  ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

// ─── Test Results Bar Chart ────────────────────────────────────────────────────

class _StudentWebTestChart extends ConsumerWidget {
  const _StudentWebTestChart();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gradesAsync = ref.watch(studentOnlineGradesProvider(null));

    return _DashCard(
      title: 'Test Results',
      icon: Icons.bar_chart_rounded,
      seeAllRoute: '${RouteNames.studentDashboard}/grades',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: gradesAsync.when(
          loading: () => const SizedBox(height: 160, child: Center(child: CircularProgressIndicator())),
          error: (_, __) => const SizedBox(height: 160, child: Center(child: Text('No data'))),
          data: (grades) {
            if (grades.isEmpty) {
              return const SizedBox(
                height: 160,
                child: Center(child: Text('No test results yet', style: TextStyle(color: AppColors.textMuted))),
              );
            }
            final last5 = grades.take(5).toList().reversed.toList();
            return SizedBox(
              height: 160,
              child: BarChart(
                BarChartData(
                  maxY: 100,
                  minY: 0,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 25,
                    getDrawingHorizontalLine: (_) => FlLine(color: const Color(0xFFE5E7EB), strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: 25,
                      getTitlesWidget: (v, _) => Text('${v.toInt()}%', style: GoogleFonts.poppins(fontSize: 9, color: AppColors.textMuted)),
                    )),
                    bottomTitles: AxisTitles(sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= last5.length) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            last5[i].subject.length > 4 ? last5[i].subject.substring(0, 4) : last5[i].subject,
                            style: GoogleFonts.poppins(fontSize: 9, color: AppColors.textMuted),
                          ),
                        );
                      },
                    )),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  barGroups: List.generate(last5.length, (i) {
                    final pct = last5[i].percentage.clamp(0.0, 100.0);
                    final color = pct >= 75
                        ? const Color(0xFF10B981)
                        : pct >= 50
                            ? const Color(0xFFF59E0B)
                            : const Color(0xFFEF4444);
                    return BarChartGroupData(x: i, barRods: [
                      BarChartRodData(
                        toY: pct,
                        color: color,
                        width: 28,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                      ),
                    ]);
                  }),
                ),
                swapAnimationDuration: const Duration(milliseconds: 300),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── Weekly Attendance Box ─────────────────────────────────────────────────────

class _StudentWebAttendanceBox extends ConsumerWidget {
  const _StudentWebAttendanceBox();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attendanceAsync = ref.watch(studentAttendanceProvider);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x0E000000), blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: attendanceAsync.when(
        loading: () => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
        error: (_, __) => const SizedBox(height: 200, child: Center(child: Text('No data'))),
        data: (records) {
          // ── Compute stats ──────────────────────────────────────────
          // Group records by date string
          final Map<String, List<dynamic>> byDate = {};
          for (final r in records) {
            final key = _fmtYMD.format(r.date);
            byDate.putIfAbsent(key, () => []).add(r);
          }

          int presentDays = 0, absentDays = 0, partialDays = 0;
          for (final recs in byDate.values) {
            final p = recs.where((r) => r.isPresent).length;
            final a = recs.length - p;
            if (p > 0 && a > 0) {
              partialDays++;
            } else if (p > 0) {
              presentDays++;
            } else {
              absentDays++;
            }
          }
          final totalDays = presentDays + absentDays + partialDays;
          final presentPct = totalDays == 0 ? 0.0 : presentDays / totalDays;
          final absentPct = totalDays == 0 ? 0.0 : absentDays / totalDays;
          final partialPct = totalDays == 0 ? 0.0 : partialDays / totalDays;
          final overallPct = (presentPct * 100).round();

          // ── Last 5 days that have records ──────────────────────────
          final sortedDates = byDate.keys.toList()..sort((a, b) => b.compareTo(a));
          final last5 = sortedDates.take(5).toList();

          return Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header: title + big % ────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('Attendance',
                        style: GoogleFonts.poppins(
                            fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    const Spacer(),
                    Text('$overallPct%',
                        style: GoogleFonts.poppins(
                            fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.primary)),
                  ],
                ),
                const SizedBox(height: 14),

                // ── Three segmented bars ─────────────────────────────
                Row(
                  children: [
                    _AttendanceBar(
                      label: '${(presentPct * 100).round()}%',
                      sublabel: 'Present',
                      flex: presentDays == 0 && totalDays == 0 ? 1 : (presentDays == 0 ? 0 : presentDays),
                      color: const Color(0xFF3B82F6),
                      isFirst: true,
                    ),
                    if (absentDays > 0 || totalDays == 0) _AttendanceBar(
                      label: '${(absentPct * 100).round()}%',
                      sublabel: 'Absent',
                      flex: absentDays == 0 ? 0 : absentDays,
                      color: const Color(0xFF1D3557),
                      isFirst: presentDays == 0,
                    ),
                    if (partialDays > 0 || totalDays == 0) _AttendanceBar(
                      label: '${(partialPct * 100).round()}%',
                      sublabel: 'Partial',
                      flex: partialDays == 0 ? 0 : partialDays,
                      color: const Color(0xFF94A3B8),
                      isFirst: presentDays == 0 && absentDays == 0,
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // ── Dark blue last-5-days box ─────────────────────────
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1D3557),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Sub-header
                      Row(
                        children: [
                          Text('Last 5 Days',
                              style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                          const Spacer(),
                          Text(
                            '${last5.where((d) {
                              final recs = byDate[d]!;
                              final p = recs.where((r) => r.isPresent).length;
                              return p > recs.length ~/ 2;
                            }).length}/5',
                            style: GoogleFonts.poppins(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Colors.white),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // List of last 5 days
                      if (last5.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text('No attendance records yet',
                              style: GoogleFonts.poppins(
                                  fontSize: 11, color: Colors.white54)),
                        )
                      else
                        ...last5.map((dateStr) {
                          final recs = byDate[dateStr]!;
                          final presentCount = recs.where((r) => r.isPresent).length;
                          final isPresent = presentCount > recs.length ~/ 2;
                          final isPartial = presentCount > 0 && !isPresent;
                          final date = DateTime.parse(dateStr);
                          final dayName = _fmtEEEE.format(date);
                          final dayDate = _fmtMMMd.format(date);

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    isPartial
                                        ? Icons.remove_circle_outline
                                        : isPresent
                                            ? Icons.check_circle_outline
                                            : Icons.cancel_outlined,
                                    size: 18,
                                    color: isPartial
                                        ? const Color(0xFFFBBF24)
                                        : isPresent
                                            ? const Color(0xFF34D399)
                                            : const Color(0xFFF87171),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(dayName,
                                          style: GoogleFonts.poppins(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white)),
                                      Text(dayDate,
                                          style: GoogleFonts.poppins(
                                              fontSize: 10,
                                              color: Colors.white54)),
                                    ],
                                  ),
                                ),
                                Container(
                                  width: 26,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color: isPartial
                                        ? const Color(0xFFFBBF24).withOpacity(0.2)
                                        : isPresent
                                            ? const Color(0xFF34D399).withOpacity(0.2)
                                            : const Color(0xFFF87171).withOpacity(0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isPartial
                                        ? Icons.remove_rounded
                                        : isPresent
                                            ? Icons.check_rounded
                                            : Icons.close_rounded,
                                    size: 14,
                                    color: isPartial
                                        ? const Color(0xFFFBBF24)
                                        : isPresent
                                            ? const Color(0xFF34D399)
                                            : const Color(0xFFF87171),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),

                // ── See all link ─────────────────────────────────────
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => context.go('${RouteNames.studentDashboard}/attendance'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: const Size(40, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text('See all →',
                        style: GoogleFonts.poppins(fontSize: 11, color: AppColors.accent)),
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

// ─── Segmented attendance bar ──────────────────────────────────────────────────

class _AttendanceBar extends StatelessWidget {
  final String label;
  final String sublabel;
  final int flex;
  final Color color;
  final bool isFirst;
  const _AttendanceBar({
    required this.label,
    required this.sublabel,
    required this.flex,
    required this.color,
    this.isFirst = false,
  });

  @override
  Widget build(BuildContext context) {
    if (flex == 0) return const SizedBox.shrink();
    return Expanded(
      flex: flex,
      child: Padding(
        padding: EdgeInsets.only(left: isFirst ? 0 : 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Container(
              height: 36,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(sublabel,
                  style: GoogleFonts.poppins(
                      fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Today's Timetable Box ─────────────────────────────────────────────────────

class _StudentWebTimetableBox extends ConsumerWidget {
  final String todayString;
  const _StudentWebTimetableBox({required this.todayString});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timetableAsync = ref.watch(studentTimetableProvider(todayString));

    return _DashCard(
      title: "Today's Timetable",
      icon: Icons.calendar_today_rounded,
      seeAllRoute: '${RouteNames.studentDashboard}/timetable',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: timetableAsync.when(
          loading: () => const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
          error: (_, __) => const SizedBox(height: 80, child: Center(child: Text('No data'))),
          data: (slots) {
            if (slots.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: Text('No classes today', style: TextStyle(color: AppColors.textMuted))),
              );
            }
            return Column(
              children: slots.map((s) => _WebTimetableRow(slot: s)).toList(),
            );
          },
        ),
      ),
    );
  }
}

class _WebTimetableRow extends StatelessWidget {
  final TimetableSlotModel slot;
  const _WebTimetableRow({required this.slot});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    bool isNow = false;
    if (!slot.isHoliday && slot.startTime != null && slot.endTime != null) {
      try {
        final parts1 = slot.startTime!.split(':');
        final parts2 = slot.endTime!.split(':');
        final start = DateTime(now.year, now.month, now.day, int.parse(parts1[0]), int.parse(parts1[1]));
        final end = DateTime(now.year, now.month, now.day, int.parse(parts2[0]), int.parse(parts2[1]));
        isNow = now.isAfter(start) && now.isBefore(end);
      } catch (_) {}
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isNow ? AppColors.primary.withOpacity(0.06) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: isNow ? Border.all(color: AppColors.primary.withOpacity(0.3)) : null,
      ),
      child: Row(
        children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              color: isNow ? AppColors.primary : AppColors.iconContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text('P${slot.periodNumber}', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: isNow ? Colors.white : AppColors.primary)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  slot.isHoliday
                      ? 'Holiday'
                      : (slot.subject?.isNotEmpty == true
                          ? slot.subject!
                          : slot.teacherUsername ?? 'Period ${slot.periodNumber}'),
                  style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
                if (!slot.isHoliday && slot.startTime != null)
                  Text('${slot.startTime} – ${slot.endTime}', style: GoogleFonts.poppins(fontSize: 10, color: AppColors.textMuted)),
              ],
            ),
          ),
          if (isNow)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(8)),
              child: Text('NOW', style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
        ],
      ),
    );
  }
}

// ─── Broadcasts Box ─────────────────────────────────────────────────────────────

class _StudentWebBroadcastsBox extends ConsumerWidget {
  const _StudentWebBroadcastsBox();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final broadcastsAsync = ref.watch(studentBroadcastsProvider);
    final lastSeen = ref.watch(studentBroadcastBadgeNotifier);

    return _DashCard(
      title: 'Broadcasts',
      icon: Icons.campaign_outlined,
      seeAllRoute: '${RouteNames.studentDashboard}/broadcasts',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: broadcastsAsync.when(
          loading: () => const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
          error: (_, __) => const SizedBox(height: 80, child: Center(child: Text('No data'))),
          data: (list) {
            if (list.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: Text('No broadcasts yet', style: TextStyle(color: AppColors.textMuted))),
              );
            }
            return Column(
              children: list.take(4).map((b) {
                final isNew = lastSeen == null || b.createdAt.isAfter(lastSeen);
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isNew ? AppColors.accent.withOpacity(0.06) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: isNew ? Border.all(color: AppColors.accent.withOpacity(0.25)) : null,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.accent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.campaign_outlined, size: 16, color: AppColors.accent),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(b.title, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
                            Text(b.message, style: GoogleFonts.poppins(fontSize: 10, color: AppColors.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(_fmtDMon.format(b.createdAt), style: GoogleFonts.poppins(fontSize: 10, color: AppColors.accent)),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }
}

