import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/user.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/admin_provider.dart';

class AdminAcademicYearScreen extends ConsumerWidget {
  const AdminAcademicYearScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final yearsAsync = ref.watch(academicYearsProvider);
    final currentAsync = ref.watch(currentAcademicYearProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Academic Year')),
      body: yearsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (years) {
          final current = currentAsync.valueOrNull;
          final previous = years.where((y) => y['is_current'] == false).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── Current year banner ──────────────────────────────────
              _CurrentYearCard(current: current, ref: ref),
              const SizedBox(height: 20),

              // ── Start new year button ────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.error,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.celebration_outlined),
                  label: Text(
                    current == null
                        ? 'Start First Academic Year'
                        : 'Start New Academic Year',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () =>
                      _confirmNewYear(context, ref, current == null),
                ),
              ),

              if (current == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'No active academic year. Start one so users can register.',
                    style: TextStyle(
                        color: AppColors.textMuted, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),

              if (previous.isNotEmpty) ...[
                const SizedBox(height: 28),
                Text(
                  'Previous Years',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                ),
                const SizedBox(height: 12),
                ...previous.map((y) => _PreviousYearCard(year: y)),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmNewYear(
      BuildContext context, WidgetRef ref, bool isFirst) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isFirst ? 'Start Academic Year?' : 'Start New Year?'),
        content: Text(
          isFirst
              ? 'This will create the first academic year and allow users to register.'
              : 'This will:\n\n'
                  '• End the current academic year\n'
                  '• Deactivate all students, teachers & parents\n'
                  '• Clear the timetable\n'
                  '• Everyone must register again\n\n'
                  'Old data is preserved and viewable under Previous Years.\n\n'
                  'Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: isFirst ? AppColors.success : AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isFirst ? 'Start' : 'Yes, Start New Year'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      final api = ref.read(apiClientProvider);
      if (isFirst) {
        await api.initAcademicYear();
      } else {
        await api.startNewAcademicYear();
      }
      ref.invalidate(academicYearsProvider);
      ref.invalidate(currentAcademicYearProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isFirst
                ? 'Academic year started!'
                : 'New academic year started! All users must re-register.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }
}

// ── Current Year Card ─────────────────────────────────────────────────────────

class _CurrentYearCard extends StatelessWidget {
  final Map<String, dynamic>? current;
  final WidgetRef ref;
  const _CurrentYearCard({required this.current, required this.ref});

  @override
  Widget build(BuildContext context) {
    if (current == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: mindForgeCardDecoration(
            color: AppColors.warning.withOpacity(0.08)),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warning_amber,
                  color: AppColors.warning, size: 28),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('No Active Year',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppColors.warning)),
                  SizedBox(height: 4),
                  Text('Users cannot register until a year is started.',
                      style:
                          TextStyle(color: AppColors.textMuted, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final label = current!['year_label'] as String;
    final startedAt = DateTime.parse(current!['started_at'] as String).toLocal();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: mindForgeCardDecoration(
          color: AppColors.success.withOpacity(0.06)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.school_outlined,
                color: AppColors.success, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(label,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                            color: AppColors.success)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('ACTIVE',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.success,
                              letterSpacing: 1)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Started ${_formatDate(startedAt)}',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Previous Year Card ────────────────────────────────────────────────────────

class _PreviousYearCard extends ConsumerWidget {
  final Map<String, dynamic> year;
  const _PreviousYearCard({required this.year});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = year['year_label'] as String;
    final startedAt = DateTime.parse(year['started_at'] as String).toLocal();
    final endedAt = year['ended_at'] != null
        ? DateTime.parse(year['ended_at'] as String).toLocal()
        : null;
    final students = year['students'] as int? ?? 0;
    final teachers = year['teachers'] as int? ?? 0;
    final parents = year['parents'] as int? ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: mindForgeCardDecoration(),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.history_edu_outlined,
                color: AppColors.primary, size: 22),
          ),
          title: Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 15)),
          subtitle: Text(
            '${_formatDate(startedAt)}  –  ${endedAt != null ? _formatDate(endedAt) : "—"}',
            style: const TextStyle(
                color: AppColors.textMuted, fontSize: 12),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StatChip(
                  icon: Icons.school_outlined,
                  count: students,
                  color: AppColors.secondary),
              const SizedBox(width: 4),
              _StatChip(
                  icon: Icons.person_outline,
                  count: teachers,
                  color: AppColors.primary),
              const SizedBox(width: 4),
              const Icon(Icons.expand_more, color: AppColors.textMuted),
            ],
          ),
          children: [
            _YearUserList(yearId: year['id'] as int, ref: ref),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final int count;
  final Color color;
  const _StatChip(
      {required this.icon, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text('$count',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: color)),
        ],
      ),
    );
  }
}

// ── User list for a year ──────────────────────────────────────────────────────

class _YearUserList extends StatefulWidget {
  final int yearId;
  final WidgetRef ref;
  const _YearUserList({required this.yearId, required this.ref});

  @override
  State<_YearUserList> createState() => _YearUserListState();
}

class _YearUserListState extends State<_YearUserList> {
  String _filter = 'all';
  List<UserModel>? _users;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = widget.ref.read(apiClientProvider);
      final raw = await api.getUsersByYear(widget.yearId);
      setState(() {
        _users = raw
            .map((e) => UserModel.fromJson(e as Map<String, dynamic>))
            .toList();
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_users == null || _users!.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('No users registered this year.',
            style: TextStyle(color: AppColors.textMuted)),
      );
    }

    final filtered = _filter == 'all'
        ? _users!
        : _users!.where((u) => u.role == _filter).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter tabs
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['all', 'student', 'teacher', 'parent'].map((r) {
                final active = _filter == r;
                return GestureDetector(
                  onTap: () => setState(() => _filter = r),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.primary
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: active
                              ? AppColors.primary
                              : AppColors.divider),
                    ),
                    child: Text(
                      r[0].toUpperCase() + r.substring(1),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: active
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: active
                              ? Colors.white
                              : AppColors.textSecondary),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),
          ...filtered.map((u) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor:
                          _roleColor(u.role).withOpacity(0.15),
                      child: Text(
                        u.username[0].toUpperCase(),
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _roleColor(u.role)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(u.username,
                          style: const TextStyle(fontSize: 13)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _roleColor(u.role).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        u.role,
                        style: TextStyle(
                            fontSize: 10,
                            color: _roleColor(u.role),
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'student':
        return AppColors.secondary;
      case 'teacher':
        return AppColors.primary;
      case 'parent':
        return AppColors.accent;
      default:
        return AppColors.textMuted;
    }
  }
}

String _formatDate(DateTime dt) =>
    '${dt.day} ${_months[dt.month - 1]} ${dt.year}';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
