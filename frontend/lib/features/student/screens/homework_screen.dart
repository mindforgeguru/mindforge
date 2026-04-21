import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/models/homework.dart' show HomeworkModel;
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/shimmer_list.dart';
import '../providers/student_provider.dart';
import '../widgets/student_scaffold.dart';

// Responsive scale helper — base ref width 390 px
double _s(BuildContext ctx, double base, {double min = 0, double max = double.infinity}) {
  final w = MediaQuery.of(ctx).size.width;
  final scaled = base * (w / 390.0);
  return scaled.clamp(min == 0 ? base * 0.75 : min, max == double.infinity ? base * 1.4 : max);
}

double _fs(BuildContext ctx, double base, {double min = 10, double max = 22}) =>
    _s(ctx, base, min: min, max: max);

// ─── Screen ───────────────────────────────────────────────────────────────────

class StudentHomeworkScreen extends ConsumerWidget {
  final bool embedded;
  const StudentHomeworkScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeworkList = _HomeworkList(
      asyncProvider: studentHomeworkProvider,
      onRefresh: () => ref.refresh(studentHomeworkProvider.future),
    );

    if (embedded) {
      return homeworkList;
    }

    final isWide = MediaQuery.of(context).size.width >= 900;

    return StudentScaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Homework',
            style: GoogleFonts.poppins(
              fontSize: _fs(context, 16, min: 14, max: 20),
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        backgroundColor: AppColors.primary,
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
      ),
      body: isWide
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: SizedBox(
                  width: MediaQuery.of(context).size.width * 0.5,
                  child: Container(
                    decoration: mindForgeCardDecoration(),
                    clipBehavior: Clip.antiAlias,
                    child: homeworkList,
                  ),
                ),
              ),
            )
          : homeworkList,
    );
  }
}

// ─── Homework List ────────────────────────────────────────────────────────────

class _HomeworkList extends ConsumerWidget {
  final ProviderListenable<AsyncValue<List<HomeworkModel>>> asyncProvider;
  final Future<void> Function() onRefresh;

  const _HomeworkList({required this.asyncProvider, required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hPad = _s(context, 14, min: 10, max: 20);
    final hwAsync = ref.watch(asyncProvider);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: hwAsync.when(
        loading: () => const ShimmerList(showAvatar: false),
        error: (e, _) => ErrorView(error: e, onRetry: () => onRefresh()),
        data: (list) => list.isEmpty
            ? _scrollableEmpty(context,
                icon: Icons.assignment_outlined,
                message: 'No homework assigned')
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(hPad,
                    _s(context, 12, min: 8, max: 16),
                    hPad, _s(context, 24, min: 16, max: 32)),
                itemCount: list.length,
                separatorBuilder: (_, __) =>
                    SizedBox(height: _s(context, 8, min: 6, max: 12)),
                itemBuilder: (ctx, i) =>
                    _HomeworkCard(hw: list[i]),
              ),
      ),
    );
  }
}

// scrollable empty so pull-to-refresh still works
Widget _scrollableEmpty(BuildContext ctx,
    {required IconData icon, required String message}) {
  return LayoutBuilder(builder: (ctx, constraints) {
    final iconSize = (constraints.maxWidth * 0.16).clamp(40.0, 64.0);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: constraints.maxHeight * 0.28),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: iconSize,
                  color: AppColors.textMuted.withOpacity(0.4)),
              SizedBox(height: _s(ctx, 14, min: 10, max: 20)),
              Text(
                message,
                style: GoogleFonts.poppins(
                  fontSize: _fs(ctx, 14, min: 12, max: 16),
                  color: AppColors.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  });
}

// ─── Homework Card ────────────────────────────────────────────────────────────

class _HomeworkCard extends StatelessWidget {
  final HomeworkModel hw;

  const _HomeworkCard({required this.hw});

  @override
  Widget build(BuildContext context) {
    final isOnline = hw.isOnlineTest;
    final isDueSoon = hw.dueDate != null &&
        hw.dueDate!.isAfter(DateTime.now()) &&
        hw.dueDate!.isBefore(
            DateTime.now().add(const Duration(days: 2)));
    final pad = _s(context, 14, min: 10, max: 20);

    return LayoutBuilder(builder: (context, constraints) {
      return Container(
        width: constraints.maxWidth,
        padding: EdgeInsets.all(pad),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: isDueSoon
              ? Border.all(
                  color: AppColors.warning.withOpacity(0.5), width: 1)
              : null,
          boxShadow: const [
            BoxShadow(
                color: Color(0x0C1D3557),
                blurRadius: 10,
                offset: Offset(0, 3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Type + subject + due date ──────────────────────────────────
            Row(
              children: [
                _Badge(
                  label: isOnline ? 'Online Test' : 'Written',
                  color: isOnline ? AppColors.accent : AppColors.primary,
                ),
                SizedBox(width: _s(context, 6, min: 4, max: 10)),
                Flexible(
                  child: _Badge(
                    label: hw.subject,
                    color: AppColors.textSecondary,
                    bg: AppColors.iconContainer,
                    maxLines: 1,
                  ),
                ),
                if (hw.dueDate != null) ...[
                  const Spacer(),
                  Text(
                    'Due ${DateFormat('dd MMM').format(hw.dueDate!)}',
                    style: GoogleFonts.poppins(
                      fontSize: _fs(context, 10, min: 9, max: 12),
                      fontWeight: FontWeight.w600,
                      color: isDueSoon
                          ? AppColors.warning
                          : AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),

            SizedBox(height: _s(context, 8, min: 6, max: 12)),

            // ── Title ──────────────────────────────────────────────────────
            Text(
              hw.title,
              style: GoogleFonts.poppins(
                fontSize: _fs(context, 14, min: 12, max: 17),
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),

            // ── Description ────────────────────────────────────────────────
            if (hw.description != null &&
                hw.description!.isNotEmpty) ...[
              SizedBox(height: _s(context, 6, min: 4, max: 10)),
              Text(
                hw.description!,
                style: GoogleFonts.poppins(
                  fontSize: _fs(context, 12, min: 11, max: 14),
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],

            SizedBox(height: _s(context, 8, min: 6, max: 12)),

            // ── Assigned date ──────────────────────────────────────────────
            Text(
              'Assigned ${DateFormat('dd MMM yyyy').format(hw.createdAt)}',
              style: GoogleFonts.poppins(
                fontSize: _fs(context, 10, min: 9, max: 12),
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      );
    });
  }
}

// ─── Shared badge ─────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final Color? bg;
  final int maxLines;

  const _Badge({
    required this.label,
    required this.color,
    this.bg,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _s(context, 8, min: 6, max: 12),
        vertical: _s(context, 3, min: 2, max: 5),
      ),
      decoration: BoxDecoration(
        color: bg ?? color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: _fs(context, 10, min: 9, max: 12),
          fontWeight: FontWeight.w600,
          color: color,
        ),
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
