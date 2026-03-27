import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/fees.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/responsive.dart';
import '../providers/parent_provider.dart';
import '../widgets/parent_bottom_nav.dart';
import '../widgets/parent_error_widget.dart';

class ParentFeesScreen extends ConsumerWidget {
  const ParentFeesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feesAsync = ref.watch(parentChildFeesProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Fees'),
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorColor: AppColors.accent,
            tabs: [
              Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Summary'),
              Tab(icon: Icon(Icons.payment_outlined), text: 'Pay'),
            ],
          ),
        ),
        bottomNavigationBar: const ParentBottomNav(),
        body: feesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => parentErrorWidget(e),
          data: (fees) => TabBarView(
            children: [
              _SummaryTab(fees: fees),
              _PayTab(fees: fees),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Tab 1: Fee Summary + Payment History ────────────────────────────────────

class _SummaryTab extends StatelessWidget {
  final StudentFeeSummaryModel fees;
  const _SummaryTab({required this.fees});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BalanceSummaryCard(fees: fees),
          const SizedBox(height: 16),
          Text('Payment History',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          if (fees.payments.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: mindForgeCardDecoration(),
              child: const Center(
                child: Text('No payments recorded yet.',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else
            ...fees.payments.map((p) => _PaymentTile(payment: p)),
        ],
      ),
    );
  }
}

// ── Tab 2: Payment Info + QR Code ───────────────────────────────────────────

class _PayTab extends StatelessWidget {
  final StudentFeeSummaryModel fees;
  const _PayTab({required this.fees});

  @override
  Widget build(BuildContext context) {
    final info = fees.paymentInfo;

    if (info == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.account_balance_outlined,
                  size: 64, color: AppColors.textSecondary),
              SizedBox(height: 16),
              Text(
                'Payment details not set up yet.\nPlease contact the admin.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Balance due reminder
          if (fees.balanceDue > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.error.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: AppColors.error, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Balance Due: ${NumberFormat.currency(symbol: '₹', decimalDigits: 0).format(fees.balanceDue)}',
                    style: const TextStyle(
                        color: AppColors.error, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Bank details card
          if (info.bankName != null ||
              info.accountHolder != null ||
              info.accountNumber != null ||
              info.ifsc != null) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: mindForgeCardDecoration(
                  color: AppColors.primary.withOpacity(0.03)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.account_balance,
                          color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Text('Bank Transfer',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: AppColors.primary)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (info.bankName != null)
                    _DetailRow(
                        icon: Icons.account_balance_outlined,
                        label: 'Bank',
                        value: info.bankName!),
                  if (info.accountHolder != null)
                    _DetailRow(
                        icon: Icons.person_outline,
                        label: 'Account Holder',
                        value: info.accountHolder!),
                  if (info.accountNumber != null)
                    _DetailRow(
                        icon: Icons.credit_card_outlined,
                        label: 'Account Number',
                        value: info.accountNumber!),
                  if (info.ifsc != null)
                    _DetailRow(
                        icon: Icons.tag,
                        label: 'IFSC',
                        value: info.ifsc!),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // UPI + QR Code card
          if (info.upiId != null || info.qrCodeUrl != null) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: mindForgeCardDecoration(
                  color: AppColors.secondary.withOpacity(0.03)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.qr_code_2,
                          color: AppColors.secondary, size: 20),
                      const SizedBox(width: 8),
                      Text('UPI Payment',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: AppColors.secondary)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (info.upiId != null)
                    _DetailRow(
                        icon: Icons.qr_code,
                        label: 'UPI ID',
                        value: info.upiId!),
                  if (info.qrCodeUrl != null) ...[
                    const SizedBox(height: 16),
                    const Text('Scan to Pay',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                            fontSize: 13)),
                    const SizedBox(height: 12),
                    Center(
                      child: Container(
                        width: R.fluid(context, 220, min: 160, max: 260),
                        height: R.fluid(context, 220, min: 160, max: 260),
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: AppColors.divider, width: 2),
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.white,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            info.qrCodeUrl!,
                            fit: BoxFit.contain,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return const Center(
                                  child: CircularProgressIndicator());
                            },
                            errorBuilder: (_, __, ___) => const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.broken_image_outlined,
                                      size: 48,
                                      color: AppColors.textSecondary),
                                  SizedBox(height: 8),
                                  Text('Could not load QR',
                                      style: TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 12)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Shared widgets ───────────────────────────────────────────────────────────

class _BalanceSummaryCard extends StatelessWidget {
  final StudentFeeSummaryModel fees;
  const _BalanceSummaryCard({required this.fees});

  @override
  Widget build(BuildContext context) {
    final isDue = fees.balanceDue > 0;
    final hasBreakdown = fees.totalFee > 0;

    // Collect breakdown items that are non-zero
    final breakdownItems = <(String, double)>[
      if (fees.baseAmount > 0) ('Base Fee', fees.baseAmount),
      if (fees.economicsFee > 0) ('Economics', fees.economicsFee),
      if (fees.computerFee > 0) ('Computer Applications', fees.computerFee),
      if (fees.aiFee > 0) ('Artificial Intelligence', fees.aiFee),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: mindForgeCardDecoration(
          color: isDue
              ? AppColors.error.withOpacity(0.04)
              : AppColors.success.withOpacity(0.04)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Fee Summary',
                  style: Theme.of(context).textTheme.titleMedium),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(fees.academicYear,
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          Text('Grade ${fees.grade}',
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 13)),
          const SizedBox(height: 16),

          // Fee breakdown
          if (hasBreakdown && breakdownItems.isNotEmpty) ...[
            Text('Fee Breakdown',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: AppColors.textMuted)),
            const SizedBox(height: 8),
            ...breakdownItems.map((item) => _FeeRow(
                  label: '  ${item.$1}',
                  amount: item.$2,
                  color: AppColors.textSecondary,
                  isSmall: true,
                )),
            const Divider(height: 16),
          ],

          _FeeRow(
              label: 'Total Fee',
              amount: fees.totalFee,
              color: AppColors.textPrimary,
              isBold: true),
          _FeeRow(
              label: 'Amount Paid',
              amount: fees.totalPaid,
              color: AppColors.success),
          const Divider(height: 16),
          _FeeRow(
              label: 'Balance Due',
              amount: fees.balanceDue,
              color: isDue ? AppColors.error : AppColors.success,
              isBold: true),
        ],
      ),
    );
  }
}

class _FeeRow extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final bool isBold;
  final bool isSmall;

  const _FeeRow({
    required this.label,
    required this.amount,
    required this.color,
    this.isBold = false,
    this.isSmall = false,
  });

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: isSmall ? 13 : null,
                  fontWeight: isBold ? FontWeight.bold : null)),
          Text(formatter.format(amount),
              style: TextStyle(
                  color: color,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
                  fontSize: isBold ? 16 : (isSmall ? 13 : 14))),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Text('$label: ',
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 13)),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  final FeePaymentModel payment;
  const _PaymentTile({required this.payment});

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: mindForgeCardDecoration(),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.success.withOpacity(0.15),
          child: const Icon(Icons.check, color: AppColors.success),
        ),
        title: Text(formatter.format(payment.amount),
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Text(DateFormat('dd MMM yyyy').format(payment.paidAt)),
        trailing: payment.notes != null
            ? Tooltip(
                message: payment.notes!,
                child: const Icon(Icons.info_outline,
                    color: AppColors.textMuted),
              )
            : null,
      ),
    );
  }
}
