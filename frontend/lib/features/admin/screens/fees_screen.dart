import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/fees.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/constants.dart';
import '../providers/admin_provider.dart';

class AdminFeesScreen extends ConsumerStatefulWidget {
  const AdminFeesScreen({super.key});

  @override
  ConsumerState<AdminFeesScreen> createState() => _AdminFeesScreenState();
}

// Compute current academic year the same way the backend does:
// year starts June, so Jan–May → previous year
String _currentAcademicYear() {
  final now = DateTime.now();
  final yearStart = now.month >= 6 ? now.year : now.year - 1;
  return '$yearStart-${(yearStart + 1).toString().substring(2)}';
}

// Show current year + 2 previous years in the dropdown
List<String> _yearOptions() {
  final now = DateTime.now();
  final base = now.month >= 6 ? now.year : now.year - 1;
  return List.generate(3, (i) {
    final y = base - i;
    return '$y-${(y + 1).toString().substring(2)}';
  });
}

class _AdminFeesScreenState extends ConsumerState<AdminFeesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late String _selectedYear;

  @override
  void initState() {
    super.initState();
    _selectedYear = _currentAcademicYear();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fee Management'),
        actions: [
          // Year selector
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: DropdownButton<String>(
              value: _selectedYear,
              dropdownColor: AppColors.surface,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              underline: const SizedBox.shrink(),
              icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
              items: _yearOptions().map((y) => DropdownMenuItem(
                value: y,
                child: Text(y, style: const TextStyle(color: Colors.white)),
              )).toList(),
              onChanged: (v) {
                if (v != null) setState(() => _selectedYear = v);
              },
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: AppColors.accent,
          tabs: const [
            Tab(text: 'Fee Structures'),
            Tab(text: 'Payments'),
            Tab(text: 'Payment Info'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _FeeStructuresTab(selectedYear: _selectedYear),
          _PaymentsTab(selectedYear: _selectedYear),
          const _PaymentInfoTab(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 1: Fee Structures
// ─────────────────────────────────────────────────────────────────────────────

class _FeeStructuresTab extends ConsumerStatefulWidget {
  final String selectedYear;
  const _FeeStructuresTab({required this.selectedYear});

  @override
  ConsumerState<_FeeStructuresTab> createState() => _FeeStructuresTabState();
}

class _FeeStructuresTabState extends ConsumerState<_FeeStructuresTab> {
  bool _showAddForm = false;
  int _newGrade = 8;
  final _baseCtrl = TextEditingController(text: '0');
  final _econCtrl = TextEditingController(text: '0');
  final _compCtrl = TextEditingController(text: '0');
  final _aiCtrl = TextEditingController(text: '0');

  @override
  void dispose() {
    _baseCtrl.dispose();
    _econCtrl.dispose();
    _compCtrl.dispose();
    _aiCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final structuresAsync = ref.watch(feeStructuresProvider(widget.selectedYear));
    final fmt = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton.icon(
            icon: Icon(_showAddForm ? Icons.close : Icons.add),
            label: Text(_showAddForm ? 'Cancel' : 'Add Fee Structure'),
            onPressed: () => setState(() => _showAddForm = !_showAddForm),
          ),
          if (_showAddForm) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: mindForgeCardDecoration(
                  color: AppColors.primary.withValues(alpha: 0.04)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: _newGrade,
                    decoration: const InputDecoration(labelText: 'Grade'),
                    items: AppConstants.grades
                        .map((g) => DropdownMenuItem(
                            value: g, child: Text('Grade $g')))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _newGrade = v);
                    },
                  ),
                  const SizedBox(height: 8),
                  _FeeField(ctrl: _baseCtrl, label: 'Base Amount'),
                  _FeeField(ctrl: _econCtrl, label: 'Economics Fee'),
                  _FeeField(ctrl: _compCtrl, label: 'Computer Fee'),
                  _FeeField(ctrl: _aiCtrl, label: 'AI Fee'),
                  const SizedBox(height: 12),
                  ElevatedButton(
                      onPressed: _createStructure,
                      child: const Text('Save')),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          structuresAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _RetryWidget(
                onRetry: () => ref.invalidate(feeStructuresProvider)),
            data: (structures) {
              if (structures.isEmpty) {
                return const Center(child: Text('No fee structures yet.'));
              }
              return Column(
                children: structures
                    .map((s) => _FeeStructureTile(structure: s, formatter: fmt))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _createStructure() async {
    try {
      final api = ref.read(apiClientProvider);
      await api.createFeeStructure({
        'academic_year': widget.selectedYear,
        'grade': _newGrade,
        'base_amount': double.tryParse(_baseCtrl.text) ?? 0,
        'economics_fee': double.tryParse(_econCtrl.text) ?? 0,
        'computer_fee': double.tryParse(_compCtrl.text) ?? 0,
        'ai_fee': double.tryParse(_aiCtrl.text) ?? 0,
      });
      ref.invalidate(feeStructuresProvider);
      ref.invalidate(feeSummariesProvider);
      setState(() => _showAddForm = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Fee structure saved!'),
            backgroundColor: AppColors.success));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'), backgroundColor: AppColors.error));
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 2: Payments Received
// ─────────────────────────────────────────────────────────────────────────────

class _PaymentsTab extends ConsumerStatefulWidget {
  final String selectedYear;
  const _PaymentsTab({required this.selectedYear});

  @override
  ConsumerState<_PaymentsTab> createState() => _PaymentsTabState();
}

class _PaymentsTabState extends ConsumerState<_PaymentsTab> {
  final fmt = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
  int? _filterGrade;
  int? _filterStudentId;

  @override
  Widget build(BuildContext context) {
    final summariesAsync = ref.watch(feeSummariesProvider(widget.selectedYear));

    return summariesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _RetryWidget(
          onRetry: () => ref.invalidate(feeSummariesProvider)),
      data: (summaries) {
        if (summaries.isEmpty) {
          return const Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.people_outline, size: 56, color: AppColors.textMuted),
              SizedBox(height: 12),
              Text('No approved students yet.',
                  style: TextStyle(color: AppColors.textSecondary)),
            ]),
          );
        }

        // Build filtered list
        final gradeFiltered = _filterGrade == null
            ? List<dynamic>.from(summaries)
            : summaries
                .where((s) => (s['grade'] as int) == _filterGrade)
                .toList();

        final displayed = _filterStudentId == null
            ? gradeFiltered
            : gradeFiltered
                .where((s) => (s['student_id'] as int) == _filterStudentId)
                .toList();

        // Totals across displayed students
        double totalFeeAll = 0, totalPaidAll = 0;
        for (final s in displayed) {
          totalFeeAll += (s['total_fee'] as num).toDouble();
          totalPaidAll += (s['total_paid'] as num).toDouble();
        }
        final balanceAll = totalFeeAll - totalPaidAll;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Grade + Student filter dropdowns ──────────────────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: mindForgeCardDecoration(
                  color: AppColors.primary.withValues(alpha: 0.04)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<int?>(
                    initialValue: _filterGrade,
                    decoration: const InputDecoration(
                      labelText: 'Filter by Grade',
                      prefixIcon: Icon(Icons.school_outlined),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('All Grades')),
                      ...AppConstants.grades.map((g) => DropdownMenuItem(
                            value: g,
                            child: Text('Grade $g'),
                          )),
                    ],
                    onChanged: (v) => setState(() {
                      _filterGrade = v;
                      _filterStudentId = null; // reset student when grade changes
                    }),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int?>(
                    initialValue: _filterStudentId,
                    decoration: const InputDecoration(
                      labelText: 'Select Student',
                      prefixIcon: Icon(Icons.person_outline),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('All Students')),
                      ...gradeFiltered.map((s) => DropdownMenuItem(
                            value: s['student_id'] as int,
                            child: Text(
                                '${s['username']}  •  Grade ${s['grade']}'),
                          )),
                    ],
                    onChanged: (v) =>
                        setState(() => _filterStudentId = v),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Summary banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primaryDark, AppColors.primary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  _SummaryChip('Total Due', fmt.format(totalFeeAll),
                      Colors.white70, Colors.white),
                  _SummaryChip('Collected', fmt.format(totalPaidAll),
                      Colors.greenAccent.shade100, Colors.greenAccent),
                  _SummaryChip('Balance', fmt.format(balanceAll),
                      Colors.orange.shade100, Colors.orangeAccent),
                ],
              ),
            ),

            const SizedBox(height: 16),

            if (displayed.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Text('No students match the selected filters.',
                      style: TextStyle(color: AppColors.textSecondary)),
                ),
              ),

            // Per-student cards
            ...displayed.map((s) => _StudentPaymentCard(
                  summary: s,
                  academicYear: widget.selectedYear,
                  formatter: fmt,
                  onPaymentRecorded: () {
                    ref.invalidate(feeSummariesProvider);
                  },
                )),
          ],
        );
      },
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final Color labelColor;
  final Color valueColor;
  const _SummaryChip(this.label, this.value, this.labelColor, this.valueColor);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: TextStyle(fontSize: 10, color: labelColor),
              textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: valueColor),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _StudentPaymentCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> summary;
  final String academicYear;
  final NumberFormat formatter;
  final VoidCallback onPaymentRecorded;

  const _StudentPaymentCard({
    required this.summary,
    required this.academicYear,
    required this.formatter,
    required this.onPaymentRecorded,
  });

  @override
  ConsumerState<_StudentPaymentCard> createState() =>
      _StudentPaymentCardState();
}

