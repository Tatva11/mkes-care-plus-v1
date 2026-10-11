import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../models/billing_invoice_model.dart';
import '../models/billing_payment_model.dart';
import '../providers/billing_provider.dart';
import '../widgets/billing_summary_cards.dart';
import '../widgets/record_payment_dialog.dart';
import '../../reports/screens/admin_reports_screen.dart';
import 'billing_reports_screen.dart';
import 'create_invoice_screen.dart';

class BillingManagementScreen extends StatelessWidget {
  final bool isEmbedded;
  final bool isStaff;

  const BillingManagementScreen({
    super.key,
    this.isEmbedded = false,
    this.isStaff = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isEmbedded) {
      return BillingManagementContent(isStaff: isStaff);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Billing & Invoices'),
        actions: [
          if (!isStaff)
            IconButton(
              icon: const Icon(Icons.analytics_outlined),
              tooltip: 'Reports & Analytics',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AdminReportsScreen(),
                  ),
                );
              },
            ),
        ],
      ),
      body: BillingManagementContent(isStaff: isStaff),
    );
  }
}

class BillingManagementContent extends ConsumerStatefulWidget {
  final bool isStaff;

  const BillingManagementContent({
    super.key,
    this.isStaff = false,
  });

  @override
  ConsumerState<BillingManagementContent> createState() =>
      _BillingManagementContentState();
}

