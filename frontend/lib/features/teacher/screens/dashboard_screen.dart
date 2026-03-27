import 'dart:async';

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
import '../../../core/providers/badge_provider.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/badge_dot.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/teacher_provider.dart';
import '../widgets/teacher_bottom_nav.dart';

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
    extends ConsumerState<TeacherDashboardScreen> {
  StreamSubscription<Map<String, dynamic>>? _wsSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _connectWs());
  }

  void _connectWs() {
    final userId = ref.read(authProvider).userId;
    if (userId == null) return;
    final ws = ref.read(webSocketClientProvider);
    _wsSub = ws.connect(userId).listen((event) {
      final eventType = event['event'] as String?;
      if (eventType == 'profile_updated' && mounted) {
        _showProfileUpdatedDialog(event['new_username'] as String?);
      } else if ((eventType == 'test_completed' ||
              eventType == 'test_status_changed') &&
          mounted) {
        ref.invalidate(teacherTestsProvider);
      }
    });
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
    _wsSub?.cancel();
    super.dispose();
  }

  String get _todayString => DateFormat('yyyy-MM-dd').format(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final timetableAsync = ref.watch(myTimetableProvider);

    // Broadcast badge
    final lastSeenBroadcast = ref.watch(teacherBroadcastBadgeNotifier);
    final broadcastsAsync = ref.watch(teacherBroadcastsProvider);
    final hasBroadcastBadge = broadcastsAsync.maybeWhen(
      data: (list) {
        if (list.isEmpty) return false;
        final latest = list.map((b) => b.createdAt).reduce((a, b) => a.isAfter(b) ? a : b);
        return lastSeenBroadcast == null || latest.isAfter(lastSeenBroadcast);
      },
      orElse: () => false,
    );

    final mq = MediaQuery.of(context);
    final topPadding = mq.padding.top;
    final screenWidth = mq.size.width;
    final screenHeight = mq.size.height;

    // Filter today's slots from all upcoming slots
    final todaySlots = timetableAsync.maybeWhen(
      data: (slots) =>
          slots.where((s) => s.slotDate == _todayString).toList(),
      orElse: () => <TimetableSlotModel>[],
    );

    final subjects = timetableAsync.maybeWhen(
      data: (slots) => slots.map((s) => s.subject).toSet().toList()..sort(),
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

    // Responsive logo / text sizes for header
    final double logoH = (screenWidth * 0.142).clamp(42.0, 58.0);
    final double titleFs = (screenWidth * 0.062).clamp(18.0, 25.0);

    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: const TeacherBottomNav(),
      body: CustomScrollView(
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
                            Image.asset(
                              'assets/images/logo.png',
                              height: logoH,
                              fit: BoxFit.contain,
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
                        onPressed: () =>
                            ref.read(authProvider.notifier).logout(),
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
                                  _Badge(label: 'TEACHER'),
                                  ...subjects.map((s) => _SubjectChip(subject: s)),
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
                      DateFormat('EEE, d MMM').format(DateTime.now()),
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
          timetableAsync.when(
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
            child: Consumer(builder: (context, ref, _) {
              final hwAsync = ref.watch(teacherHomeworkProvider(null));
              return hwAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: LinearProgressIndicator(),
                ),
                error: (_, __) => const SizedBox.shrink(),
                data: (list) => list.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Text('No homework yet',
                          style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textMuted),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : Column(
                        children: list.take(2).map((h) => _DashHomeworkTile(hw: h)).toList(),
                      ),
              );
            }),
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
            child: Consumer(builder: (context, ref, _) {
              final bcAsync = ref.watch(teacherBroadcastsProvider);
              return bcAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: LinearProgressIndicator(),
                ),
                error: (_, __) => const SizedBox.shrink(),
                data: (list) => list.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Text('No announcements yet',
                          style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textMuted),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : Column(
                        children: list.take(2).map((b) => _DashBroadcastTile(broadcast: b, lastSeen: lastSeenBroadcast)).toList(),
                      ),
              );
            }),
          ),
          SliverToBoxAdapter(child: SizedBox(height: _s(context, 16, min: 12, max: 24))),

        ],
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
              DateFormat('d MMM').format(hw.createdAt),
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
              DateFormat('d MMM').format(broadcast.createdAt),
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
            ? Image.network(photoUrl!, fit: BoxFit.cover)
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
                fontSize: (sw * 0.024).clamp(9.0, 11.0),
                fontWeight: FontWeight.w700,
                color: onDark,
              ),
            ),
          ),
          const Spacer(),
          // Subject
          Text(
            slot.isHoliday ? 'Holiday' : slot.subject,
            style: GoogleFonts.poppins(
              fontSize: (sw * 0.031).clamp(11.0, 14.0),
              fontWeight: FontWeight.w700,
              color: onDark,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          // Grade • time
          Text(
            slot.isHoliday
                ? (slot.comment ?? '')
                : 'Grade ${slot.grade}${slot.startTime != null ? ' • ${slot.startTime}' : ''}',
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
                  slot.isHoliday ? 'Holiday' : slot.subject,
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