class _StudentPaymentCardState extends ConsumerState<_StudentPaymentCard> {
  bool _expanded = false;
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _recording = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Color get _statusColor {
    final balance = (widget.summary['balance_due'] as num).toDouble();
    if (balance <= 0) return AppColors.success;
    final paid = (widget.summary['total_paid'] as num).toDouble();
    final total = (widget.summary['total_fee'] as num).toDouble();
    if (total > 0 && paid / total >= 0.5) return AppColors.warning;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    final username = s['username'] as String;
    final grade = s['grade'] as int;
    final totalFee = (s['total_fee'] as num).toDouble();
    final totalPaid = (s['total_paid'] as num).toDouble();
    final balance = (s['balance_due'] as num).toDouble();
    final payments = s['payments'] as List<dynamic>;
    final paidFraction = totalFee > 0 ? (totalPaid / totalFee).clamp(0.0, 1.0) : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: mindForgeCardDecoration(),
      child: Column(
        children: [
          // Header row
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor:
                            _statusColor.withValues(alpha: 0.15),
                        child: Text(
                          username[0].toUpperCase(),
                          style: TextStyle(
                              color: _statusColor,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(username,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15)),
                            Text('Grade $grade',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            balance <= 0
                                ? 'PAID'
                                : widget.formatter.format(balance),
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _statusColor,
                                fontSize: 14),
                          ),
                          Text(
                            balance <= 0 ? 'Fully paid' : 'Balance due',
                            style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      Icon(
                          _expanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          color: AppColors.textSecondary),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: paidFraction,
                      minHeight: 6,
                      backgroundColor: Colors.grey.shade200,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(_statusColor),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                          'Paid: ${widget.formatter.format(totalPaid)}',
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary)),
                      Text(
                          'Total: ${widget.formatter.format(totalFee)}',
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary)),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Expanded: payment log + record payment
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Payment log
                  if (payments.isNotEmpty) ...[
                    const Text('Payment History',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 8),
                    ...payments.map((p) => _PaymentLogTile(
                          payment: p,
                          formatter: widget.formatter,
                          onChanged: widget.onPaymentRecorded,
                        )),
                    const Divider(),
                    const SizedBox(height: 4),
                  ],

                  // Record new payment
                  const Text('Record Payment',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _amountCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Amount (₹)',
                            prefixIcon: Icon(Icons.currency_rupee),
                            isDense: true,
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _notesCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Notes (optional)',
                            prefixIcon: Icon(Icons.note_outlined),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 40,
                    child: ElevatedButton.icon(
                      icon: _recording
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.add, size: 18),
                      label: Text(_recording
                          ? 'Saving...'
                          : 'Record Payment'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success),
                      onPressed: _recording ? null : _recordPayment,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _recordPayment() async {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Enter a valid amount.'),
          backgroundColor: AppColors.error));
      return;
    }
    setState(() => _recording = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.recordFeePayment({
        'student_id': widget.summary['student_id'] as int,
        'amount': amount,
        'notes': _notesCtrl.text.trim().isEmpty
            ? null
            : _notesCtrl.text.trim(),
      });
      _amountCtrl.clear();
      _notesCtrl.clear();
      widget.onPaymentRecorded();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('₹${amount.toStringAsFixed(0)} recorded for ${widget.summary['username']}'),
            backgroundColor: AppColors.success));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _recording = false);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 3: Payment Info
