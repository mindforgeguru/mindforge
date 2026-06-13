import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/constants.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/shimmer_list.dart';
import '../providers/presentation_provider.dart';
import '../widgets/teacher_scaffold.dart';

class AutoPresentationListScreen extends ConsumerWidget {
  const AutoPresentationListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(presentationListProvider);

    return TeacherScaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Auto Presentations',
          style: GoogleFonts.poppins(
            fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white,
          ),
        ),
        backgroundColor: AppColors.primary,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
            child: FilledButton.icon(
              onPressed: () => context.go(
                '${RouteNames.teacherDashboard}/presentations/upload',
              ),
              icon: const Icon(Icons.upload_file_outlined, size: 18),
              label: Text(
                'Upload Chapter PDF',
                style: GoogleFonts.poppins(
                  fontSize: 13, fontWeight: FontWeight.w600,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(presentationListProvider),
              child: listAsync.when(
                loading: () => const ShimmerList(showAvatar: false),
                error: (e, _) => ErrorView(
                  error: e,
                  onRetry: () => ref.invalidate(presentationListProvider),
                ),
                data: (rows) {
                  if (rows.isEmpty) {
                    return _EmptyState();
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _PresentationCard(row: rows[i]),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.slideshow_outlined,
                size: 48, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(
              'No presentations yet.',
              style: GoogleFonts.poppins(
                fontSize: 14, fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Upload a chapter PDF to generate a slide-by-slide lesson plan.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 12, color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PresentationCard extends ConsumerWidget {
  final Map<String, dynamic> row;
  const _PresentationCard({required this.row});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = row['presentation_id'] as int;
    final status = (row['status'] as String? ?? 'PROCESSING');
    final total = (row['total_slides'] as int?) ?? 0;
    final current = (row['current_slide_index'] as int?) ?? 0;
    final periodsUsed = (row['periods_used'] as int?) ?? 0;
    final periodsRec = (row['recommended_periods'] as int?) ?? 0;
    final pct = total > 0 ? (current / total).clamp(0.0, 1.0) : 0.0;

    final isProcessing = status == 'PROCESSING';
    final isFailed = status == 'FAILED';

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: isProcessing
          ? null
          : () => context.go(
              '${RouteNames.teacherDashboard}/presentations/$id'),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.iconContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Grade ${row['grade']} · ${row['subject']}',
                    style: GoogleFonts.poppins(
                      fontSize: 11, fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const Spacer(),
                if (isProcessing)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 12, height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Generating…',
                        style: GoogleFonts.poppins(
                            fontSize: 11, color: AppColors.textMuted),
                      ),
                    ],
                  )
                else if (isFailed)
                  Text('Failed',
                      style: GoogleFonts.poppins(
                          fontSize: 11, color: AppColors.error,
                          fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              row['chapter_name']?.toString() ?? '—',
              style: GoogleFonts.poppins(
                fontSize: 15, fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Teacher: ${row['teacher_username']}'
              '${row['teacher_id'] != row['created_by_teacher_id'] ? '   ·   uploaded by ${row['created_by_username']}' : ''}',
              style: GoogleFonts.poppins(
                fontSize: 11, color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 10),
            if (!isProcessing && total > 0) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 6,
                  backgroundColor: AppColors.divider,
                  valueColor: AlwaysStoppedAnimation(AppColors.primary),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$current / $total slides   ·   $periodsUsed / $periodsRec periods',
                style: GoogleFonts.poppins(
                  fontSize: 11, color: AppColors.textSecondary,
                ),
              ),
            ] else if (isFailed) ...[
              Text(
                'Generation failed. Tap to view details or try uploading again.',
                style: GoogleFonts.poppins(
                  fontSize: 11, color: AppColors.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
