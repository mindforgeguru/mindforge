import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/api/websocket_client.dart';
import '../../../core/models/homework.dart';
import '../../../core/models/timetable.dart';
import '../../../core/providers/badge_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/constants.dart';
import '../../../core/utils/logout_confirm.dart';
import '../../../core/widgets/badge_dot.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/parent_provider.dart';
import '../widgets/parent_bottom_nav.dart';

// File-level DateFormat cache.
final _fmtYMD   = DateFormat('yyyy-MM-dd');
final _fmtEDMon = DateFormat('EEE, d MMM');
final _fmtDMon  = DateFormat('d MMM');

// ─── Responsive helpers ───────────────────────────────────────────────────────
double _s(BuildContext ctx, double base, {double min = 0, double max = double.infinity}) {
  final w = MediaQuery.of(ctx).size.width;
  final scaled = base * (w / 390.0);
  return scaled.clamp(min == 0 ? base * 0.72 : min, max == double.infinity ? base * 1.4 : max);
}

double _fs(BuildContext ctx, double base, {double min = 10, double max = 22}) =>
    _s(ctx, base, min: min, max: max);

// ─── Screen ───────────────────────────────────────────────────────────────────

class ParentDashboardScreen extends ConsumerStatefulWidget {
  const ParentDashboardScreen({super.key});

  @override
  ConsumerState<ParentDashboardScreen> createState() =>
      _ParentDashboardScreenState();
}

