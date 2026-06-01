import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/xp_provider.dart';
import '../widgets/leaderboard_tile.dart';
import '../widgets/student_scaffold.dart';

/// Leaderboard screen with three tabs:
///   - **Class** — ranking within the viewer's grade
///   - **Points Table** — static reference of XP awarded per action
///   - **All** — global ranking across the school
class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    final tabBar = TabBar(
      labelColor: Colors.white,
      unselectedLabelColor: Colors.white60,
      indicatorColor: AppColors.accent,
      tabs: const [
        Tab(text: 'Class'),
        Tab(text: 'Points Table'),
        Tab(text: 'All'),
      ],
    );

    const tabBarView = TabBarView(
      children: [
        _LeaderboardTab(scope: 'class'),
        _PointsTableTab(),
        _LeaderboardTab(scope: 'school'),
      ],
    );

    if (isWide) {
      // StudentScaffold drops `appBar` on web (the top nav replaces it),
      // which would also drop the TabBar living inside AppBar.bottom. So
      // on web we inline the TabBar at the top of the body — same pattern
      // used by test_screen.
      return DefaultTabController(
        length: 3,
        child: StudentScaffold(
          backgroundColor: AppColors.background,
          wideContent: true,
          body: Padding(
            padding: const EdgeInsets.fromLTRB(48, 28, 48, 20),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(Icons.leaderboard_outlined,
                            size: 16, color: AppColors.primary),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Leaderboard',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: tabBar,
                  ),
                  const SizedBox(height: 8),
                  const Expanded(child: tabBarView),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: StudentScaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Leaderboard'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                ),
                padding: const EdgeInsets.all(3),
                child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
              ),
            ),
          ],
          bottom: tabBar,
        ),
        body: tabBarView,
      ),
    );
  }
}

class _LeaderboardTab extends ConsumerWidget {
  final String scope;
  const _LeaderboardTab({required this.scope});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(leaderboardProvider(scope));
    final myUserId = ref.watch(authProvider).userId;

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(leaderboardProvider(scope)),
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not load leaderboard.\n$e',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ),
        data: (board) {
          if (board.entries.isEmpty) {
            return Center(
              child: Text(
                'No XP earned in this scope yet.',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: board.entries.length,
            itemBuilder: (_, i) {
              final e = board.entries[i];
              return LeaderboardTile(entry: e, isMe: e.studentId == myUserId);
            },
          );
        },
      ),
    );
  }
}

// ─── Points Table tab ─────────────────────────────────────────────────────────
//
// Static reference of how XP is earned. Values mirror constants in
// `backend/app/services/xp_service.py` — keep in sync if the service-side
// table changes.

class _PointsTableTab extends ConsumerWidget {
  const _PointsTableTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(currentPaletteProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // Header callout — palette-tinted gradient.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [palette.primary, palette.primaryLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Icons.bolt_rounded,
                  color: Colors.amberAccent, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'How you earn XP',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Show up. Do the work. Ace your tests.',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        const _SectionLabel(text: 'Attendance'),
        const _PointsRow(
          icon: Icons.event_available_rounded,
          title: 'Marked present',
          subtitle: 'For each period you attend',
          xp: 5,
        ),

        const SizedBox(height: 8),
        const _SectionLabel(text: 'Homework'),
        const _PointsRow(
          icon: Icons.edit_note_rounded,
          title: 'Homework — on time',
          subtitle: 'Completed on or before due date',
          xp: 20,
        ),
        const _PointsRow(
          icon: Icons.edit_note_rounded,
          title: 'Homework — late',
          subtitle: 'Completed after due date',
          xp: 10,
        ),

        const SizedBox(height: 8),
        const _SectionLabel(text: 'Tests'),
        const _PointsRow(
          icon: Icons.quiz_rounded,
          title: 'Test score 50–69%',
          xp: 30,
        ),
        const _PointsRow(
          icon: Icons.quiz_rounded,
          title: 'Test score 70–89%',
          xp: 50,
        ),
        const _PointsRow(
          icon: Icons.quiz_rounded,
          title: 'Test score 90–99%',
          xp: 80,
        ),
        const _PointsRow(
          icon: Icons.workspace_premium_rounded,
          title: 'Perfect test (100%)',
          subtitle: 'Score every question right',
          xp: 120,
        ),

        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Each level you climb unlocks new themes. Reach Level 50 — '
            'Mythic V — to unlock the final theme.',
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: AppColors.textMuted,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 6, bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

class _PointsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final int xp;

  const _PointsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.xp,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.iconContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      subtitle!,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.iconContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '+$xp XP',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
