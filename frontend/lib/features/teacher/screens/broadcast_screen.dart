import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/homework.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/constants.dart';
import '../providers/teacher_provider.dart';
import '../widgets/teacher_bottom_nav.dart';

// ─── Responsive helpers ───────────────────────────────────────────────────────
double _s(BuildContext ctx, double base, {double min = 0, double max = double.infinity}) {
  final w = MediaQuery.of(ctx).size.width;
  final scaled = base * (w / 390.0);
  return scaled.clamp(min == 0 ? base * 0.75 : min, max == double.infinity ? base * 1.4 : max);
}

double _fs(BuildContext ctx, double base, {double min = 10, double max = 22}) =>
    _s(ctx, base, min: min, max: max);

// ─── Screen ───────────────────────────────────────────────────────────────────

class TeacherBroadcastScreen extends ConsumerWidget {
  const TeacherBroadcastScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hPad = _s(context, 14, min: 10, max: 20);
    final bcAsync = ref.watch(teacherBroadcastsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Broadcasts',
            style: GoogleFonts.poppins(
              fontSize: _fs(context, 16, min: 14, max: 20),
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        backgroundColor: AppColors.primary,
      ),
      bottomNavigationBar: const TeacherBottomNav(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Send New Broadcast button ───────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(
                hPad, _s(context, 14, min: 10, max: 20),
                hPad, _s(context, 8, min: 6, max: 12)),
            child: FilledButton.icon(
              onPressed: () => _showSendDialog(context, ref),
              icon: Icon(Icons.campaign_outlined,
                  size: _s(context, 18, min: 16, max: 22)),
              label: Text(
                'Send New Broadcast',
                style: GoogleFonts.poppins(
                  fontSize: _fs(context, 13, min: 11, max: 15),
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ),

          // ── Broadcast list ─────────────────────────────────────────────
          Expanded(
            child: bcAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: EdgeInsets.all(_s(context, 24)),
                  child: Text(
                    'Could not load broadcasts',
                    style: GoogleFonts.poppins(
                      color: AppColors.textMuted,
                      fontSize: _fs(context, 13, min: 11, max: 15),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              data: (list) => list.isEmpty
                  ? _EmptyState()
                  : RefreshIndicator(
                      onRefresh: () async =>
                          ref.invalidate(teacherBroadcastsProvider),
                      child: ListView.separated(
                        padding: EdgeInsets.fromLTRB(
                          hPad, _s(context, 4, min: 2, max: 8),
                          hPad, _s(context, 24, min: 16, max: 32),
                        ),
                        itemCount: list.length,
                        separatorBuilder: (_, __) =>
                            SizedBox(height: _s(context, 8, min: 6, max: 12)),
                        itemBuilder: (_, i) => _BroadcastCard(bc: list[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSendDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => _SendBroadcastDialog(
        onSent: () => ref.invalidate(teacherBroadcastsProvider),
      ),
    );
  }
}

// ─── Broadcast Card ───────────────────────────────────────────────────────────

class _BroadcastCard extends StatelessWidget {
  final BroadcastModel bc;
  const _BroadcastCard({required this.bc});

  @override
  Widget build(BuildContext context) {
    final pad = _s(context, 14, min: 10, max: 20);
    final targetLabel = bc.targetType == 'grade' && bc.targetGrade != null
        ? 'Grade ${bc.targetGrade}'
        : 'Everyone';

    return Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0C1D3557), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: _s(context, 8, min: 6, max: 12),
                  vertical: _s(context, 3, min: 2, max: 5),
                ),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  targetLabel,
                  style: GoogleFonts.poppins(
                    fontSize: _fs(context, 10, min: 9, max: 12),
                    fontWeight: FontWeight.w600,
                    color: AppColors.accent,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                DateFormat('dd MMM yyyy').format(bc.createdAt),
                style: GoogleFonts.poppins(
                  fontSize: _fs(context, 11, min: 10, max: 13),
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          SizedBox(height: _s(context, 6, min: 4, max: 10)),
          Text(
            bc.title,
            style: GoogleFonts.poppins(
              fontSize: _fs(context, 14, min: 12, max: 17),
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          SizedBox(height: _s(context, 4, min: 3, max: 6)),
          Text(
            bc.message,
            style: GoogleFonts.poppins(
              fontSize: _fs(context, 12, min: 11, max: 14),
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Send Broadcast Dialog ────────────────────────────────────────────────────

class _SendBroadcastDialog extends ConsumerStatefulWidget {
  final VoidCallback onSent;
  const _SendBroadcastDialog({required this.onSent});

  @override
  ConsumerState<_SendBroadcastDialog> createState() =>
      _SendBroadcastDialogState();
}

class _SendBroadcastDialogState extends ConsumerState<_SendBroadcastDialog> {
  final _formKey = GlobalKey<FormState>();
  String _title = '';
  String _message = '';
  String _targetType = 'all';
  int? _targetGrade;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    final dialogWidth = (sw * 0.9).clamp(280.0, 480.0);

    return AlertDialog(
      title: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          'Send Broadcast',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            fontSize: _fs(context, 16, min: 14, max: 18),
            color: AppColors.primary,
          ),
        ),
      ),
      contentPadding: EdgeInsets.fromLTRB(
          _s(context, 20, min: 14, max: 24), 12,
          _s(context, 20, min: 14, max: 24), 0),
      content: SizedBox(
        width: dialogWidth,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Title'),
                  onChanged: (v) => _title = v,
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Required' : null,
                ),
                SizedBox(height: _s(context, 10, min: 8, max: 14)),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Message'),
                  maxLines: 4,
                  onChanged: (v) => _message = v,
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Required' : null,
                ),
                SizedBox(height: _s(context, 10, min: 8, max: 14)),
                Wrap(
                  spacing: _s(context, 8, min: 6, max: 12),
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Send to:',
                      style: GoogleFonts.poppins(
                        fontSize: _fs(context, 13, min: 11, max: 15),
                        color: AppColors.textSecondary,
                      ),
                    ),
                    ChoiceChip(
                      label: Text('Everyone',
                          style: GoogleFonts.poppins(
                              fontSize:
                                  _fs(context, 12, min: 10, max: 14))),
                      selected: _targetType == 'all',
                      onSelected: (_) =>
                          setState(() => _targetType = 'all'),
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                    ),
                    ChoiceChip(
                      label: Text('Specific Grade',
                          style: GoogleFonts.poppins(
                              fontSize:
                                  _fs(context, 12, min: 10, max: 14))),
                      selected: _targetType == 'grade',
                      onSelected: (_) =>
                          setState(() => _targetType = 'grade'),
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                    ),
                  ],
                ),
                if (_targetType == 'grade') ...[
                  SizedBox(height: _s(context, 10, min: 8, max: 14)),
                  DropdownButtonFormField<int>(
                    initialValue: _targetGrade,
                    decoration:
                        const InputDecoration(labelText: 'Select Grade'),
                    isExpanded: true,
                    items: AppConstants.grades
                        .map((g) => DropdownMenuItem(
                              value: g,
                              child: Text('Grade $g'),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _targetGrade = v),
                    validator: (v) =>
                        v == null ? 'Please select a grade' : null,
                  ),
                ],
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
              backgroundColor: AppColors.accent,
              minimumSize: const Size(80, 44)),
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text('Send',
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
      await api.sendBroadcast({
        'title': _title,
        'message': _message,
        'target_type': _targetType,
        if (_targetType == 'grade') 'target_grade': _targetGrade,
      });
      widget.onSent();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Broadcast sent!')),
        );
      }
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

// ─── Empty State ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final iconSize = (constraints.maxWidth * 0.16).clamp(40.0, 64.0);
      return Center(
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: _s(context, 32, min: 24, max: 48)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.campaign_outlined,
                  size: iconSize,
                  color: AppColors.textMuted.withOpacity(0.4)),
              SizedBox(height: _s(context, 14, min: 10, max: 20)),
              Text(
                'No broadcasts sent yet',
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
