import 'package:dio/dio.dart' show DioException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/homework.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/shimmer_list.dart';
import '../providers/teacher_provider.dart';
import '../widgets/teacher_scaffold.dart';

double _s(BuildContext ctx, double base,
    {double min = 0, double max = double.infinity}) {
  final w = MediaQuery.of(ctx).size.width;
  final scaled = base * (w / 390.0);
  return scaled.clamp(
      min == 0 ? base * 0.75 : min,
      max == double.infinity ? base * 1.4 : max);
}

double _fs(BuildContext ctx, double base,
        {double min = 10, double max = 22}) =>
    _s(ctx, base, min: min, max: max);

/// Teacher screen for marking which students completed a piece of homework.
/// Mirrors the per-period attendance flow: roster + Switch.adaptive toggles
/// + summary strip + Submit/Update bottom action.
class TeacherHomeworkCompletionScreen extends ConsumerStatefulWidget {
  final int homeworkId;
  const TeacherHomeworkCompletionScreen({super.key, required this.homeworkId});

  @override
  ConsumerState<TeacherHomeworkCompletionScreen> createState() =>
      _TeacherHomeworkCompletionScreenState();
}

class _TeacherHomeworkCompletionScreenState
    extends ConsumerState<TeacherHomeworkCompletionScreen> {
  // student_id → completed
  final Map<int, bool> _state = {};
  // Tracks the homeworkId the local map was last seeded from, so that a
  // rebuild from a provider refresh doesn't wipe the teacher's edits.
  int? _seededFor;
  bool _submitting = false;

  void _seedFromRecords(List<HomeworkCompletionDetail> records) {
    if (_seededFor == widget.homeworkId) return;
    _seededFor = widget.homeworkId;
    _state
      ..clear()
      ..addEntries(records.map((r) => MapEntry(r.studentId, r.completed)));
  }

  void _resetAll(List<HomeworkCompletionDetail> records) {
    setState(() {
      for (final r in records) {
        // Absent rows stay locked Incomplete — Reset doesn't unlock them.
        _state[r.studentId] = r.wasAbsent ? false : false;
      }
    });
  }

  Future<void> _submit({required bool isUpdate}) async {
    if (_state.isEmpty) return;
    setState(() => _submitting = true);
    try {
      final api = ref.read(apiClientProvider);
      final records = _state.entries
          .map((e) => {
                'student_id': e.key,
                'completed': e.value,
              })
          .toList();
      await api.upsertHomeworkCompletions(widget.homeworkId, records);
      ref.invalidate(
          teacherHomeworkCompletionsProvider(widget.homeworkId));
      ref.invalidate(teacherTodayWorkflowProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isUpdate
                ? 'Homework status updated successfully!'
                : 'Homework status submitted successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } on DioException catch (e) {
      // 400 = backend rejected because attendance hasn't been recorded.
      // Show the server's detail message — it names the date the teacher
      // needs to mark.
      final detail = e.response?.data is Map<String, dynamic>
          ? (e.response!.data as Map<String, dynamic>)['detail']?.toString()
          : null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(detail ?? 'Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailsAsync =
        ref.watch(teacherHomeworkCompletionsProvider(widget.homeworkId));

    return TeacherScaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Homework Status',
            style: GoogleFonts.poppins(
              fontSize: _fs(context, 18, min: 15, max: 21),
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ),
      body: detailsAsync.when(
        loading: () => const ShimmerList(),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(
              teacherHomeworkCompletionsProvider(widget.homeworkId)),
        ),
        data: (response) {
          final records = response.students;
          if (records.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No active students found in this grade.',
                  style: GoogleFonts.poppins(
                      fontSize: _fs(context, 13, min: 11, max: 15),
                      color: AppColors.textMuted),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          _seedFromRecords(records);
          // Force-sync the local toggle state with absent rows on every
          // build — backend always returns completed=false for absent
          // students and we want the UI to mirror that even if the
          // teacher previously toggled them on before attendance was
          // entered.
          for (final r in records) {
            if (r.wasAbsent) _state[r.studentId] = false;
          }

          final completeCount =
              _state.values.where((v) => v).length;
          final incompleteCount = records.length - completeCount;
          final alreadySubmitted =
              records.any((r) => r.markedAt != null);
          final attendanceMissing = !response.attendanceRecorded;

          return Column(
            children: [
              _SummaryStrip(
                total: records.length,
                complete: completeCount,
                incomplete: incompleteCount,
              ),
              if (attendanceMissing)
                _AttendanceMissingBanner(
                    attendanceDate: response.attendanceDate),
              if (alreadySubmitted && !attendanceMissing)
                _SubmittedBanner(),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => ref.invalidate(
                      teacherHomeworkCompletionsProvider(widget.homeworkId)),
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                        16, 12, 16, R.sp(context, 16, min: 12, max: 24)),
                    itemCount: records.length + 1,
                    separatorBuilder: (_, i) =>
                        SizedBox(height: i < records.length - 1 ? 8 : 16),
                    itemBuilder: (ctx, i) {
                      if (i == records.length) {
                        return _BottomActions(
                          submitting: _submitting,
                          isUpdate: alreadySubmitted,
                          // Block Submit until attendance has been entered;
                          // the backend will reject the call anyway, but
                          // disabling the button prevents the round trip
                          // and shows the user where the friction is.
                          disabled: attendanceMissing,
                          onReset: () => _resetAll(records),
                          onSubmit: () =>
                              _submit(isUpdate: alreadySubmitted),
                        );
                      }
                      final r = records[i];
                      final completed = _state[r.studentId] ?? false;
                      return _StudentTile(
                        username: r.username,
                        completed: completed,
                        wasAbsent: r.wasAbsent,
                        onChanged: r.wasAbsent
                            ? null
                            : (v) => setState(
                                () => _state[r.studentId] = v),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Summary strip ──────────────────────────────────────────────────────────

class _SummaryStrip extends StatelessWidget {
  final int total;
  final int complete;
  final int incomplete;

  const _SummaryStrip({
    required this.total,
    required this.complete,
    required this.incomplete,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : complete / total;
    final gap = R.sp(context, 12, min: 8, max: 16);
    return Container(
      margin: EdgeInsets.fromLTRB(
          R.sp(context, 16, min: 12, max: 20),
          R.sp(context, 12, min: 8, max: 16),
          R.sp(context, 16, min: 12, max: 20),
          0),
      padding: EdgeInsets.symmetric(
          horizontal: R.sp(context, 16, min: 12, max: 20),
          vertical: R.sp(context, 12, min: 8, max: 16)),
      decoration: mindForgeCardDecoration(),
      child: Row(
        children: [
          _StatChip(label: 'Total', value: '$total', color: AppColors.primary),
          SizedBox(width: gap),
          _StatChip(
              label: 'Complete',
              value: '$complete',
              color: AppColors.success),
          SizedBox(width: gap),
          _StatChip(
              label: 'Incomplete',
              value: '$incomplete',
              color: AppColors.error),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${(pct * 100).toStringAsFixed(0)}%',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: _fs(context, 16, min: 13, max: 18),
                    color: AppColors.primary),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: R.fluid(context, 80, min: 60, max: 100),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 8,
                    backgroundColor: AppColors.error.withOpacity(0.2),
                    valueColor:
                        const AlwaysStoppedAnimation(AppColors.success),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value,
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: _fs(context, 18, min: 15, max: 22),
                  color: color)),
        ),
        Text(label,
            style: GoogleFonts.poppins(
                fontSize: _fs(context, 10, min: 9, max: 12),
                color: AppColors.textMuted)),
      ],
    );
  }
}

class _SubmittedBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.fromLTRB(
          R.sp(context, 16, min: 12, max: 20),
          R.sp(context, 8, min: 6, max: 12),
          R.sp(context, 16, min: 12, max: 20),
          0),
      padding: EdgeInsets.symmetric(
          horizontal: R.sp(context, 14, min: 10, max: 18),
          vertical: R.sp(context, 10, min: 8, max: 13)),
      decoration: BoxDecoration(
        color: AppColors.accent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.accent.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle,
              color: AppColors.accent,
              size: R.fluid(context, 18, min: 15, max: 22)),
          SizedBox(width: R.sp(context, 8, min: 6, max: 10)),
          Expanded(
            child: Text(
              'Status already recorded for this homework. '
              'Make changes below and tap Update to save.',
              style: GoogleFonts.poppins(
                  fontSize: _fs(context, 12, min: 10, max: 13),
                  color: AppColors.accent,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentTile extends StatelessWidget {
  final String username;
  final bool completed;
  final bool wasAbsent;
  // null = locked (absent). Switch is disabled and shown unchanged.
  final void Function(bool)? onChanged;

  const _StudentTile({
    required this.username,
    required this.completed,
    required this.wasAbsent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final avatarRadius = R.fluid(context, 18, min: 15, max: 22);
    final isLocked = wasAbsent;
    // Visual treatment for locked rows: same red as Incomplete but with a
    // distinct "Absent" label so the teacher knows why the toggle is off
    // and uneditable.
    final labelText = isLocked
        ? 'Absent'
        : (completed ? 'Complete' : 'Incomplete');
    final labelColor = isLocked
        ? AppColors.error
        : (completed ? AppColors.success : AppColors.error);
    return Opacity(
      opacity: isLocked ? 0.7 : 1.0,
      child: Container(
        decoration: mindForgeCardDecoration(),
        padding: EdgeInsets.symmetric(
            horizontal: R.sp(context, 16, min: 12, max: 20),
            vertical: R.sp(context, 10, min: 8, max: 14)),
        child: Row(
          children: [
            CircleAvatar(
              radius: avatarRadius,
              backgroundColor: completed && !isLocked
                  ? AppColors.success.withOpacity(0.15)
                  : AppColors.error.withOpacity(0.15),
              child: Icon(
                isLocked
                    ? Icons.block
                    : (completed
                        ? Icons.check_circle_outline
                        : Icons.radio_button_unchecked),
                size: R.fluid(context, 20, min: 16, max: 24),
                color: completed && !isLocked
                    ? AppColors.success
                    : AppColors.error,
              ),
            ),
            SizedBox(width: R.sp(context, 12, min: 8, max: 16)),
            Expanded(
              child: Text(
                username,
                style: GoogleFonts.poppins(
                  fontSize: _fs(context, 14, min: 12, max: 16),
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              labelText,
              style: GoogleFonts.poppins(
                fontSize: _fs(context, 12, min: 10, max: 13),
                fontWeight: FontWeight.w600,
                color: labelColor,
              ),
            ),
            SizedBox(width: R.sp(context, 4, min: 2, max: 8)),
            Switch.adaptive(
              value: completed && !isLocked,
              activeColor: AppColors.success,
              inactiveTrackColor: AppColors.error.withOpacity(0.3),
              // null disables the switch — Flutter renders it greyed out.
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

// Banner shown when attendance has not been recorded for the homework's
// assigned date. Blocks Submit and tells the teacher exactly which date
// to mark before they can record completion status.
class _AttendanceMissingBanner extends StatelessWidget {
  final String attendanceDate;
  const _AttendanceMissingBanner({required this.attendanceDate});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.fromLTRB(
          R.sp(context, 16, min: 12, max: 20),
          R.sp(context, 8, min: 6, max: 12),
          R.sp(context, 16, min: 12, max: 20),
          0),
      padding: EdgeInsets.symmetric(
          horizontal: R.sp(context, 14, min: 10, max: 18),
          vertical: R.sp(context, 10, min: 8, max: 13)),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withOpacity(0.6)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              color: AppColors.warning,
              size: R.fluid(context, 20, min: 17, max: 24)),
          SizedBox(width: R.sp(context, 8, min: 6, max: 10)),
          Expanded(
            child: Text(
              'Mark attendance for $attendanceDate first. '
              'Homework status can only be recorded once attendance is taken.',
              style: GoogleFonts.poppins(
                  fontSize: _fs(context, 12, min: 10, max: 13),
                  color: AppColors.warning,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomActions extends StatelessWidget {
  final bool submitting;
  final bool isUpdate;
  final bool disabled;
  final VoidCallback onReset;
  final VoidCallback onSubmit;

  const _BottomActions({
    required this.submitting,
    required this.isUpdate,
    required this.disabled,
    required this.onReset,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final btnColor = isUpdate ? AppColors.accent : AppColors.primary;
    final btnLabel = submitting
        ? (isUpdate ? 'Updating…' : 'Submitting…')
        : (isUpdate ? 'Update Status' : 'Submit Status');
    final btnIcon = isUpdate ? Icons.edit_outlined : Icons.send_outlined;
    final blocked = submitting || disabled;

    return Padding(
      padding: EdgeInsets.symmetric(
          vertical: R.sp(context, 4, min: 2, max: 8)),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: Icon(Icons.refresh,
                  size: R.fluid(context, 18, min: 16, max: 20)),
              label: Text('Reset',
                  style: GoogleFonts.poppins(
                      fontSize: _fs(context, 14, min: 12, max: 16))),
              onPressed: blocked ? null : onReset,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textMuted,
                side: const BorderSide(color: AppColors.divider),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          SizedBox(width: R.sp(context, 12, min: 8, max: 16)),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              icon: Icon(btnIcon,
                  size: R.fluid(context, 18, min: 16, max: 20)),
              label: Text(btnLabel,
                  style: GoogleFonts.poppins(
                      fontSize: _fs(context, 14, min: 12, max: 16),
                      fontWeight: FontWeight.w600)),
              onPressed: blocked ? null : onSubmit,
              style: FilledButton.styleFrom(
                backgroundColor: btnColor,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