class _ParentDashboardScreenState
    extends ConsumerState<ParentDashboardScreen>
    with WidgetsBindingObserver {
  StreamSubscription<Map<String, dynamic>>? _wsSub;

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
      } else if (eventType == 'timetable_updated') {
        ref.invalidate(parentChildTimetableProvider(_todayString));
      } else if (eventType == 'new_test' || eventType == 'test_status_changed') {
        ref.invalidate(parentChildTestsProvider);
      } else if (eventType == 'child_grade_added') {
        ref.invalidate(parentChildGradesProvider(null));
        ref.invalidate(parentChildOfflineGradesProvider(null));
      } else if (eventType == 'broadcast_created' || eventType == 'homework_added') {
        ref.invalidate(parentBroadcastsProvider);
        ref.invalidate(parentHomeworkProvider);
      }
    });
  }

  Future<void> _refreshDashboard() async {
    ref.invalidate(parentChildTimetableProvider(_todayString));
    ref.invalidate(parentBroadcastsProvider);
    ref.invalidate(parentHomeworkProvider);
    ref.invalidate(parentChildGradesProvider(null));
    ref.invalidate(parentChildTestsProvider);
    ref.invalidate(parentChildFeesProvider);
    await ref.read(parentChildTimetableProvider(_todayString).future).catchError((_) => <dynamic>[]);
  }

  Future<void> _showProfileUpdatedDialog(String? newUsername) async {
    await showDialog<void>(
      context: context,
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
    final timetableAsync =
        ref.watch(parentChildTimetableProvider(_todayString));
    final mq = MediaQuery.of(context);
    final topPadding = mq.padding.top;
    final sw = mq.size.width;
    final sh = mq.size.height;
    final now = DateTime.now();

    // ── Broadcast badge — select() so this boolean is only recomputed when
    // broadcasts or lastSeen actually change, not on every dashboard rebuild.
    final lastSeenBroadcast = ref.watch(parentBroadcastBadgeNotifier);
    final hasBroadcastBadge = ref.watch(parentBroadcastsProvider.select((async) =>
      async.maybeWhen(
        data: (list) {
          if (list.isEmpty) return false;
          DateTime? latest;
          for (final b in list) {
            if (latest == null || b.createdAt.isAfter(latest)) latest = b.createdAt;
          }
          return latest != null && _isNew(lastSeenBroadcast, latest);
        },
        orElse: () => false,
      )));

    // ── Layout geometry — all derived from screen dimensions ─────────────
    final double avatarRadius = (sw * 0.114).clamp(36.0, 50.0);
    final double cardRadius = (sw * 0.062).clamp(20.0, 28.0);
    final double cardHMargin = (sw * 0.04).clamp(12.0, 20.0);
    final double cardIntoNavy = (sh * 0.066).clamp(44.0, 60.0);
    final double navyH = topPadding + (sh * 0.165).clamp(95.0, 142.0);
    // Card height: avatarRadius + top-pad + content + bottom-pad
    final double cardInternalH = (avatarRadius + 90).clamp(128.0, 158.0);
    final double headerH =
        navyH + cardInternalH - cardIntoNavy + avatarRadius;

    final double logoH = (sw * 0.142).clamp(42.0, 58.0);
    final double titleFs = (sw * 0.062).clamp(18.0, 25.0);

    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: const ParentBottomNav(),
      body: RefreshIndicator(
        onRefresh: _refreshDashboard,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [

          // ── Header: navy + white welcome card ─────────────────────────
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
                              (sw * 0.113).clamp(36.0, 48.0)),
                          bottomRight: Radius.circular(
                              (sw * 0.113).clamp(36.0, 48.0)),
                        ),
                      ),
                    ),
                  ),

                  // Logout icon — min 48×48 tap target
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

                  // Logo + wordmark + tagline
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
                                    fontSize: _fs(context, 14, min: 13, max: 16),
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

                  // White welcome card
                  Positioned(
                    top: navyH - cardIntoNavy,
                    left: cardHMargin,
                    right: cardHMargin,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.topCenter,
                      children: [
                        // Card body
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
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'Welcome back, ${auth.username ?? 'Parent'}',
                                  style: GoogleFonts.poppins(
                                    fontSize: _fs(context, 14, min: 12, max: 17),
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              SizedBox(height: _s(context, 6, min: 4, max: 8)),
                              Wrap(
                                spacing: _s(context, 8, min: 6, max: 12),
                                runSpacing: _s(context, 6, min: 4, max: 8),
                                alignment: WrapAlignment.center,
                                children: const [
                                  _Badge(label: 'PARENT'),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Avatar — tappable, min 48×48
                        Positioned(
                          top: 0,
                          child: GestureDetector(
                            onTap: () => context.go(
                                '${RouteNames.parentDashboard}/profile'),
                            child: Stack(
                              alignment: Alignment.bottomRight,
                              children: [
                                _ProfileAvatar(
                                  username: auth.username ?? 'P',
                                  photoUrl: auth.profilePicUrl,
                                  radius: avatarRadius,
                                ),
                                Container(
                                  padding: EdgeInsets.all(
                                      _s(context, 4, min: 3, max: 6)),
                                  decoration: const BoxDecoration(
                                    color: AppColors.accent,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Icons.edit,
                                      size: _s(context, 12, min: 10, max: 15),
                                      color: Colors.white),
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

          // ── Today's Timetable header with "See all →" ─────────────────
          SliverToBoxAdapter(
            child: LayoutBuilder(builder: (context, constraints) {
              final w = constraints.maxWidth;
              return Padding(
                padding: EdgeInsets.fromLTRB(
                  (w * 0.05).clamp(14.0, 22.0),
                  (w * 0.04).clamp(12.0, 20.0),
                  (w * 0.02).clamp(4.0, 10.0),
                  (w * 0.025).clamp(8.0, 12.0),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: (w * 0.038).clamp(13.0, 17.0),
                      color: AppColors.primary,
                    ),
                    SizedBox(width: (w * 0.02).clamp(5.0, 9.0)),
                    Expanded(
                      child: Text(
                        "Today's Timetable",
                        style: GoogleFonts.poppins(
                          fontSize: (w * 0.033).clamp(11.0, 15.0),
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      _fmtEDMon.format(now),
                      style: GoogleFonts.poppins(
                        fontSize: (w * 0.028).clamp(9.5, 12.0),
                        color: AppColors.textMuted,
                      ),
                    ),
                    TextButton(
                      onPressed: () => context
                          .go('${RouteNames.parentDashboard}/timetable'),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                          horizontal: (w * 0.02).clamp(6.0, 10.0),
                          vertical: 4,
                        ),
                        minimumSize: const Size(48, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'See all →',
                        style: GoogleFonts.poppins(
                          fontSize: (w * 0.028).clamp(9.5, 12.0),
                          color: AppColors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),

          // ── Timetable horizontal cards ─────────────────────────────────
          timetableAsync.when(
            loading: () => SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    _s(context, 16, min: 12, max: 20), 0,
                    _s(context, 16, min: 12, max: 20), 16),
                child: const LinearProgressIndicator(),
              ),
            ),
            error: (_, __) =>
                const SliverToBoxAdapter(child: SizedBox.shrink()),
            data: (slots) => SliverToBoxAdapter(
              child:
                  slots.isEmpty ? _TimetableEmpty() : _TimetableHScroll(slots: slots),
            ),
          ),

          // ── Recent Homework ───────────────────────────────────────────
          SliverToBoxAdapter(
            child: _DashSectionHeader(
              icon: Icons.assignment_outlined,
              title: 'Recent Homework',
              onSeeAll: () =>
                  context.go('${RouteNames.parentDashboard}/homework'),
            ),
          ),
          SliverToBoxAdapter(
            child: Consumer(builder: (context, ref, _) {
              final hwAsync = ref.watch(parentHomeworkProvider);
              return hwAsync.when(
                loading: () => Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: _s(context, 16, min: 12, max: 20),
                      vertical: 4),
                  child: const LinearProgressIndicator(),
                ),
                error: (_, __) => const SizedBox.shrink(),
                data: (list) => list.isEmpty
                    ? Padding(
                        padding: EdgeInsets.fromLTRB(
                            _s(context, 16, min: 12, max: 20),
                            0,
                            _s(context, 16, min: 12, max: 20),
                            12),
                        child: Text(
                          'No homework yet',
                          style: GoogleFonts.poppins(
                            fontSize: _fs(context, 11, min: 10, max: 13),
                            color: AppColors.textMuted,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : Column(
                        children: list
                            .take(2)
                            .map((h) => _DashHomeworkTile(hw: h))
                            .toList(),
                      ),
              );
            }),
          ),

          // ── Announcements ─────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _DashSectionHeader(
              icon: Icons.campaign_outlined,
              title: 'Announcements',
              showBadge: hasBroadcastBadge,
              onSeeAll: () {
                ref.read(parentBroadcastBadgeNotifier.notifier).markSeen();
                context.go('${RouteNames.parentDashboard}/homework?tab=1');
              },
            ),
          ),
          SliverToBoxAdapter(
            child: Consumer(builder: (context, ref, _) {
              final bcAsync = ref.watch(parentBroadcastsProvider);
              return bcAsync.when(
                loading: () => Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: _s(context, 16, min: 12, max: 20),
                      vertical: 4),
                  child: const LinearProgressIndicator(),
                ),
                error: (_, __) => const SizedBox.shrink(),
                data: (list) => list.isEmpty
                    ? Padding(
                        padding: EdgeInsets.fromLTRB(
                            _s(context, 16, min: 12, max: 20),
                            0,
                            _s(context, 16, min: 12, max: 20),
                            12),
                        child: Text(
                          'No announcements yet',
                          style: GoogleFonts.poppins(
                            fontSize: _fs(context, 11, min: 10, max: 13),
                            color: AppColors.textMuted,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : Column(
                        children: list
                            .take(2)
                            .map((b) => _DashBroadcastTile(broadcast: b, lastSeen: lastSeenBroadcast))
                            .toList(),
                      ),
              );
            }),
          ),

          SliverToBoxAdapter(
              child: SizedBox(height: _s(context, 24, min: 16, max: 32))),
        ],
        ),
      ),
    );
  }
}

// ─── Section Header ───────────────────────────────────────────────────────────

class _DashSectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onSeeAll;
  final bool showBadge;
  const _DashSectionHeader(
      {required this.icon, required this.title, required this.onSeeAll, this.showBadge = false});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      return Padding(
        padding: EdgeInsets.fromLTRB(
          (w * 0.05).clamp(14.0, 22.0),
          0,
          (w * 0.02).clamp(4.0, 8.0),
          (w * 0.015).clamp(4.0, 8.0),
        ),
        child: Row(
          children: [
            BadgeDot(
              show: showBadge,
              child: Icon(icon, size: (w * 0.038).clamp(13.0, 16.0), color: AppColors.primary),
            ),
            SizedBox(width: (w * 0.02).clamp(5.0, 9.0)),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: (w * 0.033).clamp(11.0, 14.0),
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: onSeeAll,
              style: TextButton.styleFrom(
                padding: EdgeInsets.symmetric(
                    horizontal: (w * 0.02).clamp(6.0, 10.0), vertical: 4),
                minimumSize: const Size(48, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'See all →',
                style: GoogleFonts.poppins(
                  fontSize: (w * 0.028).clamp(10.0, 12.0),
                  color: AppColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}

// ─── Homework Tile ────────────────────────────────────────────────────────────

class _DashHomeworkTile extends StatelessWidget {
  final HomeworkModel hw;
  const _DashHomeworkTile({required this.hw});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final hPad = (w * 0.05).clamp(14.0, 22.0);
      final vPad = (w * 0.022).clamp(8.0, 12.0);
      return Container(
        margin: EdgeInsets.fromLTRB(
            hPad, 0, hPad, (w * 0.018).clamp(5.0, 8.0)),
        padding: EdgeInsets.symmetric(
            horizontal: (w * 0.035).clamp(10.0, 14.0), vertical: vPad),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular((w * 0.025).clamp(8.0, 12.0)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0C1D3557), blurRadius: 6, offset: Offset(0, 2))
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: (w * 0.02).clamp(5.0, 8.0),
                vertical: (w * 0.01).clamp(2.0, 4.0),
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
                  fontSize: (w * 0.025).clamp(9.0, 11.0),
                  fontWeight: FontWeight.w700,
                  color: hw.isOnlineTest
                      ? AppColors.accent
                      : AppColors.primary,
                ),
              ),
            ),
            SizedBox(width: (w * 0.025).clamp(7.0, 10.0)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hw.title,
                    style: GoogleFonts.poppins(
                      fontSize: (w * 0.03).clamp(11.0, 13.0),
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    hw.subject,
                    style: GoogleFonts.poppins(
                      fontSize: (w * 0.026).clamp(9.0, 11.0),
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
                fontSize: (w * 0.025).clamp(9.0, 11.0),
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

// ─── Broadcast Tile ───────────────────────────────────────────────────────────

class _DashBroadcastTile extends StatelessWidget {
  final BroadcastModel broadcast;
  final DateTime? lastSeen;
  const _DashBroadcastTile({required this.broadcast, this.lastSeen});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go('${RouteNames.parentDashboard}/homework?tab=1'),
      child: _buildTile(context),
    );
  }

  Widget _buildTile(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final hPad = (w * 0.05).clamp(14.0, 22.0);
      final vPad = (w * 0.022).clamp(8.0, 12.0);
      final isNew = lastSeen == null || broadcast.createdAt.isAfter(lastSeen!);
      return Container(
        margin: EdgeInsets.fromLTRB(
            hPad, 0, hPad, (w * 0.018).clamp(5.0, 8.0)),
        padding: EdgeInsets.symmetric(
            horizontal: (w * 0.035).clamp(10.0, 14.0), vertical: vPad),
        decoration: BoxDecoration(
          color: isNew ? AppColors.accent.withOpacity(0.07) : Colors.white,
          borderRadius: BorderRadius.circular((w * 0.025).clamp(8.0, 12.0)),
          border: isNew ? Border.all(color: AppColors.accent.withOpacity(0.30), width: 1) : null,
          boxShadow: const [
            BoxShadow(
                color: Color(0x0C1D3557), blurRadius: 6, offset: Offset(0, 2))
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.campaign_outlined,
                size: (w * 0.038).clamp(13.0, 17.0),
                color: AppColors.accent),
            SizedBox(width: (w * 0.025).clamp(7.0, 10.0)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    broadcast.title,
                    style: GoogleFonts.poppins(
                      fontSize: (w * 0.03).clamp(11.0, 13.0),
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    broadcast.message,
                    style: GoogleFonts.poppins(
                      fontSize: (w * 0.026).clamp(9.0, 11.0),
                      color: AppColors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            SizedBox(width: (w * 0.015).clamp(4.0, 8.0)),
            Text(
              _fmtDMon.format(broadcast.createdAt),
              style: GoogleFonts.poppins(
                fontSize: (w * 0.025).clamp(9.0, 11.0),
                color: AppColors.accent,
              ),
            ),
          ],
        ),
      );
    });
  }
}

// ─── Timetable Widgets ────────────────────────────────────────────────────────

class _TimetableEmpty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      return Container(
        margin: EdgeInsets.fromLTRB(
          (w * 0.04).clamp(12.0, 20.0), 0,
          (w * 0.04).clamp(12.0, 20.0), (w * 0.04).clamp(12.0, 20.0),
        ),
        padding: EdgeInsets.all((w * 0.06).clamp(18.0, 28.0)),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular((w * 0.035).clamp(10.0, 16.0)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0C1D3557), blurRadius: 8, offset: Offset(0, 3))
          ],
        ),
        child: Center(
          child: Text(
            'No classes today',
            style: GoogleFonts.poppins(
              fontSize: (w * 0.034).clamp(12.0, 14.0),
              color: AppColors.textMuted,
            ),
          ),
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
      final w = constraints.maxWidth;
      final hPad = (w * 0.04).clamp(12.0, 18.0);
      final gap = (w * 0.018).clamp(5.0, 8.0);
      final n = slots.length;
      final cardW =
          ((w - hPad * 2 - gap * (n - 1)) / n).clamp(44.0, 160.0);
      final cardH = (w * 0.28).clamp(95.0, 122.0);
      return Padding(
        padding: EdgeInsets.fromLTRB(hPad, 0, hPad, (w * 0.03).clamp(10.0, 16.0)),
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
        final end = _parseTime(slot.endTime!, now);
        isNow = now.isAfter(start) && now.isBefore(end);
      } catch (_) {}
    }
    final onDark = isNow ? Colors.white : AppColors.primary;
    final onMuted =
        isNow ? Colors.white.withOpacity(0.72) : AppColors.textMuted;

    return Container(
      width: cardW,
      height: cardH,
      padding: EdgeInsets.all((sw * 0.024).clamp(8.0, 11.0)),
      decoration: BoxDecoration(
        color: isNow ? AppColors.primary : Colors.white,
        borderRadius: BorderRadius.circular((sw * 0.036).clamp(12.0, 16.0)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0E1D3557), blurRadius: 8, offset: Offset(0, 3)),
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
          // Teacher • time
          Text(
            slot.isHoliday
                ? (slot.comment ?? '')
                : '${slot.teacherUsername ?? 'Grade ${slot.grade}'}${slot.startTime != null ? ' • ${slot.startTime}' : ''}',
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

// ─── Profile Avatar ───────────────────────────────────────────────────────────

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
                    username.isNotEmpty ? username[0].toUpperCase() : 'P',
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

// ─── Badge ────────────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final String label;
  const _Badge({required this.label});

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _s(context, 10, min: 8, max: 14),
        vertical: _s(context, 4, min: 3, max: 6),
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

bool _isNew(DateTime? lastSeen, DateTime? latest) {
  if (latest == null) return false;
  if (lastSeen == null) return true;
  return latest.isAfter(lastSeen);
}
