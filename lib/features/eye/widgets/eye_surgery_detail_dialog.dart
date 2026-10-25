import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/providers/auth_provider.dart';
import '../../billing/models/billing_invoice_model.dart';
import '../../billing/models/billing_item_model.dart';
import '../../billing/repositories/billing_repository.dart';
import '../../billing/screens/create_invoice_screen.dart';
import '../../patients/models/patient_model.dart';
import '../../patients/repositories/patient_repository.dart';
import '../models/eye_surgery_insurance_model.dart';
import '../models/eye_surgery_model.dart';
import '../providers/eye_surgery_provider.dart';
import '../../appointments/repositories/appointment_repository.dart';
import '../../appointments/widgets/appointment_form_dialog.dart';
import 'assign_eye_surgery_staff_dialog.dart';
import 'eye_surgery_insurance_dialogs.dart';

/// Modal dialog displaying full details of an eye surgery.
/// Provides 4 dedicated tabs:
/// 1. Surgery details & clinical progress
/// 2. Surgery billing
/// 3. Insurance (Eye Surgery only - Cashless & Reimbursement)
/// 4. Payment history & outstanding balances
class EyeSurgeryDetailDialog extends ConsumerStatefulWidget {
  const EyeSurgeryDetailDialog({
    super.key,
    required this.surgery,
    this.initialTabIndex = 0,
  });

  final EyeSurgeryModel surgery;
  final int initialTabIndex;

  @override
  ConsumerState<EyeSurgeryDetailDialog> createState() =>
      _EyeSurgeryDetailDialogState();
}

