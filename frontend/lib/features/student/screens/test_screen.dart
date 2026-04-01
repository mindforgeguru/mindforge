import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/models/test.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/constants.dart';
import '../../../core/utils/responsive.dart';
import '../providers/student_provider.dart';
import '../widgets/student_bottom_nav.dart';

class StudentTestScreen extends ConsumerWidget {
  const StudentTestScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Tests'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
                padding: const EdgeInsets.all(3),
                child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
              ),
            ),
          ],
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorColor: AppColors.accent,
            tabs: [
              Tab(text: 'Online'),
              Tab(text: 'Offline'),
              Tab(text: 'Completed'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _OnlineTestsTab(),
            _OfflineTestsTab(),
            _CompletedTestsTab(),
          ],
        ),
        bottomNavigationBar: const StudentBottomNav(),
      ),
    );
  }
}

// ─── Online pending tests ─────────────────────────────────────────────────────

class _OnlineTestsTab extends ConsumerWidget {
  const _OnlineTestsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pendingTestsProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (tests) {
        if (tests.isEmpty) {
          return const _EmptyState(
            icon: Icons.check_circle_outline,
            message: 'No pending online tests.',
            sub: 'Check back later.',
          );
        }
        return RefreshIndicator(
          onRefresh: () => ref.refresh(pendingTestsProvider.future),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: tests.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (ctx, i) => _OnlineTestCard(test: tests[i]),
          ),
        );
      },
    );
  }
}

class _OnlineTestCard extends StatelessWidget {
  final TestModel test;
  const _OnlineTestCard({required this.test});

  Duration get _timeLeft {
    if (test.expiresAt == null) return Duration.zero;
    return test.expiresAt!.difference(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final tl = _timeLeft;
    final isUrgent = tl.inHours < 6;

    return Container(
      decoration: mindForgeCardDecoration(
        color: isUrgent ? AppColors.error.withValues(alpha: 0.04) : AppColors.cardBackground,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                const Icon(Icons.computer, color: AppColors.secondary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(test.title, style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis),
                ),
                if (isUrgent) const Icon(Icons.warning_amber, color: AppColors.error, size: 20),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _Chip(label: test.subject, color: AppColors.secondary),
                    _Chip(label: 'Grade ${test.grade}', color: AppColors.primary),
                    _Chip(label: '${test.questionCount} Qs', color: AppColors.textSecondary),
                    _Chip(label: '${test.totalMarks.toInt()} marks', color: AppColors.accent),
                    if (test.timeLimitMinutes != null)
                      _Chip(label: '${test.timeLimitMinutes} min', color: AppColors.info),
                  ],
                ),
                if (test.expiresAt != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.timer_outlined, size: 13,
                          color: isUrgent ? AppColors.error : AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text(
                        'Expires ${DateFormat('dd MMM, hh:mm a').format(test.expiresAt!.toLocal())}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isUrgent ? AppColors.error : AppColors.textMuted,
                          fontWeight: isUrgent ? FontWeight.bold : null,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Start Test'),
                    onPressed: () => context.go(
                      '${RouteNames.studentDashboard}/tests/${test.id}/attempt',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Offline tests (view only) ────────────────────────────────────────────────

class _OfflineTestsTab extends ConsumerWidget {
  const _OfflineTestsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(offlineTestsProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (tests) {
        if (tests.isEmpty) {
          return const _EmptyState(
            icon: Icons.print_outlined,
            message: 'No offline tests yet.',
            sub: 'Offline tests assigned by your teacher will appear here.',
          );
        }
        return RefreshIndicator(
          onRefresh: () => ref.refresh(offlineTestsProvider.future),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: tests.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (ctx, i) => _OfflineTestCard(test: tests[i]),
          ),
        );
      },
    );
  }
}

class _OfflineTestCard extends StatelessWidget {
  final TestModel test;
  const _OfflineTestCard({required this.test});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: mindForgeCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                const Icon(Icons.print_outlined, color: AppColors.accent, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(test.title, style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('OFFLINE',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                          color: AppColors.accent)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _Chip(label: test.subject, color: AppColors.secondary),
                    _Chip(label: 'Grade ${test.grade}', color: AppColors.primary),
                    _Chip(label: '${test.questionCount} Qs', color: AppColors.textSecondary),
                    _Chip(label: '${test.totalMarks.toInt()} marks', color: AppColors.accent),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Created ${DateFormat('dd MMM yyyy').format(test.createdAt.toLocal())}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.info.withValues(alpha: 0.2)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, size: 14, color: AppColors.info),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'This is an offline test. Take it in class. Grades will be entered by your teacher.',
                          style: TextStyle(fontSize: 12, color: AppColors.info),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Completed online tests ───────────────────────────────────────────────────

class _CompletedTestsTab extends ConsumerWidget {
  const _CompletedTestsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(completedTestsProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (tests) {
        if (tests.isEmpty) {
          return const _EmptyState(
            icon: Icons.assignment_turned_in_outlined,
            message: 'No completed tests yet.',
            sub: 'Tests you submit will appear here.',
          );
        }
        return RefreshIndicator(
          onRefresh: () => ref.refresh(completedTestsProvider.future),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: tests.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (ctx, i) => _CompletedTestCard(test: tests[i]),
          ),
        );
      },
    );
  }
}

class _CompletedTestCard extends StatelessWidget {
  final TestModel test;
  const _CompletedTestCard({required this.test});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go(
        '${RouteNames.studentDashboard}/tests/${test.id}/review',
      ),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: mindForgeCardDecoration(),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: R.fluid(context, 44, min: 40, max: 52),
              height: R.fluid(context, 44, min: 40, max: 52),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, color: AppColors.success),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(test.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text('${test.subject} · ${test.totalMarks.toInt()} marks',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  const Text('Tap to review answers',
                      style: TextStyle(fontSize: 11, color: AppColors.primary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String sub;
  const _EmptyState({required this.icon, required this.message, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text(message, style: const TextStyle(fontSize: 16, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(sub,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
