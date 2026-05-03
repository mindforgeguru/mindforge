import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/models/xp.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/constants.dart';
import '../providers/xp_provider.dart';
import '../widgets/student_scaffold.dart';
import '../widgets/theme_picker.dart';
import '../widgets/xp_progress_bar.dart';

final _fmtDate = DateFormat('d MMM • h:mm a');

class XpDashboardScreen extends ConsumerWidget {
  const XpDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final xpAsync = ref.watch(studentXpProvider);

    return StudentScaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'XP & Levels',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Leaderboard',
            icon: const Icon(Icons.leaderboard_rounded),
            onPressed: () =>
                context.go('${RouteNames.studentDashboard}/xp/leaderboard'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(studentXpProvider),
        child: xpAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorView(
            error: e.toString(),
            onRetry: () => ref.invalidate(studentXpProvider),
          ),
          data: (xp) => _XpBody(xp: xp),
        ),
      ),
    );
  }
}

class _XpBody extends ConsumerWidget {
  final StudentXPDetails xp;
  const _XpBody({required this.xp});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(currentPaletteProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Hero — total XP, tinted to selected theme
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [palette.primary, palette.primaryLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.10),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.bolt_rounded,
                  size: 40, color: Colors.amberAccent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total XP',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.7),
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${xp.totalXp}',
                      style: GoogleFonts.poppins(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'LEVEL',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: Colors.white.withOpacity(0.7),
                      letterSpacing: 1.5,
                    ),
                  ),
                  Text(
                    '${xp.currentLevel}',
                    style: GoogleFonts.poppins(
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      color: palette.accent,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Progress to next level
        XPProgressBar(
          currentLevel: xp.currentLevel,
          currentLevelTitle: xp.currentLevelTitle,
          xpIntoLevel: xp.xpIntoLevel,
          xpForNextLevel: xp.xpForNextLevel,
          progress: xp.progressToNextLevel,
        ),
        if (xp.nextLevelTitle != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Next: ${xp.nextLevelTitle} (Level ${xp.nextLevel})',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),

        // Recent activity
        Text(
          'Recent Activity',
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 8),
        if (xp.recentTransactions.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            alignment: Alignment.center,
            child: Text(
              'No XP earned yet — show up, finish your homework, and ace tests.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: AppColors.textMuted,
              ),
            ),
          )
        else
          ...xp.recentTransactions.map((t) => _TxnRow(txn: t)),

        const SizedBox(height: 24),

        // Cosmetic theme picker — Phase 3 unlock mechanic
        const ThemePicker(),
      ],
    );
  }
}

class _TxnRow extends StatelessWidget {
  final XPTransactionModel txn;
  const _TxnRow({required this.txn});

  @override
  Widget build(BuildContext context) {
    final isPositive = txn.amount >= 0;
    final amountColor = isPositive ? AppColors.success : AppColors.error;
    final icon = _iconForReason(txn.reason);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration:       BoxDecoration(
              color: AppColors.iconContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  txn.description ?? _humanReason(txn.reason),
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _fmtDate.format(txn.createdAt.toLocal()),
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${isPositive ? '+' : ''}${txn.amount}',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: amountColor,
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForReason(String reason) {
    switch (reason) {
      case 'ATTENDANCE':
        return Icons.event_available_rounded;
      case 'HOMEWORK_ON_TIME':
      case 'HOMEWORK_LATE':
        return Icons.edit_note_rounded;
      case 'TEST_SCORE':
      case 'TEST_PERFECT':
        return Icons.quiz_rounded;
      case 'STREAK_BONUS':
        return Icons.local_fire_department_rounded;
      case 'MANUAL_ADJUSTMENT':
        return Icons.admin_panel_settings_rounded;
      default:
        return Icons.bolt_rounded;
    }
  }

  String _humanReason(String reason) {
    switch (reason) {
      case 'ATTENDANCE':
        return 'Attendance';
      case 'HOMEWORK_ON_TIME':
        return 'Homework — on time';
      case 'HOMEWORK_LATE':
        return 'Homework — late';
      case 'TEST_SCORE':
        return 'Test score';
      case 'TEST_PERFECT':
        return 'Perfect test score';
      case 'STREAK_BONUS':
        return 'Streak bonus';
      case 'MANUAL_ADJUSTMENT':
        return 'Manual adjustment';
      default:
        return reason;
    }
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text(
              'Could not load XP.',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              error,
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: AppColors.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
