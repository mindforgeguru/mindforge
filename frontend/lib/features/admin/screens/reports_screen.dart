import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:printing/printing.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/error_view.dart';
import '../providers/admin_provider.dart';
import '../widgets/admin_bottom_nav.dart';

// Responsive scale: baseline 360 logical pixels wide
double _sp(BuildContext context, double size) {
  final w = MediaQuery.of(context).size.width;
  return size * (w / 360).clamp(0.85, 1.3);
}

double _hp(BuildContext context) =>
    (MediaQuery.of(context).size.width * 0.04).clamp(12.0, 24.0);

class AdminReportsScreen extends ConsumerStatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  ConsumerState<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends ConsumerState<AdminReportsScreen> {
  String _selectedYear = '';
  int? _selectedGrade;
  int? _selectedStudentId;
  String? _selectedStudentName;

  bool _downloadingFees = false;
  bool _downloadingLedger = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initYear());
  }

  Future<void> _initYear() async {
    try {
      final data = await ref.read(currentAcademicYearProvider.future);
      final year = data?['year_label'] as String?;
      if (year != null && mounted) setState(() => _selectedYear = year);
    } catch (_) {}
  }

  List<String> _yearOptions() {
    final now = DateTime.now();
    return List.generate(4, (i) {
      final y = now.year - i;
      return '$y-${(y + 1).toString().substring(2)}';
    });
  }

  List<Map<String, dynamic>> _studentsForGrade(List summaries) {
    if (_selectedGrade == null) return [];
    return summaries
        .cast<Map<String, dynamic>>()
        .where((s) => s['grade'] == _selectedGrade)
        .toList();
  }

  Future<void> _downloadPendingFees() async {
    if (_selectedYear.isEmpty) return;
    setState(() => _downloadingFees = true);
    try {
      final api = ref.read(apiClientProvider);
      final bytes = Uint8List.fromList(
          await api.downloadPendingFeesReport(_selectedYear));
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'pending_fees_$_selectedYear.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed: $e'),
              backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _downloadingFees = false);
    }
  }

  Future<void> _downloadLedger() async {
    if (_selectedYear.isEmpty || _selectedStudentId == null) return;
    setState(() => _downloadingLedger = true);
    try {
      final api = ref.read(apiClientProvider);
      final bytes = Uint8List.fromList(
          await api.downloadStudentLedger(_selectedStudentId!, _selectedYear));
      await Printing.sharePdf(
        bytes: bytes,
        filename:
            'ledger_${_selectedStudentName ?? _selectedStudentId}_$_selectedYear.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed: $e'),
              backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _downloadingLedger = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summariesAsync = ref.watch(feeSummariesProvider(_selectedYear));
    final pad = _hp(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: const AdminBottomNav(),
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6)),
              padding: const EdgeInsets.all(3),
              child:
                  Image.asset('assets/images/logo.png', fit: BoxFit.contain),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(pad, pad, pad, pad + 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Academic Year ──────────────────────────────────────────
            _SectionLabel(label: 'Academic Year', context: context),
            SizedBox(height: _sp(context, 8)),
            _DropdownCard(
              context: context,
              child: DropdownButton<String>(
                value: _selectedYear.isEmpty ? null : _selectedYear,
                hint: Text('Select year',
                    style: GoogleFonts.poppins(fontSize: _sp(context, 13))),
                isExpanded: true,
                underline: const SizedBox(),
                style: GoogleFonts.poppins(
                    fontSize: _sp(context, 13),
                    color: AppColors.textPrimary),
                items: _yearOptions()
                    .map((y) => DropdownMenuItem(value: y, child: Text(y)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      _selectedYear = v;
                      _selectedGrade = null;
                      _selectedStudentId = null;
                      _selectedStudentName = null;
                    });
                  }
                },
              ),
            ),

            SizedBox(height: _sp(context, 20)),

            // ── Pending Fees ───────────────────────────────────────────
            _SectionLabel(label: 'Pending Fees Report', context: context),
            SizedBox(height: _sp(context, 4)),
            Text(
              'Grade-wise list of all students with outstanding balance',
              style: GoogleFonts.poppins(
                  fontSize: _sp(context, 11),
                  color: AppColors.textSecondary),
            ),
            SizedBox(height: _sp(context, 10)),
            _ReportCard(
              context: context,
              icon: Icons.pending_actions_outlined,
              title: 'Download Pending Fees PDF',
              color: AppColors.error,
              loading: _downloadingFees,
              enabled: _selectedYear.isNotEmpty,
              onDownload:
                  _selectedYear.isEmpty ? null : _downloadPendingFees,
            ),

            SizedBox(height: _sp(context, 28)),

            // ── Student Ledger ─────────────────────────────────────────
            _SectionLabel(label: 'Student Ledger', context: context),
            SizedBox(height: _sp(context, 4)),
            Text(
              'Select grade and student to download their fee ledger',
              style: GoogleFonts.poppins(
                  fontSize: _sp(context, 11),
                  color: AppColors.textSecondary),
            ),
            SizedBox(height: _sp(context, 12)),

            summariesAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorView(
                error: e,
                onRetry: () => ref.invalidate(feeSummariesProvider(_selectedYear)),
              ),
              data: (summaries) {
                final grades = summaries
                    .cast<Map<String, dynamic>>()
                    .map((s) => s['grade'] as int)
                    .toSet()
                    .toList()
                  ..sort();

                final studentsInGrade = _studentsForGrade(summaries);

                if (_selectedStudentId != null &&
                    studentsInGrade.every(
                        (s) => s['student_id'] != _selectedStudentId)) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() {
                        _selectedStudentId = null;
                        _selectedStudentName = null;
                      });
                    }
                  });
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Grade
                    _SectionLabel(
                        label: 'Grade',
                        context: context,
                        small: true),
                    SizedBox(height: _sp(context, 6)),
                    _DropdownCard(
                      context: context,
                      child: DropdownButton<int>(
                        value: _selectedGrade,
                        hint: Text('Select grade',
                            style: GoogleFonts.poppins(
                                fontSize: _sp(context, 13))),
                        isExpanded: true,
                        underline: const SizedBox(),
                        style: GoogleFonts.poppins(
                            fontSize: _sp(context, 13),
                            color: AppColors.textPrimary),
                        items: grades
                            .map((g) => DropdownMenuItem(
                                value: g,
                                child: Text('Grade $g')))
                            .toList(),
                        onChanged: (v) {
                          setState(() {
                            _selectedGrade = v;
                            _selectedStudentId = null;
                            _selectedStudentName = null;
                          });
                        },
                      ),
                    ),

                    if (_selectedGrade != null) ...[
                      SizedBox(height: _sp(context, 14)),
                      _SectionLabel(
                          label: 'Student',
                          context: context,
                          small: true),
                      SizedBox(height: _sp(context, 6)),
                      _DropdownCard(
                        context: context,
                        child: DropdownButton<int>(
                          value: _selectedStudentId,
                          hint: Text('Select student',
                              style: GoogleFonts.poppins(
                                  fontSize: _sp(context, 13))),
                          isExpanded: true,
                          underline: const SizedBox(),
                          style: GoogleFonts.poppins(
                              fontSize: _sp(context, 13),
                              color: AppColors.textPrimary),
                          items: studentsInGrade
                              .map((s) => DropdownMenuItem<int>(
                                    value: s['student_id'] as int,
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            s['username'] as String,
                                            overflow:
                                                TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          (s['balance_due'] as num) > 0
                                              ? 'Due: ₹${(s['balance_due'] as num).toStringAsFixed(0)}'
                                              : 'Paid',
                                          style: GoogleFonts.poppins(
                                            fontSize: _sp(context, 10),
                                            color:
                                                (s['balance_due'] as num) >
                                                        0
                                                    ? AppColors.error
                                                    : AppColors.success,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              final student = studentsInGrade.firstWhere(
                                  (s) => s['student_id'] == v);
                              setState(() {
                                _selectedStudentId = v;
                                _selectedStudentName =
                                    student['username'] as String;
                              });
                            }
                          },
                        ),
                      ),
                    ],

                    if (_selectedStudentId != null) ...[
                      SizedBox(height: _sp(context, 16)),
                      Builder(builder: (ctx) {
                        final student = studentsInGrade.firstWhere(
                            (s) => s['student_id'] == _selectedStudentId,
                            orElse: () => {});
                        final balance =
                            (student['balance_due'] as num?)
                                    ?.toDouble() ??
                                0;
                        final paid =
                            (student['total_paid'] as num?)?.toDouble() ??
                                0;
                        final total =
                            (student['total_fee'] as num?)?.toDouble() ??
                                0;
                        return _BalanceCard(
                          context: context,
                          total: total,
                          paid: paid,
                          balance: balance,
                        );
                      }),
                      SizedBox(height: _sp(context, 12)),
                      _ReportCard(
                        context: context,
                        icon: Icons.account_balance_wallet_outlined,
                        title: 'Download Ledger PDF',
                        color: AppColors.primary,
                        loading: _downloadingLedger,
                        enabled: true,
                        onDownload: _downloadLedger,
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Shared widgets ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final BuildContext context;
  final bool small;
  const _SectionLabel(
      {required this.label, required this.context, this.small = false});

  @override
  Widget build(BuildContext ctx) {
    return Text(label,
        style: GoogleFonts.poppins(
            fontSize: _sp(context, small ? 13 : 15),
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary));
  }
}

class _DropdownCard extends StatelessWidget {
  final Widget child;
  final BuildContext context;
  const _DropdownCard({required this.child, required this.context});

  @override
  Widget build(BuildContext ctx) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
          horizontal: _sp(context, 14), vertical: _sp(context, 2)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: child,
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final BuildContext context;
  final double total;
  final double paid;
  final double balance;
  const _BalanceCard(
      {required this.context,
      required this.total,
      required this.paid,
      required this.balance});

  @override
  Widget build(BuildContext ctx) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(_sp(context, 14)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: balance > 0
                ? AppColors.error.withValues(alpha: 0.3)
                : AppColors.success.withValues(alpha: 0.3)),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
                child: _StatCell(
                    context: context,
                    label: 'Total Fee',
                    value: '₹${total.toStringAsFixed(0)}')),
            VerticalDivider(
                color: Colors.grey.withValues(alpha: 0.3), width: 1),
            Expanded(
                child: _StatCell(
                    context: context,
                    label: 'Paid',
                    value: '₹${paid.toStringAsFixed(0)}',
                    color: AppColors.success)),
            VerticalDivider(
                color: Colors.grey.withValues(alpha: 0.3), width: 1),
            Expanded(
                child: _StatCell(
                    context: context,
                    label: 'Balance',
                    value: '₹${balance.toStringAsFixed(0)}',
                    color:
                        balance > 0 ? AppColors.error : AppColors.success)),
          ],
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final BuildContext context;
  final String label;
  final String value;
  final Color? color;
  const _StatCell(
      {required this.context,
      required this.label,
      required this.value,
      this.color});

  @override
  Widget build(BuildContext ctx) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value,
              style: GoogleFonts.poppins(
                  fontSize: _sp(context, 14),
                  fontWeight: FontWeight.w700,
                  color: color ?? AppColors.textPrimary)),
        ),
        SizedBox(height: _sp(context, 2)),
        Text(label,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: _sp(context, 10),
                color: AppColors.textSecondary)),
      ],
    );
  }
}

class _ReportCard extends StatelessWidget {
  final BuildContext context;
  final IconData icon;
  final String title;
  final Color color;
  final bool loading;
  final bool enabled;
  final VoidCallback? onDownload;

  const _ReportCard({
    required this.context,
    required this.icon,
    required this.title,
    required this.color,
    required this.loading,
    required this.enabled,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext ctx) {
    final iconBoxSize = _sp(context, 44);
    final iconSize = _sp(context, 22);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: InkWell(
        onTap: enabled && !loading ? onDownload : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: _sp(context, 16), vertical: _sp(context, 14)),
          child: Row(
            children: [
              Container(
                width: iconBoxSize,
                height: iconBoxSize,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: iconSize),
              ),
              SizedBox(width: _sp(context, 14)),
              Expanded(
                child: Text(title,
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: _sp(context, 13),
                        color: enabled
                            ? AppColors.textPrimary
                            : AppColors.textSecondary)),
              ),
              SizedBox(width: _sp(context, 8)),
              loading
                  ? SizedBox(
                      width: _sp(context, 22),
                      height: _sp(context, 22),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: color))
                  : Icon(Icons.download_outlined,
                      size: _sp(context, 24),
                      color: enabled ? color : Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}