class _EyeSurgeryDetailDialogState extends ConsumerState<EyeSurgeryDetailDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _tabCount = 4;
  static const Color _successColor = Color(0xFF2E7D32);

  @override
  void initState() {
    super.initState();
    _tabCount = widget.surgery.canAccessBilling ? 4 : 1;
    final initialIdx = widget.surgery.canAccessBilling
        ? widget.initialTabIndex.clamp(0, _tabCount - 1)
        : 0;
    _tabController = TabController(
      length: _tabCount,
      vsync: this,
      initialIndex: initialIdx,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(currentUserRoleProvider).valueOrNull;
    final isAdmin = role?.toLowerCase() == 'admin';
    final surgeries = ref.watch(eyeSurgeryListProvider).valueOrNull;
    final surgery = surgeries?.firstWhere(
      (s) => s.id == widget.surgery.id,
      orElse: () => widget.surgery,
    ) ?? widget.surgery;

    final targetTabCount = surgery.canAccessBilling ? 4 : 1;
    if (_tabCount != targetTabCount) {
      final oldIndex = _tabController.index;
      _tabController.dispose();
      _tabCount = targetTabCount;
      _tabController = TabController(
        length: _tabCount,
        vsync: this,
        initialIndex: oldIndex.clamp(0, _tabCount - 1),
      );
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 720,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: const Icon(
                      Icons.visibility_outlined,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: AppSpacing.xs,
                          runSpacing: 2,
                          children: [
                            Text(
                              surgery.displaySurgeryType,
                              style: AppTypography.headlineMd.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            _buildStatusChip(surgery.status, surgery.isMissed),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Patient: ${surgery.patientName ?? surgery.patientId}'
                          '${surgery.patientNumber != null ? " (${surgery.patientNumber})" : ""}',
                          style: AppTypography.bodySm.copyWith(
                            color: AppColors.onSurfaceVariant,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),

              // Tab Bar Navigation (Only shown when Billing & Insurance are accessible)
              if (surgery.canAccessBilling) ...[
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.onSurfaceVariant,
                  indicatorColor: AppColors.primary,
                  indicatorWeight: 3,
                  tabs: const [
                    Tab(
                      icon: Icon(Icons.medical_services_outlined, size: 18),
                      text: 'Clinical Details',
                    ),
                    Tab(
                      icon: Icon(Icons.receipt_long_outlined, size: 18),
                      text: 'Surgery Billing',
                    ),
                    Tab(
                      icon: Icon(Icons.health_and_safety_outlined, size: 18),
                      text: 'Insurance',
                    ),
                    Tab(
                      icon: Icon(Icons.account_balance_wallet_outlined, size: 18),
                      text: 'Balances & History',
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              // Tab Views
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Tab 1: Clinical Details & Progress
                    _buildClinicalDetailsTab(surgery, isAdmin),

                    if (surgery.canAccessBilling) ...[
                      // Tab 2: Surgery Billing
                      _buildBillingTab(surgery),

                      // Tab 3: Insurance (Eye Surgery Only)
                      _buildInsuranceTab(surgery),

                      // Tab 4: Balances & Payment History
                      _buildBalancesAndHistoryTab(surgery),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // TAB 1: CLINICAL DETAILS & PROGRESS
  // =========================================================================

  Widget _buildClinicalDetailsTab(EyeSurgeryModel surgery, bool isAdmin) {
    final itemsAsync = ref.watch(eyeSurgeryItemsProvider(surgery.id));
    final completedChecklist = EyeSurgeryModel.checklistItems.keys
        .where((k) => surgery.preOpChecklist[k] == true)
        .length;

    final dateFormatted = DateFormat('dd MMM yyyy').format(surgery.surgeryDate);
    final preOpFormatted = DateFormat('dd MMM yyyy').format(surgery.preOpDate);
    final timeFormatted = surgery.surgeryTime;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Discharged Surgery Actions: Exactly Two Actions (Section 5)
          if (surgery.isDischarged) ...[
            _buildSectionCard(
              title: 'DISCHARGED SURGERY ACTIONS',
              icon: Icons.task_alt,
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  FilledButton.icon(
                    onPressed: () => _openScheduleFollowUp(surgery),
                    icon: const Icon(Icons.calendar_month_outlined, size: 16),
                    label: Text(surgery.followUpAppointmentId == null
                        ? 'Schedule Follow-up Appointment'
                        : 'Follow-up Scheduled · Edit'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _tabController.animateTo(1),
                    icon: const Icon(Icons.receipt_long_outlined, size: 16),
                    label: const Text('Billing & Insurance'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          // Schedule & Clinical Overview
          _buildSectionCard(
            title: 'SCHEDULE & CLINICAL OVERVIEW',
            icon: Icons.calendar_today_outlined,
            child: Column(
              children: [
                _buildInfoRow(
                  label: 'Surgery Date & Time',
                  value: '$dateFormatted${timeFormatted != null ? " at $timeFormatted" : ""}',
                  icon: Icons.schedule_outlined,
                ),
                _buildInfoRow(
                  label: 'Eye Side',
                  value: '${surgery.eyeSide.toUpperCase()} EYE',
                  icon: Icons.remove_red_eye_outlined,
                ),
                _buildInfoRow(
                  label: 'Assigned Staff',
                  value: surgery.assignedStaffName ?? 'Unassigned',
                  icon: Icons.person_outline,
                  trailing: (isAdmin && !surgery.isDischarged)
                      ? TextButton.icon(
                          onPressed: () async {
                            await showAssignEyeSurgeryStaffDialog(
                                context, ref, surgery);
                          },
                          icon: const Icon(Icons.person_add_alt_1, size: 14),
                          label: Text(
                            surgery.assignedStaffName == null
                                ? 'Assign Staff'
                                : 'Change',
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                          ),
                        )
                      : null,
                ),
                _buildInfoRow(
                  label: 'Pre-operative Date',
                  value: preOpFormatted,
                  icon: Icons.event_available_outlined,
                ),
                if (surgery.dischargedAt != null)
                  _buildInfoRow(
                    label: 'Discharged On',
                    value: DateFormat('dd MMM yyyy, h:mm a')
                        .format(surgery.dischargedAt!.toLocal()),
                    icon: Icons.exit_to_app_outlined,
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Pre-op Checklist Card (Hidden when surgery is Discharged)
          if (!surgery.isDischarged) ...[
            _buildSectionCard(
              title:
                  'PRE-OP CHECKLIST ($completedChecklist / ${EyeSurgeryModel.checklistItems.length})',
              icon: Icons.checklist_outlined,
              trailingBadge: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: completedChecklist == EyeSurgeryModel.checklistItems.length
                      ? _successColor.withValues(alpha: 0.15)
                      : Colors.amber.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  completedChecklist == EyeSurgeryModel.checklistItems.length
                      ? 'ALL VERIFIED'
                      : '$completedChecklist PENDING',
                  style: AppTypography.labelCaps.copyWith(
                    color: completedChecklist == EyeSurgeryModel.checklistItems.length
                        ? _successColor
                        : Colors.amber.shade900,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
              child: Column(
                children: EyeSurgeryModel.checklistItems.entries.map((entry) {
                  final isDone = surgery.preOpChecklist[entry.key] == true;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          isDone
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          size: 18,
                          color: isDone ? _successColor : AppColors.outlineVariant,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            entry.value,
                            style: AppTypography.bodySm.copyWith(
                              color: isDone
                                  ? AppColors.onSurface
                                  : AppColors.onSurfaceVariant,
                              fontWeight:
                                  isDone ? FontWeight.w500 : FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          // Clinical Details (IOL and Remarks)
          if ((surgery.iolDetails != null &&
                  surgery.iolDetails!.trim().isNotEmpty) ||
              (surgery.remarks != null &&
                  surgery.remarks!.trim().isNotEmpty)) ...[
            _buildSectionCard(
              title: 'CLINICAL DETAILS & NOTES',
              icon: Icons.notes_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (surgery.iolDetails != null &&
                      surgery.iolDetails!.trim().isNotEmpty) ...[
                    Text(
                      'IOL Details (Lens Model & Power)',
                      style: AppTypography.bodySm.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(surgery.iolDetails!, style: AppTypography.bodyMd),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  if (surgery.remarks != null &&
                      surgery.remarks!.trim().isNotEmpty) ...[
                    Text(
                      'Clinical Remarks / Post-Op Notes',
                      style: AppTypography.bodySm.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(surgery.remarks!, style: AppTypography.bodyMd),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          // Follow-up Appointment Linkage
          if (surgery.followUpAppointmentId != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: _successColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: _successColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline,
                      color: _successColor, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Follow-up appointment scheduled (Appointment #${surgery.followUpAppointmentId!.length > 8 ? surgery.followUpAppointmentId!.substring(0, 8) : surgery.followUpAppointmentId})',
                      style: AppTypography.bodySm.copyWith(
                        color: _successColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          // Recorded Surgery Inventory Items
          _buildSectionCard(
            title: 'SURGERY INVENTORY ITEMS',
            icon: Icons.inventory_2_outlined,
            child: itemsAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (e, _) => Text(
                'Unable to load surgery inventory items: $e',
                style: AppTypography.bodySm.copyWith(color: AppColors.error),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: Text(
                      'No inventory items recorded or consumed for this surgery.',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(
                    height: 1,
                    color: AppColors.outlineVariant,
                  ),
                  itemBuilder: (context, i) {
                    final item = items[i];
                    final isConsumed = item.consumedAt != null;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.xs),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.inventoryItemName,
                                  style: AppTypography.bodyMd.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  'Required: ${item.requiredQuantity} ${item.unit}',
                                  style: AppTypography.bodySm.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isConsumed
                                  ? _successColor.withValues(alpha: 0.1)
                                  : Colors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(
                                  AppSpacing.radiusSm),
                            ),
                            child: Text(
                              isConsumed ? 'CONSUMED' : 'ALLOCATED',
                              style: AppTypography.labelCaps.copyWith(
                                color: isConsumed
                                    ? _successColor
                                    : Colors.blue.shade800,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // TAB 2: SURGERY BILLING (Section 2)
  // =========================================================================

  Widget _buildBillingTab(EyeSurgeryModel surgery) {
    final invoiceAsync = ref.watch(eyeSurgeryInvoiceProvider(surgery.id));
    final summary = ref.watch(eyeSurgeryFinancialSummaryProvider(surgery.id));

    return invoiceAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (e, _) => SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Unable to load invoice',
                style: AppTypography.headlineMd.copyWith(fontSize: 16),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '$e',
                textAlign: TextAlign.center,
                style: AppTypography.bodySm.copyWith(color: AppColors.error),
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: () =>
                    ref.invalidate(eyeSurgeryInvoiceProvider(surgery.id)),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (invoice) {
        if (invoice == null) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.receipt_long_outlined,
                        size: 48, color: AppColors.outline),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'No Invoice Linked to This Surgery',
                      style: AppTypography.headlineMd.copyWith(fontSize: 18),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Create an invoice for this surgery. Total charges, previous balances, and payment allocations can be configured seamlessly.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton.icon(
                      onPressed: () => _openCreateSurgeryInvoice(surgery),
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                      label: const Text('Create Surgery Invoice'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // Invoice exists: Display detailed surgery invoice & patient payment actions
        final isFullyPaid = invoice.isPaid;
        final isPartial = invoice.isPartiallyPaid;
        final statusColor = isFullyPaid
            ? _successColor
            : isPartial
                ? Colors.amber.shade800
                : AppColors.error;

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Invoice Header Banner
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Invoice #${invoice.invoiceNumber}',
                                style: AppTypography.headlineMd.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  invoice.paymentStatus.toUpperCase().replaceAll('_', ' '),
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Billed on ${DateFormat('dd MMM yyyy, h:mm a').format(invoice.createdAt)}',
                            style: AppTypography.bodySm.copyWith(
                              color: AppColors.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isFullyPaid)
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                        ),
                        onPressed: () => _openRecordPatientPayment(invoice),
                        icon: const Icon(Icons.add_card, size: 16),
                        label: const Text('Record Payment'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Line Items Card
              _buildSectionCard(
                title: 'INVOICE LINE ITEMS',
                icon: Icons.list_alt,
                child: Column(
                  children: [
                    ...invoice.items.map((item) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.serviceName,
                                style: const TextStyle(fontWeight: FontWeight.w500),
                              ),
                            ),
                            Text('${item.quantity} × ₹${item.unitPrice.toStringAsFixed(2)}'),
                            const SizedBox(width: AppSpacing.md),
                            Text(
                              '₹${item.totalAmount.toStringAsFixed(2)}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      );
                    }),
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Subtotal:'),
                        Text('₹${invoice.subtotal.toStringAsFixed(2)}'),
                      ],
                    ),
                    if (invoice.discount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Discount:',
                                style: TextStyle(color: AppColors.error)),
                            Text('-₹${invoice.discount.toStringAsFixed(2)}',
                                style: const TextStyle(color: AppColors.error)),
                          ],
                        ),
                      ),
                    const Divider(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Surgery Bill:',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('₹${invoice.totalAmount.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Summary Breakdown
              _buildSectionCard(
                title: 'PAYMENT STATUS & PATIENT BALANCE',
                icon: Icons.account_balance,
                child: Column(
                  children: [
                    _buildRow(
                        'Total Surgery Charges', '₹${invoice.totalAmount.toStringAsFixed(2)}'),
                    _buildRow("Patient's Payable Share",
                        '₹${summary.patientPayableShare.toStringAsFixed(2)}',
                        isBold: true),
                    _buildRow('Patient Payments Received',
                        '₹${invoice.amountPaid.toStringAsFixed(2)}',
                        color: _successColor),
                    _buildRow(
                      'Remaining Patient Balance',
                      '₹${summary.remainingPatientBalance.toStringAsFixed(2)}',
                      color: summary.remainingPatientBalance > 0
                          ? AppColors.error
                          : _successColor,
                      isBold: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // =========================================================================
  // TAB 3: INSURANCE (Eye Surgery Only - Section 3, 4, 5)
  // =========================================================================

  Widget _buildInsuranceTab(EyeSurgeryModel surgery) {
    final insuranceAsync = ref.watch(eyeSurgeryInsuranceProvider(surgery.id));
    final summary = ref.watch(eyeSurgeryFinancialSummaryProvider(surgery.id));

    return insuranceAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (e, _) => SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Unable to load insurance',
                style: AppTypography.headlineMd.copyWith(fontSize: 16),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '$e',
                textAlign: TextAlign.center,
                style: AppTypography.bodySm.copyWith(color: AppColors.error),
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: () =>
                    ref.invalidate(eyeSurgeryInsuranceProvider(surgery.id)),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (insurance) {
        if (insurance == null) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.health_and_safety_outlined,
                        size: 48, color: AppColors.outline),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'No Insurance Configured for this Eye Surgery',
                      style: AppTypography.headlineMd.copyWith(fontSize: 18),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Configure Cashless (clinic direct) or Reimbursement (patient claimed) arrangements exclusively for this eye surgery.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton.icon(
                      onPressed: () => _openConfigureInsurance(surgery, null),
                      icon: const Icon(Icons.shield_outlined, size: 18),
                      label: const Text('Configure Surgery Insurance'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final isCashless = insurance.isCashless;
        final statusColor = insurance.isApproved
            ? _successColor
            : insurance.isRejected
                ? AppColors.error
                : Colors.blue.shade700;

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Arrangement Header Card
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: isCashless
                      ? Colors.teal.shade50
                      : Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(
                    color: isCashless
                        ? Colors.teal.shade300
                        : Colors.indigo.shade300,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isCashless
                          ? Icons.account_balance_wallet_outlined
                          : Icons.receipt_long_outlined,
                      color: isCashless
                          ? Colors.teal.shade800
                          : Colors.indigo.shade800,
                      size: 28,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '${insurance.arrangement.label.toUpperCase()} ARRANGEMENT',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isCashless
                                      ? Colors.teal.shade900
                                      : Colors.indigo.shade900,
                                  fontSize: 13,
                                  letterSpacing: 1.1,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  insurance.claimStatus.label,
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isCashless
                                ? 'Insurance pays clinic directly · Patient pays remaining balance'
                                : 'Patient pays clinic first · Patient claims reimbursement personally',
                            style: TextStyle(
                              fontSize: 12,
                              color: isCashless
                                  ? Colors.teal.shade800
                                  : Colors.indigo.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Edit Insurance Configuration',
                      onPressed: () =>
                          _openConfigureInsurance(surgery, insurance),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Policy Details Card
              _buildSectionCard(
                title: 'POLICY & CLAIM INFORMATION',
                icon: Icons.badge_outlined,
                child: Column(
                  children: [
                    _buildRow('Insurance Provider / TPA',
                        insurance.insuranceProvider,
                        isBold: true),
                    if (insurance.policyNumber != null)
                      _buildRow('Policy Number', insurance.policyNumber!),
                    if (insurance.memberId != null)
                      _buildRow('Member / Patient ID', insurance.memberId!),
                    _buildRow(
                      'Claim / Reference #',
                      insurance.claimNumber?.isNotEmpty == true
                          ? insurance.claimNumber!
                          : 'Not assigned yet',
                    ),
                    if (insurance.claimSubmissionDate != null)
                      _buildRow(
                        'Claim Submission Date',
                        DateFormat('dd MMM yyyy')
                            .format(insurance.claimSubmissionDate!),
                      ),
                    if (insurance.coverageDetails != null &&
                        insurance.coverageDetails!.trim().isNotEmpty)
                      _buildRow(
                          'Coverage Details', insurance.coverageDetails!),
                    if (insurance.rejectionReason != null &&
                        insurance.rejectionReason!.trim().isNotEmpty)
                      _buildRow(
                        'Rejection Reason',
                        insurance.rejectionReason!,
                        color: AppColors.error,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Coverage & Insurer Balance Card (Section 4 rules)
              _buildSectionCard(
                title: 'COVERAGE & INSURER BALANCES',
                icon: Icons.account_balance_wallet,
                child: Column(
                  children: [
                    _buildRow('Estimated Eligible Coverage',
                        '₹${insurance.estimatedAmount.toStringAsFixed(2)}'),
                    _buildRow(
                      'Approved Insurance Coverage',
                      '₹${insurance.approvedAmount.toStringAsFixed(2)}',
                      isBold: true,
                      color: insurance.isApproved ? _successColor : null,
                    ),
                    _buildRow('Insurance Received by Clinic',
                        '₹${summary.insuranceAmountReceivedByClinic.toStringAsFixed(2)}',
                        color: _successColor),
                    if (isCashless)
                      _buildRow(
                        'Pending from Insurer (Insurer Outstanding)',
                        '₹${summary.insuranceAmountPending.toStringAsFixed(2)}',
                        color: summary.insuranceAmountPending > 0
                            ? Colors.orange.shade800
                            : _successColor,
                        isBold: true,
                      )
                    else
                      _buildRow(
                        'Reimbursement Received by Patient',
                        '₹${summary.patientReimbursementReceived.toStringAsFixed(2)}',
                        color: Colors.indigo.shade800,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Actions Row
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => _openUpdateClaimDialog(surgery, insurance),
                    icon: const Icon(Icons.rule_outlined, size: 16),
                    label: const Text('Update Claim Decision'),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: AppColors.primary,
                    ),
                    onPressed: () =>
                        _openRecordInsurancePayment(surgery, insurance),
                    icon: const Icon(Icons.add_card, size: 16),
                    label: const Text('Record Insurance Payment'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // =========================================================================
  // TAB 4: BALANCES & PAYMENT HISTORY (Section 4 & 5)
  // =========================================================================

  Widget _buildBalancesAndHistoryTab(EyeSurgeryModel surgery) {
    final invoiceAsync = ref.watch(eyeSurgeryInvoiceProvider(surgery.id));
    final insuranceAsync = ref.watch(eyeSurgeryInsuranceProvider(surgery.id));
    final summary = ref.watch(eyeSurgeryFinancialSummaryProvider(surgery.id));

    final invoice = invoiceAsync.valueOrNull;
    final insurance = insuranceAsync.valueOrNull;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Authoritative 8-Amount Dashboard (Requirement Section 4)
          Text(
            'AUTHORITATIVE FINANCIAL BREAKDOWN',
            style: AppTypography.labelCaps.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: Column(
              children: [
                _buildNumberedRow(1, 'Total Surgery Bill',
                    '₹${summary.totalSurgeryBill.toStringAsFixed(2)}',
                    isBold: true),
                _buildNumberedRow(2, 'Estimated Insurance Coverage',
                    '₹${summary.estimatedInsuranceCoverage.toStringAsFixed(2)}'),
                _buildNumberedRow(3, 'Approved Insurance Coverage',
                    '₹${summary.approvedInsuranceCoverage.toStringAsFixed(2)}',
                    color: summary.approvedInsuranceCoverage > 0
                        ? _successColor
                        : null),
                _buildNumberedRow(4, 'Insurance Received by Clinic',
                    '₹${summary.insuranceAmountReceivedByClinic.toStringAsFixed(2)}',
                    color: _successColor),
                _buildNumberedRow(
                  5,
                  'Insurance Amount Still Pending (Insurer Outstanding)',
                  '₹${summary.insuranceAmountPending.toStringAsFixed(2)}',
                  color: summary.insuranceAmountPending > 0
                      ? Colors.orange.shade800
                      : _successColor,
                  isBold: true,
                ),
                const Divider(height: 12),
                _buildNumberedRow(6, "Patient's Payable Share",
                    '₹${summary.patientPayableShare.toStringAsFixed(2)}',
                    isBold: true),
                _buildNumberedRow(7, 'Patient Payments Received',
                    '₹${summary.patientPaymentsReceived.toStringAsFixed(2)}',
                    color: _successColor),
                _buildNumberedRow(
                  8,
                  'Remaining Patient Balance',
                  '₹${summary.remainingPatientBalance.toStringAsFixed(2)}',
                  color: summary.remainingPatientBalance > 0
                      ? AppColors.error
                      : _successColor,
                  isBold: true,
                  fontSize: 14,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Audit Trail 1: Patient Payments
          _buildSectionCard(
            title: 'PATIENT PAYMENTS AUDIT TRAIL',
            icon: Icons.person_outline,
            child: (invoice?.payments.isEmpty ?? true)
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      'No patient payments recorded against this invoice yet.',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        fontSize: 12,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: invoice!.payments.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: AppColors.outlineVariant),
                    itemBuilder: (context, i) {
                      final p = invoice.payments[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_outline,
                                color: _successColor, size: 18),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '₹${p.amount.toStringAsFixed(2)} · ${p.paymentMode.toUpperCase()}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                  if (p.paymentReference != null &&
                                      p.paymentReference!.isNotEmpty)
                                    Text('Ref: ${p.paymentReference}',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.onSurfaceVariant)),
                                ],
                              ),
                            ),
                            if (p.paidAt != null)
                              Text(
                                DateFormat('dd MMM yyyy, h:mm a').format(p.paidAt!),
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.onSurfaceVariant),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Audit Trail 2: Insurer Payments
          _buildSectionCard(
            title: 'INSURANCE PAYMENTS AUDIT TRAIL',
            icon: Icons.shield_outlined,
            child: (insurance?.payments.isEmpty ?? true)
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      'No insurance payments recorded yet.',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        fontSize: 12,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: insurance!.payments.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: AppColors.outlineVariant),
                    itemBuilder: (context, i) {
                      final p = insurance.payments[i];
                      final isClinic = p.isClinicDestination;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Icon(
                              isClinic
                                  ? Icons.local_hospital_outlined
                                  : Icons.person_pin_outlined,
                              color: isClinic
                                  ? _successColor
                                  : Colors.indigo.shade700,
                              size: 18,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '₹${p.amount.toStringAsFixed(2)} · ${p.isClinicDestination ? "Clinic Receipt" : "Direct Patient Reimbursement"}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    'Mode: ${p.paymentMode.toUpperCase()}${p.paymentReference != null ? " · Ref: ${p.paymentReference}" : ""}',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              DateFormat('dd MMM yyyy').format(p.paymentDate),
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // ACTIONS & DIALOGS
  // =========================================================================

  Future<void> _openCreateSurgeryInvoice(EyeSurgeryModel surgery) async {
    PatientModel? patient;
    try {
      final repo = ref.read(patientRepositoryProvider);
      patient = await repo.getPatient(surgery.patientId);
    } catch (_) {
      patient = PatientModel(
        id: surgery.patientId,
        patientNumber: surgery.patientNumber ?? 'SURG-PAT',
        name: surgery.patientName ?? 'Surgery Patient',
        department: 'eye',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }

    final procedureItem = BillingItemModel(
      serviceName:
          '${surgery.displaySurgeryType} (${surgery.eyeSide.toUpperCase()} Eye)',
      quantity: 1,
      unitPrice: 0.0,
      isCustom: true,
    );

    if (!mounted) return;
    final created = await Navigator.of(context).push<BillingInvoiceModel>(
      MaterialPageRoute(
        builder: (_) => CreateInvoiceScreen(
          initialPatient: patient,
          initialDepartment: 'eye',
          initialEyeSurgeryId: surgery.id,
          initialItems: [procedureItem],
        ),
      ),
    );

    ref.invalidate(eyeSurgeryInvoiceProvider(surgery.id));
    ref.invalidate(eyeSurgeryFinancialSummaryProvider(surgery.id));
    if (created != null && _tabController.length > 1) {
      _tabController.animateTo(1);
    }
  }

  Future<void> _openScheduleFollowUp(EyeSurgeryModel surgery) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AppointmentFormDialog(
        initialPatientId: surgery.patientId,
        initialPatientName: surgery.patientName,
        initialAppointmentType: 'follow_up',
      ),
    );
    if (result == true) {
      try {
        final appointments = await ref
            .read(appointmentRepositoryProvider)
            .fetchPatientAppointments(
              patientId: surgery.patientId,
              department: 'eye',
            );
        final latest = appointments.isNotEmpty ? appointments.first : null;
        if (latest != null) {
          await ref
              .read(eyeSurgeryListProvider.notifier)
              .linkFollowUpAppointment(surgery.id, latest.id);
        }
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Follow-up appointment scheduled successfully.'),
          ),
        );
      }
    }
  }

  Future<void> _openRecordPatientPayment(BillingInvoiceModel invoice) async {
    final amountController = TextEditingController(
      text: invoice.remainingAmount > 0
          ? invoice.remainingAmount.toStringAsFixed(2)
          : '',
    );
    final refController = TextEditingController();
    String paymentMode = 'cash';

    final recorded = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Record Patient Payment'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Invoice #${invoice.invoiceNumber} · Outstanding: ₹${invoice.remainingAmount.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Amount (₹) *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.currency_rupee),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: paymentMode,
                  decoration: const InputDecoration(
                    labelText: 'Payment Mode',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Cash')),
                    DropdownMenuItem(value: 'upi', child: Text('UPI / QR')),
                    DropdownMenuItem(
                        value: 'bank_transfer', child: Text('Bank Transfer')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => paymentMode = val);
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: refController,
                  decoration: const InputDecoration(
                    labelText: 'Payment Reference (Optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final amt = double.tryParse(amountController.text.trim());
                  if (amt == null || amt <= 0) return;
                  try {
                    await ref.read(billingRepositoryProvider).recordPayment(
                          billingId: invoice.id,
                          amount: amt,
                          paymentMode: paymentMode,
                          paymentReference: refController.text.trim(),
                        );
                    if (dialogCtx.mounted) Navigator.pop(dialogCtx, true);
                  } catch (e) {
                    if (dialogCtx.mounted) {
                      ScaffoldMessenger.of(dialogCtx).showSnackBar(
                        SnackBar(content: Text('Failed: $e')),
                      );
                    }
                  }
                },
                child: const Text('Save Payment'),
              ),
            ],
          );
        },
      ),
    );

    if (recorded == true) {
      ref.invalidate(eyeSurgeryInvoiceProvider(widget.surgery.id));
    }
  }

  Future<void> _openConfigureInsurance(
      EyeSurgeryModel surgery, EyeSurgeryInsuranceModel? existing) async {
    final saved = await showDialog<EyeSurgeryInsuranceModel>(
      context: context,
      builder: (_) => EyeSurgeryInsuranceFormDialog(
        surgery: surgery,
        existingInsurance: existing,
      ),
    );

    if (saved != null) {
      ref.invalidate(eyeSurgeryInsuranceProvider(surgery.id));
      _tabController.animateTo(2);
    }
  }

  Future<void> _openUpdateClaimDialog(
      EyeSurgeryModel surgery, EyeSurgeryInsuranceModel insurance) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => EyeSurgeryUpdateClaimDialog(
        surgery: surgery,
        insurance: insurance,
      ),
    );

    if (updated == true) {
      ref.invalidate(eyeSurgeryInsuranceProvider(surgery.id));
    }
  }

  Future<void> _openRecordInsurancePayment(
      EyeSurgeryModel surgery, EyeSurgeryInsuranceModel insurance) async {
    final recorded = await showDialog<bool>(
      context: context,
      builder: (_) => EyeSurgeryRecordInsurancePaymentDialog(
        surgery: surgery,
        insurance: insurance,
      ),
    );

    if (recorded == true) {
      ref.invalidate(eyeSurgeryInsuranceProvider(surgery.id));
    }
  }

  // =========================================================================
  // HELPER WIDGETS
  // =========================================================================

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Widget child,
    Widget? trailingBadge,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.primary),
              const SizedBox(width: AppSpacing.xs),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                  color: AppColors.primary,
                ),
              ),
              if (trailingBadge != null) ...[
                const Spacer(),
                trailingBadge,
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required String label,
    required String value,
    required IconData icon,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: AppTypography.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySm.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.xs),
            trailing,
          ],
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value,
      {Color? color, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.onSurfaceVariant)),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: color ?? AppColors.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberedRow(int number, String label, String value,
      {Color? color, bool isBold = false, double fontSize = 12}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: fontSize,
                color: isBold ? AppColors.onSurface : AppColors.onSurfaceVariant,
                fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: color ?? AppColors.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status, bool isMissed) {
    Color bg = AppColors.primaryContainer;
    Color fg = AppColors.primary;
    String label = status.toUpperCase().replaceAll('_', ' ');

    if (isMissed) {
      bg = Colors.red.shade100;
      fg = Colors.red.shade900;
      label = 'MISSED';
    } else if (status == 'discharged') {
      bg = _successColor.withValues(alpha: 0.15);
      fg = _successColor;
    } else if (status == 'in_surgery') {
      bg = Colors.purple.shade100;
      fg = Colors.purple.shade900;
    } else if (status == 'billing') {
      bg = Colors.amber.shade100;
      fg = Colors.amber.shade900;
      label = 'BILLING';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
