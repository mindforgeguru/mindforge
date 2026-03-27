import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/constants.dart';
import '../../../core/utils/responsive.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/admin_provider.dart';
import '../widgets/admin_bottom_nav.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final pendingAsync = ref.watch(pendingUsersProvider);
    final currentYearAsync = ref.watch(currentAcademicYearProvider);
    final topPadding = MediaQuery.of(context).padding.top;

    final int pendingCount = pendingAsync.when(
      data: (users) => users.length,
      loading: () => 0,
      error: (_, __) => 0,
    );
    final String? currentYear =
        currentYearAsync.valueOrNull?['year_label'] as String?;

    final double avatarRadius = R.fluid(context, 46, min: 36, max: 54);
    const double cardRadius = 24.0;
    const double cardHMargin = 16.0;
    final double cardIntoNavy = R.fluid(context, 56, min: 44, max: 64);
    final double navyH = topPadding + R.fluid(context, 108, min: 90, max: 128);
    final double cardInternalH = currentYear != null ? R.fluid(context, 155, min: 130, max: 175) : R.fluid(context, 130, min: 110, max: 150);
    final double headerH = navyH + cardInternalH - cardIntoNavy + avatarRadius;

    final cards = [
      _DashCard(icon: Icons.account_balance_wallet_outlined, label: 'Fees',
          subtitle: 'Payment records', color: AppColors.accent,
          route: '${RouteNames.adminDashboard}/fees', badge: 0),
      _DashCard(icon: Icons.calendar_month_outlined, label: 'Timetable',
          subtitle: 'Manage schedule', color: AppColors.primary,
          route: '${RouteNames.adminDashboard}/timetable', badge: 0),
      _DashCard(icon: Icons.people_outlined, label: 'Users',
          subtitle: 'Manage accounts', color: AppColors.secondary,
          route: '${RouteNames.adminDashboard}/users', badge: pendingCount),
      _DashCard(icon: Icons.auto_awesome_outlined, label: 'New Year',
          subtitle: 'Academic year', color: AppColors.error,
          route: '${RouteNames.adminDashboard}/academic-year', badge: 0),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: const AdminBottomNav(),
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
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(44),
                          bottomRight: Radius.circular(44),
                        ),
                      ),
                    ),
                  ),

                  // Top nav row
                  Positioned(
                    top: topPadding + 14,
                    left: 22,
                    right: 6,
                    child: Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('MIND', style: GoogleFonts.poppins(
                                fontSize: 20, fontWeight: FontWeight.w800,
                                color: Colors.white, height: 1.1, letterSpacing: 1)),
                            Text('FORGE', style: GoogleFonts.poppins(
                                fontSize: 20, fontWeight: FontWeight.w800,
                                color: Colors.white, height: 1.1, letterSpacing: 1)),
                          ],
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.person_outline_rounded,
                              color: Colors.white, size: 26),
                          onPressed: () =>
                              context.go('${RouteNames.adminDashboard}/profile'),
                        ),
                        IconButton(
                          icon: const Icon(Icons.logout,
                              color: Colors.white, size: 24),
                          onPressed: () =>
                              ref.read(authProvider.notifier).logout(),
                        ),
                      ],
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
                              20, avatarRadius + 14, 20, 20),
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
                              Text(
                                'Welcome back, ${auth.username ?? 'Admin'}',
                                style: GoogleFonts.poppins(
                                    fontSize: R.fs(context, 18, min: 15, max: 22), fontWeight: FontWeight.w700,
                                    color: AppColors.primary),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                alignment: WrapAlignment.center,
                                children: [
                                  _Badge(label: 'ADMIN'),
                                  if (currentYear != null)
                                    _Badge(
                                        label: currentYear,
                                        color: AppColors.success),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          top: 0,
                          child: _ProfileAvatar(
                            username: auth.username ?? 'A',
                            photoUrl: auth.profilePicUrl,
                            radius: avatarRadius,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Pending users banner ──────────────────────────────────────
          if (pendingCount > 0)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.1),
                  border: Border.all(color: AppColors.warning),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber, color: AppColors.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$pendingCount user(s) awaiting approval.',
                        style: const TextStyle(
                            color: AppColors.warning,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          context.go('${RouteNames.adminDashboard}/users'),
                      child: const Text('Review'),
                    ),
                  ],
                ),
              ),
            ),

          // ── Feature cards grid ────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _DashboardCard(card: cards[i]),
                childCount: cards.length,
              ),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Shared Widgets ───────────────────────────────────────────────────────────

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
                    username.isNotEmpty ? username[0].toUpperCase() : 'A',
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
  final Color? color;
  const _Badge({required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: c.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
            fontSize: 12, fontWeight: FontWeight.w600, color: c),
      ),
    );
  }
}

// ─── Dash Card Model ──────────────────────────────────────────────────────────

class _DashCard {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final String route;
  final int badge;
  const _DashCard({required this.icon, required this.label,
      required this.subtitle, required this.color, required this.route,
      this.badge = 0});
}

// ─── Dashboard Card ───────────────────────────────────────────────────────────

class _DashboardCard extends StatelessWidget {
  final _DashCard card;
  const _DashboardCard({required this.card});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go(card.route),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: card.color.withOpacity(0.14),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: card.color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(card.icon, size: 24, color: card.color),
                    ),
                    Icon(Icons.arrow_forward_rounded,
                        size: 16, color: card.color.withOpacity(0.45)),
                  ],
                ),
                const Spacer(),
                Text(card.label,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 3),
                Text(card.subtitle,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
            if (card.badge > 0)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                      color: AppColors.error, shape: BoxShape.circle),
                  child: Text('${card.badge}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