// ─────────────────────────────────────────────────────────────────────────────

class _PaymentInfoTab extends ConsumerStatefulWidget {
  const _PaymentInfoTab();

  @override
  ConsumerState<_PaymentInfoTab> createState() => _PaymentInfoTabState();
}

class _PaymentInfoTabState extends ConsumerState<_PaymentInfoTab> {
  final _bankNameCtrl = TextEditingController();
  final _holderCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();
  final _ifscCtrl = TextEditingController();
  final _upiCtrl = TextEditingController();
  bool _initialized = false;
  bool _uploadingQr = false;
  String? _qrUrl;

  @override
  void dispose() {
    _bankNameCtrl.dispose();
    _holderCtrl.dispose();
    _accountCtrl.dispose();
    _ifscCtrl.dispose();
    _upiCtrl.dispose();
    super.dispose();
  }

  void _initControllers(PaymentInfoModel? info) {
    if (_initialized || info == null) return;
    _bankNameCtrl.text = info.bankName ?? '';
    _holderCtrl.text = info.accountHolder ?? '';
    _accountCtrl.text = info.accountNumber ?? '';
    _ifscCtrl.text = info.ifsc ?? '';
    _upiCtrl.text = info.upiId ?? '';
    _qrUrl = info.qrCodeUrl;
    _initialized = true;
  }