class _BillingManagementContentState
    extends ConsumerState<BillingManagementContent> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _invalidateInvoices() {
    if (widget.isStaff) {
      ref.invalidate(staffBillingInvoicesProvider);
    } else {
      ref.invalidate(adminBillingInvoicesProvider);
    }
  }

  void _updateFilter(BillingFilter newFilter) {
    if (widget.isStaff) {
      ref.read(staffBillingFilterProvider.notifier).state = newFilter;
    } else {
      ref.read(adminBillingFilterProvider.notifier).state = newFilter;
    }
  }

  void _openCreateInvoiceDialog([String? defaultDepartment]) async {
    final result = await Navigator.of(context).push<BillingInvoiceModel>(
      MaterialPageRoute(
        builder: (_) => CreateInvoiceScreen(
          initialDepartment: defaultDepartment,
        ),
      ),
    );

    if (result != null && mounted) {
      _invalidateInvoices();
    }
  }

  void _showInvoiceDetails(BillingInvoiceModel invoice) {
    showDialog(
      context: context,
      builder: (dialogCtx) => _InvoiceDetailsDialog(
        invoiceId: invoice.id,
        fallback: invoice,
      ),
    );
  }

  void _openRecordPayment(BillingInvoiceModel invoice) async {
    final payment = await showDialog<BillingPaymentModel>(
      context: context,
      builder: (dialogCtx) => RecordPaymentDialog(invoice: invoice),
    );

    if (payment != null && mounted) {
      _invalidateInvoices();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Payment of ₹${payment.amount.toStringAsFixed(2)} recorded for ${invoice.invoiceNumber}.',
            ),
            backgroundColor: Colors.green[800],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _pickCustomDateRange(BillingFilter filter) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: filter.customStartDate != null && filter.customEndDate != null
          ? DateTimeRange(start: filter.customStartDate!, end: filter.customEndDate!)
          : DateTimeRange(
              start: now.subtract(const Duration(days: 7)),
              end: now,
            ),
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 365)),
    );

    if (picked != null) {
      _updateFilter(
        filter.copyWith(
          datePreset: BillingDatePreset.custom,
          customStartDate: picked.start,
          customEndDate: picked.end,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = widget.isStaff
        ? ref.watch(staffBillingFilterProvider)
        : ref.watch(adminBillingFilterProvider);
    final invoicesAsync = widget.isStaff
        ? ref.watch(staffBillingInvoicesProvider)
        : ref.watch(adminBillingInvoicesProvider);
    final isDesktop = MediaQuery.sizeOf(context).width >= 768;

    return RefreshIndicator(
      onRefresh: () async {
        _invalidateInvoices();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(
          isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Action & Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Billing & Invoices',
                      style: AppTypography.headlineMd.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.isStaff
                          ? 'Create patient invoices and record payments'
                          : 'Manage patient invoices, payments, and financial ledger',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (!widget.isStaff) ...[
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const BillingReportsScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.analytics_outlined, size: 18),
                        label: const Text('Reports & Analytics'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    FilledButton.icon(
                      onPressed: () => _openCreateInvoiceDialog(
                        filter.department == 'all' ? 'eye' : filter.department,
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('New Invoice'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            // Financial Summary & Revenue Cards (Visible ONLY for Admin, Hidden for Staff)
            if (!widget.isStaff) ...[
              const BillingSummaryCards(),
              const SizedBox(height: AppSpacing.lg),
            ],

            // Filter and Search Toolbar
            _buildToolbar(filter, isDesktop),
            const SizedBox(height: AppSpacing.md),

            // Invoices Table / List
            invoicesAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(48.0),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (err, _) => Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.errorContainer,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Center(
                  child: Text(
                    'Error loading invoices: $err',
                    style: AppTypography.bodyMd.copyWith(
                      color: AppColors.onErrorContainer,
                    ),
                  ),
                ),
              ),
              data: (invoices) {
                if (invoices.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      border: Border.all(color: AppColors.outlineVariant),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.receipt_long_outlined,
                            size: 48,
                            color: AppColors.outline,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'No invoices found for the selected filter.',
                            style: AppTypography.bodyMd.copyWith(
                              color: AppColors.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Create a new Eye or Dental invoice to get started.',
                            style: AppTypography.bodySm.copyWith(
                              color: AppColors.outline,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          FilledButton.icon(
                            onPressed: () => _openCreateInvoiceDialog(),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Create Invoice'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    border: Border.all(color: AppColors.outlineVariant),
                  ),
                  child: isDesktop
                      ? _buildDesktopTable(invoices)
                      : _buildMobileList(invoices),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar(BillingFilter filter, bool isDesktop) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Department filter
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'all', label: Text('All Depts')),
                  ButtonSegment(value: 'eye', label: Text('Eye')),
                  ButtonSegment(value: 'dental', label: Text('Dental')),
                ],
                selected: {filter.department},
                onSelectionChanged: (s) {
                  _updateFilter(filter.copyWith(department: s.first));
                },
              ),

              // Date Range Preset Filter
              DropdownButton<BillingDatePreset>(
                value: filter.datePreset,
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                items: const [
                  DropdownMenuItem(
                    value: BillingDatePreset.allTime,
                    child: Text('All Time'),
                  ),
                  DropdownMenuItem(
                    value: BillingDatePreset.today,
                    child: Text('Today'),
                  ),
                  DropdownMenuItem(
                    value: BillingDatePreset.thisWeek,
                    child: Text('This Week'),
                  ),
                  DropdownMenuItem(
                    value: BillingDatePreset.thisMonth,
                    child: Text('This Month'),
                  ),
                  DropdownMenuItem(
                    value: BillingDatePreset.thisYear,
                    child: Text('This Year'),
                  ),
                  DropdownMenuItem(
                    value: BillingDatePreset.custom,
                    child: Text('Custom Date Range...'),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    if (val == BillingDatePreset.custom) {
                      _pickCustomDateRange(filter);
                    } else {
                      _updateFilter(
                        filter.copyWith(
                          datePreset: val,
                          clearCustomDates: true,
                        ),
                      );
                    }
                  }
                },
              ),

              // Custom Date Range Display Badge (if active)
              if (filter.datePreset == BillingDatePreset.custom &&
                  filter.customStartDate != null &&
                  filter.customEndDate != null)
                InputChip(
                  avatar: const Icon(Icons.date_range, size: 16),
                  label: Text(
                    '${DateFormat('dd MMM').format(filter.customStartDate!)} - ${DateFormat('dd MMM yyyy').format(filter.customEndDate!)}',
                    style: AppTypography.bodySm.copyWith(fontSize: 12),
                  ),
                  onPressed: () => _pickCustomDateRange(filter),
                  onDeleted: () {
                    _updateFilter(
                      filter.copyWith(
                        datePreset: BillingDatePreset.allTime,
                        clearCustomDates: true,
                      ),
                    );
                  },
                ),

              // Status filter (Only Paid and Partially Paid)
              DropdownButton<String>(
                value: filter.status,
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All Statuses')),
                  DropdownMenuItem(value: 'paid', child: Text('Paid')),
                  DropdownMenuItem(value: 'partially_paid', child: Text('Partially Paid')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    _updateFilter(filter.copyWith(status: val));
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // Search field
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search by Invoice Number (e.g. 1/26-27) or patient...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        _updateFilter(filter.copyWith(searchQuery: ''));
                      },
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
            ),
            onChanged: (val) {
              _updateFilter(filter.copyWith(searchQuery: val));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopTable(List<BillingInvoiceModel> invoices) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1.8), // Invoice #
        1: FlexColumnWidth(1.1), // Date
        2: FlexColumnWidth(2.3), // Patient
        3: FlexColumnWidth(1.1), // Dept
        4: FlexColumnWidth(1.4), // Total
        5: FlexColumnWidth(1.4), // Paid
        6: FlexColumnWidth(1.4), // Remaining
        7: FlexColumnWidth(1.6), // Status
        8: FlexColumnWidth(1.5), // Actions
      },
      children: [
        TableRow(
          decoration: const BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
          ),
          children: [
            _tableHeader('Invoice #'),
            _tableHeader('Date'),
            _tableHeader('Patient'),
            _tableHeader('Department'),
            _tableHeader('Total (₹)'),
            _tableHeader('Paid (₹)'),
            _tableHeader('Remaining (₹)'),
            _tableHeader('Status'),
            _tableHeader('Actions'),
          ],
        ),
        for (final inv in invoices)
          TableRow(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.outlineVariant, width: 0.5)),
            ),
            children: [
              _tableCell(
                InkWell(
                  onTap: () => _showInvoiceDetails(inv),
                  child: Text(
                    inv.invoiceNumber,
                    style: AppTypography.bodySm.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
              _tableCell(
                Text(
                  DateFormat('dd/MM/yyyy').format(inv.createdAt),
                  style: AppTypography.bodySm,
                ),
              ),
              _tableCell(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      inv.patientName ?? '—',
                      style: AppTypography.bodySm.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (inv.patientNumber != null)
                      Text(
                        inv.patientNumber!,
                        style: AppTypography.labelCaps.copyWith(
                          color: AppColors.outline,
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ),
              _tableCell(
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: inv.department == 'eye'
                        ? AppColors.primaryContainer.withValues(alpha: 0.15)
                        : AppColors.secondaryContainer.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    inv.department.toUpperCase(),
                    style: AppTypography.labelCaps.copyWith(
                      color: inv.department == 'eye'
                          ? AppColors.primary
                          : AppColors.secondary,
                    ),
                  ),
                ),
              ),
              _tableCell(
                Text(
                  '₹${inv.totalAmount.toStringAsFixed(2)}',
                  style: AppTypography.bodySm.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _tableCell(
                Text(
                  '₹${inv.amountPaid.toStringAsFixed(2)}',
                  style: AppTypography.bodySm,
                ),
              ),
              _tableCell(
                Text(
                  '₹${inv.remainingAmount.toStringAsFixed(2)}',
                  style: AppTypography.bodySm.copyWith(
                    color: inv.remainingAmount > 0 ? AppColors.error : Colors.green[800],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _tableCell(_buildStatusBadge(inv)),
              _tableCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      color: AppColors.primary,
                      tooltip: 'View Bill & Payments',
                      onPressed: () => _showInvoiceDetails(inv),
                    ),
                    if (inv.remainingAmount > 0 && !inv.isCancelled)
                      IconButton(
                        icon: const Icon(Icons.payments_outlined, size: 18),
                        color: Colors.green[700],
                        tooltip: 'Record Payment',
                        onPressed: () => _openRecordPayment(inv),
                      ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildMobileList(List<BillingInvoiceModel> invoices) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: invoices.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final inv = invoices[index];
        return ListTile(
          onTap: () => _showInvoiceDetails(inv),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                inv.invoiceNumber,
                style: AppTypography.bodyMd.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              _buildStatusBadge(inv),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                '${inv.patientName ?? "Patient"} (${inv.patientNumber ?? "—"}) • ${inv.department.toUpperCase()}',
                style: AppTypography.bodySm,
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total: ₹${inv.totalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'Remaining: ₹${inv.remainingAmount.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: inv.remainingAmount > 0 ? AppColors.error : Colors.green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          trailing: inv.remainingAmount > 0 && !inv.isCancelled
              ? IconButton(
                  icon: const Icon(Icons.add_card, size: 20),
                  color: Colors.green[700],
                  tooltip: 'Record Payment',
                  onPressed: () => _openRecordPayment(inv),
                )
              : const Icon(Icons.chevron_right, size: 20),
        );
      },
    );
  }

  Widget _tableHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Text(
        title,
        style: AppTypography.labelCaps.copyWith(
          color: AppColors.onSurfaceVariant,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _tableCell(Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: child,
    );
  }

  Widget _buildStatusBadge(BillingInvoiceModel inv) {
    final isPaid = inv.isPaid;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isPaid
            ? Colors.green.withValues(alpha: 0.15)
            : Colors.orange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isPaid ? 'PAID' : 'PARTIALLY PAID',
        style: TextStyle(
          color: isPaid ? Colors.green[800]! : Colors.orange[800]!,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Dialog displaying the complete itemized bill/invoice details with services & payment history.
class _InvoiceDetailsDialog extends ConsumerWidget {
  final String invoiceId;
  final BillingInvoiceModel fallback;

  const _InvoiceDetailsDialog({
    required this.invoiceId,
    required this.fallback,
  });

  void _openRecordPayment(BuildContext context, BillingInvoiceModel invoice, WidgetRef ref) async {
    final payment = await showDialog<BillingPaymentModel>(
      context: context,
      builder: (dialogCtx) => RecordPaymentDialog(invoice: invoice),
    );

    if (payment != null) {
      ref.invalidate(invoiceDetailsProvider(invoice.id));
      ref.invalidate(billingInvoicesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Payment of ₹${payment.amount.toStringAsFixed(2)} recorded successfully.',
            ),
            backgroundColor: Colors.green[800],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoiceAsync = ref.watch(invoiceDetailsProvider(invoiceId));

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 620),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: invoiceAsync.when(
          loading: () => const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, __) => _buildInvoiceContent(context, fallback, ref),
          data: (invoice) => _buildInvoiceContent(context, invoice, ref),
        ),
      ),
    );
  }

  Widget _buildInvoiceContent(
    BuildContext context,
    BillingInvoiceModel invoice,
    WidgetRef ref,
  ) {
    final isPaid = invoice.isPaid;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'INVOICE',
                    style: AppTypography.labelCaps.copyWith(
                      color: AppColors.primary,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(
                    invoice.invoiceNumber,
                    style: AppTypography.headlineMd.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurface,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isPaid ? Colors.green : Colors.orange,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Text(
                  isPaid ? 'PAID' : 'PARTIALLY PAID',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // Date & Patient Info Box
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Patient: ${invoice.patientName ?? "—"}',
                      style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Patient #: ${invoice.patientNumber ?? "—"} • Mobile: ${invoice.patientMobile ?? "—"}',
                      style: AppTypography.bodySm,
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Dept: ${invoice.department.toUpperCase()}',
                      style: AppTypography.labelCaps.copyWith(color: AppColors.primary),
                    ),
                    Text(
                      DateFormat('dd MMM yyyy').format(invoice.createdAt),
                      style: AppTypography.bodySm,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Itemized Services Breakdown Table
          Text(
            'Services Provided',
            style: AppTypography.labelCaps.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: const BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: Text(
                          'Service Description',
                          style: AppTypography.labelCaps.copyWith(fontSize: 10),
                        ),
                      ),
                      SizedBox(
                        width: 35,
                        child: Text(
                          'Qty',
                          textAlign: TextAlign.center,
                          style: AppTypography.labelCaps.copyWith(fontSize: 10),
                        ),
                      ),
                      SizedBox(
                        width: 70,
                        child: Text(
                          'Unit Price',
                          textAlign: TextAlign.right,
                          style: AppTypography.labelCaps.copyWith(fontSize: 10),
                        ),
                      ),
                      SizedBox(
                        width: 80,
                        child: Text(
                          'Total',
                          textAlign: TextAlign.right,
                          style: AppTypography.labelCaps.copyWith(fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                ),
                // Line items
                if (invoice.items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Clinical Services Consultation',
                      style: AppTypography.bodySm,
                    ),
                  )
                else
                  for (int i = 0; i < invoice.items.length; i++) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 5,
                            child: Text(
                              invoice.items[i].serviceName,
                              style: AppTypography.bodySm.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 35,
                            child: Text(
                              '${invoice.items[i].quantity}',
                              textAlign: TextAlign.center,
                              style: AppTypography.bodySm,
                            ),
                          ),
                          SizedBox(
                            width: 70,
                            child: Text(
                              '₹${invoice.items[i].unitPrice.toStringAsFixed(2)}',
                              textAlign: TextAlign.right,
                              style: AppTypography.bodySm,
                            ),
                          ),
                          SizedBox(
                            width: 80,
                            child: Text(
                              '₹${invoice.items[i].totalAmount.toStringAsFixed(2)}',
                              textAlign: TextAlign.right,
                              style: AppTypography.bodySm.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (i < invoice.items.length - 1)
                      const Divider(height: 1, color: AppColors.outlineVariant),
                  ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Financial Summary
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Column(
              children: [
                _detailRow('Subtotal', '₹${invoice.subtotal.toStringAsFixed(2)}'),
                if (invoice.discount > 0)
                  _detailRow(
                    'Discount',
                    '- ₹${invoice.discount.toStringAsFixed(2)}',
                    color: Colors.green[800],
                  ),
                _detailRow(
                  'Final Total',
                  '₹${invoice.totalAmount.toStringAsFixed(2)}',
                  isBold: true,
                ),
                _detailRow(
                  'Amount Paid',
                  '₹${invoice.amountPaid.toStringAsFixed(2)}',
                  color: AppColors.primary,
                ),
                _detailRow(
                  'Remaining Balance',
                  '₹${invoice.remainingAmount.toStringAsFixed(2)}',
                  color: invoice.remainingAmount > 0 ? AppColors.error : Colors.green[800],
                  isBold: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Payment History Section
          Text(
            'Payment History (${invoice.payments.length})',
            style: AppTypography.labelCaps.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: const BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          'Date & Time',
                          style: AppTypography.labelCaps.copyWith(fontSize: 10),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'Mode',
                          style: AppTypography.labelCaps.copyWith(fontSize: 10),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          'Reference / Notes',
                          style: AppTypography.labelCaps.copyWith(fontSize: 10),
                        ),
                      ),
                      SizedBox(
                        width: 80,
                        child: Text(
                          'Amount',
                          textAlign: TextAlign.right,
                          style: AppTypography.labelCaps.copyWith(fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                ),
                // Payment records
                if (invoice.payments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Center(
                      child: Text(
                        'No recorded payments yet.',
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                else
                  for (int i = 0; i < invoice.payments.length; i++) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              invoice.payments[i].paidAt != null
                                  ? DateFormat('dd/MM/yy hh:mm a').format(invoice.payments[i].paidAt!)
                                  : '—',
                              style: AppTypography.bodySm.copyWith(fontSize: 11),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              invoice.payments[i].paymentMode.toUpperCase(),
                              style: AppTypography.labelCaps.copyWith(
                                color: AppColors.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              invoice.payments[i].paymentReference ??
                                  invoice.payments[i].notes ??
                                  '—',
                              style: AppTypography.bodySm.copyWith(fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(
                            width: 80,
                            child: Text(
                              '₹${invoice.payments[i].amount.toStringAsFixed(2)}',
                              textAlign: TextAlign.right,
                              style: AppTypography.bodySm.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.green[800],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (i < invoice.payments.length - 1)
                      const Divider(height: 1, color: AppColors.outlineVariant),
                  ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Action Buttons Footer
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (invoice.remainingAmount > 0 && !invoice.isCancelled)
                FilledButton.icon(
                  onPressed: () => _openRecordPayment(context, invoice, ref),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Record Payment'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                )
              else
                const SizedBox.shrink(),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                child: const Text('Close'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, {Color? color, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
          ),
          Text(
            value,
            style: AppTypography.bodySm.copyWith(
              color: color ?? AppColors.onSurface,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

