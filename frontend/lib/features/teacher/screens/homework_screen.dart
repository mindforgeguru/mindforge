import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/models/homework.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/constants.dart';
import '../../../core/api/api_client.dart';
import '../providers/teacher_provider.dart';
import '../widgets/teacher_bottom_nav.dart';
import '../widgets/teacher_scaffold.dart';

// ─── Responsive helpers (local) ───────────────────────────────────────────────
// Scale a base value linearly with screen width (reference = 390 px).
double _s(BuildContext ctx, double base, {double min = 0, double max = double.infinity}) {
  final w = MediaQuery.of(ctx).size.width;
  final scaled = base * (w / 390.0);
  return scaled.clamp(min == 0 ? base * 0.75 : min, max == double.infinity ? base * 1.4 : max);
}

double _fs(BuildContext ctx, double base, {double min = 10, double max = 22}) =>
    _s(ctx, base, min: min, max: max);

// ─── Screen ───────────────────────────────────────────────────────────────────

class TeacherHomeworkScreen extends ConsumerStatefulWidget {
  const TeacherHomeworkScreen({super.key});

  @override
  ConsumerState<TeacherHomeworkScreen> createState() =>
      _TeacherHomeworkScreenState();
}

class _TeacherHomeworkScreenState
    extends ConsumerState<TeacherHomeworkScreen> {
  @override
  Widget build(BuildContext context) {
    return TeacherScaffold(
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
      ),
      body: const _HomeworkTab(),
    );
  }
}

// ─── Homework Tab ─────────────────────────────────────────────────────────────

class _HomeworkTab extends ConsumerStatefulWidget {
  const _HomeworkTab();

  @override
  ConsumerState<_HomeworkTab> createState() => _HomeworkTabState();
}