  Future<void> _pickAndUploadQr() async {
    final picker = ImagePicker();
    final picked =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null) return;

    setState(() => _uploadingQr = true);
    try {
      final bytes = await picked.readAsBytes();
      final api = ref.read(apiClientProvider);
      final result =
          await api.uploadQrCode(bytes, picked.name);
      setState(() {
        _qrUrl = result['qr_code_url'] as String?;
        _uploadingQr = false;
      });
      ref.invalidate(paymentInfoProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('QR code uploaded!'),
            backgroundColor: AppColors.success));
      }
    } catch (e) {
      setState(() => _uploadingQr = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: AppColors.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final infoAsync = ref.watch(paymentInfoProvider);
    return infoAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) {
        _initialized = false;
        return _buildForm(null);
      },
      data: (info) {
        _initControllers(info);
        return _buildForm(info);
      },
    );
  }

  Widget _buildForm(PaymentInfoModel? info) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Bank & UPI Details',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          TextField(
              controller: _bankNameCtrl,
              decoration: const InputDecoration(
                  labelText: 'Bank Name',
                  prefixIcon: Icon(Icons.account_balance))),
          const SizedBox(height: 10),
          TextField(
              controller: _holderCtrl,
              decoration: const InputDecoration(
                  labelText: 'Account Holder',
                  prefixIcon: Icon(Icons.person_outline))),
          const SizedBox(height: 10),
          TextField(
              controller: _accountCtrl,
              decoration: const InputDecoration(
                  labelText: 'Account Number',
                  prefixIcon: Icon(Icons.credit_card)),
              keyboardType: TextInputType.number),
          const SizedBox(height: 10),
          TextField(
              controller: _ifscCtrl,
              decoration: const InputDecoration(
                  labelText: 'IFSC Code', prefixIcon: Icon(Icons.tag)),
              textCapitalization: TextCapitalization.characters),
          const SizedBox(height: 10),
          TextField(
              controller: _upiCtrl,
              decoration: const InputDecoration(
                  labelText: 'UPI ID', prefixIcon: Icon(Icons.qr_code))),
          const SizedBox(height: 20),

          // QR Code section
          Text('UPI QR Code',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'Upload a QR code image from your photos so parents can scan and pay.',
            style:
                TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),

          // QR preview + upload button
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // QR preview box
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.divider, width: 2),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey.shade50,
                ),
                child: _qrUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          _qrUrl!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Center(
                              child: Icon(Icons.broken_image,
                                  color: AppColors.textMuted, size: 40)),
                        ),
                      )
                    : const Center(
                        child: Icon(Icons.qr_code_2,
                            size: 48, color: AppColors.textMuted),
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('QR code will be shown to parents for payment.',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 44,
                      child: ElevatedButton.icon(
                        icon: _uploadingQr
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white))
                            : const Icon(Icons.photo_library, size: 18),
                        label: Text(_uploadingQr
                            ? 'Uploading...'
                            : _qrUrl != null
                                ? 'Change QR'
                                : 'Upload QR'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.secondary),
                        onPressed:
                            _uploadingQr ? null : _pickAndUploadQr,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.save),
              label: const Text('Save Payment Info'),
              onPressed: _savePaymentInfo,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _savePaymentInfo() async {
    try {
      final api = ref.read(apiClientProvider);
      await api.updatePaymentInfo({
        'bank_name': _bankNameCtrl.text,
        'account_holder': _holderCtrl.text,
        'account_number': _accountCtrl.text,
        'ifsc': _ifscCtrl.text,
        'upi_id': _upiCtrl.text,
      });
      ref.invalidate(paymentInfoProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Payment info updated!'),
            backgroundColor: AppColors.success));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error));
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

class _FeeField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  const _FeeField({required this.ctrl, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextField(
        controller: ctrl,
        decoration: InputDecoration(labelText: label, prefixText: '₹ '),
        keyboardType: TextInputType.number,
      ),
    );
  }
}

class _FeeStructureTile extends ConsumerStatefulWidget {
  final FeeStructureModel structure;
  final NumberFormat formatter;
  const _FeeStructureTile(
      {required this.structure, required this.formatter});

  @override
  ConsumerState<_FeeStructureTile> createState() => _FeeStructureTileState();
}

class _FeeStructureTileState extends ConsumerState<_FeeStructureTile> {
  bool _editing = false;
  bool _saving = false;

  late final TextEditingController _baseCtrl;
  late final TextEditingController _econCtrl;
  late final TextEditingController _compCtrl;
  late final TextEditingController _aiCtrl;

  @override
  void initState() {
    super.initState();
    _baseCtrl = TextEditingController(
        text: widget.structure.baseAmount.toStringAsFixed(0));
    _econCtrl = TextEditingController(
        text: widget.structure.economicsFee.toStringAsFixed(0));
    _compCtrl = TextEditingController(
        text: widget.structure.computerFee.toStringAsFixed(0));
    _aiCtrl = TextEditingController(
        text: widget.structure.aiFee.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _baseCtrl.dispose();
    _econCtrl.dispose();
    _compCtrl.dispose();
    _aiCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.updateFeeStructure(widget.structure.id, {
        'base_amount': double.tryParse(_baseCtrl.text) ?? 0,
        'economics_fee': double.tryParse(_econCtrl.text) ?? 0,
        'computer_fee': double.tryParse(_compCtrl.text) ?? 0,
        'ai_fee': double.tryParse(_aiCtrl.text) ?? 0,
      });
      ref.invalidate(feeStructuresProvider);
      ref.invalidate(feeSummariesProvider);
      setState(() => _editing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Fee structure updated!'),
            backgroundColor: AppColors.success));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Fee Structure'),
        content: Text(
            'Delete fee structure for Grade ${widget.structure.grade}? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final api = ref.read(apiClientProvider);
      await api.deleteFeeStructure(widget.structure.id);
      ref.invalidate(feeStructuresProvider);
      ref.invalidate(feeSummariesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Fee structure deleted.'),
            backgroundColor: AppColors.error));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = widget.formatter;
    final s = widget.structure;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: mindForgeCardDecoration(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ──────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Grade ${s.grade}',
                        style: Theme.of(context).textTheme.titleMedium),
                    Text(fmt.format(s.totalAmount),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: AppColors.primary)),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  _editing ? Icons.close : Icons.edit_outlined,
                  color: _editing ? AppColors.textSecondary : AppColors.primary,
                  size: 20,
                ),
                tooltip: _editing ? 'Cancel' : 'Edit',
                onPressed: () => setState(() => _editing = !_editing),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: AppColors.error, size: 20),
                tooltip: 'Delete',
                onPressed: _delete,
              ),
            ],
          ),

          // ── Read-only breakdown ──────────────────────────────────────
          if (!_editing) ...[
            const SizedBox(height: 8),
            if (s.baseAmount > 0) _AmountRow('Base', s.baseAmount, fmt),
            if (s.economicsFee > 0) _AmountRow('Economics', s.economicsFee, fmt),
            if (s.computerFee > 0) _AmountRow('Computer', s.computerFee, fmt),
            if (s.aiFee > 0) _AmountRow('AI', s.aiFee, fmt),
          ],

          // ── Inline edit form ─────────────────────────────────────────
          if (_editing) ...[
            const Divider(height: 20),
            _FeeField(ctrl: _baseCtrl, label: 'Base Amount'),
            _FeeField(ctrl: _econCtrl, label: 'Economics Fee'),
            _FeeField(ctrl: _compCtrl, label: 'Computer Fee'),
            _FeeField(ctrl: _aiCtrl, label: 'AI Fee'),
            const SizedBox(height: 12),
            SizedBox(
              height: 40,
              child: ElevatedButton.icon(
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save, size: 18),
                label: Text(_saving ? 'Saving…' : 'Save Changes'),
                onPressed: _saving ? null : _save,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  final String label;
  final double amount;
  final NumberFormat fmt;
  const _AmountRow(this.label, this.amount, this.fmt);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
          Text(fmt.format(amount),
              style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Payment log tile — supports inline edit and delete
// ─────────────────────────────────────────────────────────────────────────────

class _PaymentLogTile extends ConsumerStatefulWidget {
  final Map<String, dynamic> payment;
  final NumberFormat formatter;
  final VoidCallback onChanged;

  const _PaymentLogTile({
    required this.payment,
    required this.formatter,
    required this.onChanged,
  });

  @override
  ConsumerState<_PaymentLogTile> createState() => _PaymentLogTileState();
}

class _PaymentLogTileState extends ConsumerState<_PaymentLogTile> {
  bool _editing = false;
  bool _saving = false;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(
        text: (widget.payment['amount'] as num).toStringAsFixed(0));
    _notesCtrl =
        TextEditingController(text: widget.payment['notes'] as String? ?? '');
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Enter a valid amount.'),
          backgroundColor: AppColors.error));
      return;
    }
    setState(() => _saving = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.updateFeePayment(
          widget.payment['id'] as int, amount, _notesCtrl.text.trim());
      setState(() => _editing = false);
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'), backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Payment'),
        content: Text(
            'Delete this payment of ${widget.formatter.format((widget.payment['amount'] as num).toDouble())}? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final api = ref.read(apiClientProvider);
      await api.deleteFeePayment(widget.payment['id'] as int);
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'), backgroundColor: AppColors.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = (widget.payment['amount'] as num).toDouble();
    final date = DateTime.parse(widget.payment['paid_at'] as String);
    final notes = widget.payment['notes'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: _editing ? AppColors.primary : AppColors.divider,
            width: _editing ? 1.5 : 1),
      ),
      child: _editing
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _amountCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Amount (₹)',
                          prefixIcon: Icon(Icons.currency_rupee, size: 16),
                          isDense: true,
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _notesCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Notes',
                          prefixIcon: Icon(Icons.note_outlined, size: 16),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => setState(() => _editing = false),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 34,
                      child: ElevatedButton.icon(
                        icon: _saving
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save, size: 15),
                        label: Text(_saving ? 'Saving…' : 'Save'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12)),
                        onPressed: _saving ? null : _save,
                      ),
                    ),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                const Icon(Icons.check_circle,
                    size: 16, color: AppColors.success),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.formatter.format(amount),
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                      if (notes != null && notes.isNotEmpty)
                        Text(notes,
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary)),
                      Text(DateFormat('dd MMM yyyy').format(date),
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined,
                      size: 16, color: AppColors.primary),
                  tooltip: 'Edit',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => setState(() => _editing = true),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 16, color: AppColors.error),
                  tooltip: 'Delete',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _delete,
                ),
              ],
            ),
    );
  }
}

class _RetryWidget extends StatelessWidget {
  final VoidCallback onRetry;
  const _RetryWidget({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, size: 48, color: Colors.red),
        const SizedBox(height: 8),
        const Text('Failed to load data'),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
          onPressed: onRetry,
        ),
      ]),
    );
  }
}