class _HomeworkTabState extends ConsumerState<_HomeworkTab> {
  int _selectedGrade = 8;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final sw = mq.size.width;
    final hPad = _s(context, 14, min: 10, max: 20);
    final hwAsync = ref.watch(teacherHomeworkProvider(_selectedGrade));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Grade filter row ──────────────────────────────────────────────
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, _s(context, 12, min: 8, max: 16),
              hPad, _s(context, 4, min: 2, max: 6)),
          child: Row(
            children: [
              Text(
                'Grade:',
                style: GoogleFonts.poppins(
                  fontSize: _fs(context, 13, min: 11, max: 15),
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              SizedBox(width: _s(context, 8, min: 6, max: 12)),
              // Chips in their own scrollable row — no Add button competing
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: AppConstants.grades.map((g) {
                      final selected = _selectedGrade == g;
                      return Padding(
                        padding: EdgeInsets.only(
                            right: _s(context, 6, min: 4, max: 10)),
                        child: ChoiceChip(
                          label: Text(
                            'Grade $g',
                            style: GoogleFonts.poppins(
                              fontSize: _fs(context, 12, min: 10, max: 14),
                              fontWeight: FontWeight.w600,
                              color: selected
                                  ? Colors.white
                                  : AppColors.primary,
                            ),
                          ),
                          selected: selected,
                          selectedColor: AppColors.primary,
                          onSelected: (_) =>
                              setState(() => _selectedGrade = g),
                          materialTapTargetSize:
                              MaterialTapTargetSize.padded,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Add Homework button — full width, separate row ────────────────
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 0, hPad,
              _s(context, 8, min: 6, max: 12)),
          child: FractionallySizedBox(
            widthFactor: 1.0,
            child: FilledButton.icon(
              onPressed: () => _showCreateDialog(context),
              icon: Icon(Icons.add,
                  size: _s(context, 16, min: 14, max: 20)),
              label: Text(
                'Assign Homework',
                style: GoogleFonts.poppins(
                  fontSize: _fs(context, 13, min: 11, max: 15),
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                minimumSize: const Size(double.infinity, 46),
              ),
            ),
          ),
        ),

        // ── Homework list ─────────────────────────────────────────────────
        Expanded(
          child: hwAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Padding(
                padding: EdgeInsets.all(_s(context, 24)),
                child: Text(
                  'Could not load homework',
                  style: GoogleFonts.poppins(
                    color: AppColors.textMuted,
                    fontSize: _fs(context, 13, min: 11, max: 15),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            data: (list) => list.isEmpty
                ? const _EmptyState(
                    icon: Icons.assignment_outlined,
                    message: 'No homework assigned yet',
                  )
                : RefreshIndicator(
                    onRefresh: () async =>
                        ref.invalidate(teacherHomeworkProvider(_selectedGrade)),
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        hPad, _s(context, 4, min: 2, max: 8),
                        hPad, _s(context, 24, min: 16, max: 32),
                      ),
                      itemCount: list.length,
                      separatorBuilder: (_, __) =>
                          SizedBox(height: _s(context, 8, min: 6, max: 12)),
                      itemBuilder: (ctx, i) => _HomeworkCard(
                        hw: list[i],
                        screenWidth: sw,
                        onDelete: () async {
                          final api = ref.read(apiClientProvider);
                          await api.deleteHomework(list[i].id);
                          ref.invalidate(
                              teacherHomeworkProvider(_selectedGrade));
                        },
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  void _showCreateDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _CreateHomeworkDialog(
        selectedGrade: _selectedGrade,
        onCreated: () =>
            ref.invalidate(teacherHomeworkProvider(_selectedGrade)),
      ),
    );
  }
}

// ─── Create Homework Dialog ───────────────────────────────────────────────────

class _CreateHomeworkDialog extends ConsumerStatefulWidget {
  final int selectedGrade;
  final VoidCallback onCreated;

  const _CreateHomeworkDialog({
    required this.selectedGrade,
    required this.onCreated,
  });

  @override
  ConsumerState<_CreateHomeworkDialog> createState() =>
      _CreateHomeworkDialogState();
}

class _CreateHomeworkDialogState
    extends ConsumerState<_CreateHomeworkDialog> {
  final _formKey = GlobalKey<FormState>();
  late int _grade;
  String _subject = AppConstants.subjects.first;
  String _title = '';
  String _description = '';
  String _type = 'written';
  DateTime? _dueDate;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _grade = widget.selectedGrade;
  }

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    // Dialog width: at most 90% of screen, capped at 480
    final dialogWidth = (sw * 0.9).clamp(280.0, 480.0);

    return AlertDialog(
      title: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          'Assign Homework',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            fontSize: _fs(context, 16, min: 14, max: 18),
            color: AppColors.primary,
          ),
        ),
      ),
      contentPadding: EdgeInsets.fromLTRB(
          _s(context, 20, min: 14, max: 24),
          12,
          _s(context, 20, min: 14, max: 24),
          0),
      content: SizedBox(
        width: dialogWidth,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Grade
                DropdownButtonFormField<int>(
                  value: _grade,
                  decoration: const InputDecoration(labelText: 'Grade'),
                  items: AppConstants.grades
                      .map((g) => DropdownMenuItem(
                            value: g,
                            child: Text('Grade $g'),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _grade = v!),
                ),
                SizedBox(height: _s(context, 10, min: 8, max: 14)),
                // Subject
                DropdownButtonFormField<String>(
                  value: _subject,
                  decoration: const InputDecoration(labelText: 'Subject'),
                  isExpanded: true,
                  items: AppConstants.subjects
                      .map((s) => DropdownMenuItem(
                            value: s,
                            child: Text(s,
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _subject = v!),
                ),
                SizedBox(height: _s(context, 10, min: 8, max: 14)),
                // Title
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Title'),
                  onChanged: (v) => _title = v,
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Required' : null,
                ),
                SizedBox(height: _s(context, 10, min: 8, max: 14)),
                // Type — use Wrap so chips never overflow dialog
                Wrap(
                  spacing: _s(context, 8, min: 6, max: 12),
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Type:',
                      style: GoogleFonts.poppins(
                        fontSize: _fs(context, 13, min: 11, max: 15),
                        color: AppColors.textSecondary,
                      ),
                    ),
                    ChoiceChip(
                      label: Text('Written',
                          style: GoogleFonts.poppins(
                              fontSize: _fs(context, 12, min: 10, max: 14))),
                      selected: _type == 'written',
                      onSelected: (_) =>
                          setState(() => _type = 'written'),
                      materialTapTargetSize:
                          MaterialTapTargetSize.padded,
                    ),
                    ChoiceChip(
                      label: Text('Online Test',
                          style: GoogleFonts.poppins(
                              fontSize: _fs(context, 12, min: 10, max: 14))),
                      selected: _type == 'online_test',
                      onSelected: (_) =>
                          setState(() => _type = 'online_test'),
                      materialTapTargetSize:
                          MaterialTapTargetSize.padded,
                    ),
                  ],
                ),
                SizedBox(height: _s(context, 10, min: 8, max: 14)),
                // Description / link
                TextFormField(
                  decoration: InputDecoration(
                    labelText: _type == 'online_test'
                        ? 'Test Link / Instructions'
                        : 'Description / Instructions',
                  ),
                  maxLines: 3,
                  onChanged: (v) => _description = v,
                ),
                SizedBox(height: _s(context, 10, min: 8, max: 14)),
                // Due date
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now()
                            .add(const Duration(days: 1)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now()
                            .add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setState(() => _dueDate = picked);
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today_outlined,
                              size: _s(context, 18, min: 16, max: 22),
                              color: AppColors.accent),
                          SizedBox(width: _s(context, 8, min: 6, max: 12)),
                          Expanded(
                            child: Text(
                              _dueDate == null
                                  ? 'Set Due Date (optional)'
                                  : 'Due: ${DateFormat('dd MMM yyyy').format(_dueDate!)}',
                              style: GoogleFonts.poppins(
                                fontSize: _fs(context, 13, min: 11, max: 15),
                                color: _dueDate == null
                                    ? AppColors.textSecondary
                                    : AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(height: _s(context, 4, min: 2, max: 8)),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel',
              style: GoogleFonts.poppins(
                  fontSize: _fs(context, 13, min: 11, max: 15))),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              minimumSize: const Size(80, 44)),
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text('Assign',
                  style: GoogleFonts.poppins(
                      fontSize: _fs(context, 13, min: 11, max: 15),
                      fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.createHomework({
        'grade': _grade,
        'subject': _subject,
        'title': _title,
        'description': _description.isNotEmpty ? _description : null,
        'homework_type': _type,
        'due_date': _dueDate?.toIso8601String().substring(0, 10),
      });
      widget.onCreated();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

// ─── Homework Card ─────────────────────────────────────────────────────────────

class _HomeworkCard extends StatelessWidget {
  final HomeworkModel hw;
  final double screenWidth;
  final VoidCallback onDelete;

  const _HomeworkCard({
    required this.hw,
    required this.screenWidth,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isOnline = hw.isOnlineTest;
    final pad = _s(context, 14, min: 10, max: 20);

    return LayoutBuilder(builder: (context, constraints) {
      return Container(
        width: constraints.maxWidth,
        padding: EdgeInsets.all(pad),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
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
            // ── Badge row ─────────────────────────────────────────────────
            Row(
              children: [
                // Type badge
                _Badge(
                  label: isOnline ? 'Online Test' : 'Written',
                  color:
                      isOnline ? AppColors.accent : AppColors.primary,
                ),
                SizedBox(width: _s(context, 6, min: 4, max: 10)),
                // Subject — flexible, won't overflow
                Flexible(
                  child: _Badge(
                    label: hw.subject,
                    color: AppColors.textSecondary,
                    bg: AppColors.iconContainer,
                    maxLines: 1,
                  ),
                ),
                const Spacer(),
                // Delete — guaranteed 48x48 tap area
                SizedBox(
                  width: 48,
                  height: 48,
                  child: IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      color: AppColors.error,
                      size: _s(context, 20, min: 18, max: 24),
                    ),
                    onPressed: onDelete,
                    tooltip: 'Delete',
                  ),
                ),
              ],
            ),

            SizedBox(height: _s(context, 6, min: 4, max: 10)),

            // ── Title ─────────────────────────────────────────────────────
            Text(
              hw.title,
              style: GoogleFonts.poppins(
                fontSize: _fs(context, 14, min: 12, max: 17),
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),

            // ── Description ───────────────────────────────────────────────
            if (hw.description != null &&
                hw.description!.isNotEmpty) ...[
              SizedBox(height: _s(context, 4, min: 3, max: 8)),
              Text(
                hw.description!,
                style: GoogleFonts.poppins(
                  fontSize: _fs(context, 12, min: 11, max: 14),
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            SizedBox(height: _s(context, 8, min: 6, max: 12)),

            // ── Footer row ────────────────────────────────────────────────
            Wrap(
              spacing: _s(context, 12, min: 8, max: 16),
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _MetaChip(
                  icon: Icons.school_outlined,
                  label: 'Grade ${hw.grade}',
                ),
                if (hw.dueDate != null)
                  _MetaChip(
                    icon: Icons.calendar_today_outlined,
                    label:
                        'Due ${DateFormat('dd MMM').format(hw.dueDate!)}',
                  ),
                _MetaChip(
                  icon: Icons.access_time_outlined,
                  label: DateFormat('dd MMM').format(hw.createdAt),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }
}


// ─── Shared micro-widgets ─────────────────────────────────────────────────────

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

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon,
            size: _s(context, 13, min: 11, max: 15),
            color: AppColors.textMuted),
        SizedBox(width: _s(context, 4, min: 3, max: 6)),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: _fs(context, 11, min: 10, max: 13),
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final iconSize =
          (constraints.maxWidth * 0.16).clamp(40.0, 64.0);
      return Center(
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: _s(context, 32, min: 24, max: 48)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: iconSize,
                  color: AppColors.textMuted.withOpacity(0.4)),
              SizedBox(height: _s(context, 14, min: 10, max: 20)),
              Text(
                message,
                style: GoogleFonts.poppins(
                  fontSize: _fs(context, 14, min: 12, max: 16),
                  color: AppColors.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    });
  }
}
