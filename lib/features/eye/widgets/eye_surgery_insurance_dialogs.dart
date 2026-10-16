import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../models/eye_surgery_insurance_model.dart';
import '../models/eye_surgery_model.dart';
import '../providers/eye_surgery_provider.dart';

/// Modal dialog for configuring or editing Eye Surgery Insurance
class EyeSurgeryInsuranceFormDialog extends ConsumerStatefulWidget {
  final EyeSurgeryModel surgery;
  final EyeSurgeryInsuranceModel? existingInsurance;

  const EyeSurgeryInsuranceFormDialog({
    super.key,
    required this.surgery,
    this.existingInsurance,
  });

  @override
  ConsumerState<EyeSurgeryInsuranceFormDialog> createState() =>
      _EyeSurgeryInsuranceFormDialogState();
}

class _EyeSurgeryInsuranceFormDialogState
    extends ConsumerState<EyeSurgeryInsuranceFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _providerController;
  late TextEditingController _policyNumberController;
  late TextEditingController _memberIdController;
  late TextEditingController _claimNumberController;
  late TextEditingController _coverageDetailsController;
  late TextEditingController _estimatedAmountController;
  late TextEditingController _notesController;

  late EyeSurgeryInsuranceArrangement _arrangement;
  DateTime? _claimSubmissionDate;
  bool _isSaving = false;
  String? _errorMessage;

  static const _commonProviders = [
    'Star Health & Allied Insurance',
    'Care Health Insurance',
    'HDFC ERGO Health',
    'ICICI Lombard General Insurance',
    'Bajaj Allianz General Insurance',
    'New India Assurance',
    'National Insurance Company',
    'United India Insurance',
    'Oriental Insurance Company',
    'Max Bupa / Niva Bupa',
    'Other / Private TPA',
  ];

  @override
  void initState() {
    super.initState();
    final existing = widget.existingInsurance;
    _providerController =
        TextEditingController(text: existing?.insuranceProvider ?? '');
    _policyNumberController =
        TextEditingController(text: existing?.policyNumber ?? '');
    _memberIdController = TextEditingController(text: existing?.memberId ?? '');
    _claimNumberController =
        TextEditingController(text: existing?.claimNumber ?? '');
    _coverageDetailsController =
        TextEditingController(text: existing?.coverageDetails ?? '');
    _estimatedAmountController = TextEditingController(
      text: existing != null && existing.estimatedAmount > 0
          ? existing.estimatedAmount.toStringAsFixed(2)
          : '',
    );
    _notesController = TextEditingController(text: existing?.notes ?? '');
    _arrangement = existing?.arrangement ?? EyeSurgeryInsuranceArrangement.cashless;
    _claimSubmissionDate = existing?.claimSubmissionDate;
  }

  @override
  void dispose() {
    _providerController.dispose();
    _policyNumberController.dispose();
    _memberIdController.dispose();
    _claimNumberController.dispose();
    _coverageDetailsController.dispose();
    _estimatedAmountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final estimated =
          double.tryParse(_estimatedAmountController.text.trim()) ?? 0.0;

      final insuranceToSave = EyeSurgeryInsuranceModel(
        id: widget.existingInsurance?.id ?? '',
        eyeSurgeryId: widget.surgery.id,
        patientId: widget.surgery.patientId,
        insuranceProvider: _providerController.text.trim(),
        arrangement: _arrangement,
        policyNumber: _policyNumberController.text.trim().isNotEmpty
            ? _policyNumberController.text.trim()
            : null,
        memberId: _memberIdController.text.trim().isNotEmpty
            ? _memberIdController.text.trim()
            : null,
        claimNumber: _claimNumberController.text.trim().isNotEmpty
            ? _claimNumberController.text.trim()
            : null,
        coverageDetails: _coverageDetailsController.text.trim().isNotEmpty
            ? _coverageDetailsController.text.trim()
            : null,
        estimatedAmount: estimated,
        approvedAmount: widget.existingInsurance?.approvedAmount ?? 0.0,
        amountReceived: widget.existingInsurance?.amountReceived ?? 0.0,
        claimSubmissionDate: _claimSubmissionDate,
        claimStatus: widget.existingInsurance?.claimStatus ??
            EyeSurgeryClaimStatus.notSubmitted,
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
        rejectionReason: widget.existingInsurance?.rejectionReason,
        createdAt: widget.existingInsurance?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final saved = await ref
          .read(eyeSurgeryInsuranceProvider(widget.surgery.id).notifier)
          .saveInsurance(insuranceToSave);

      if (mounted) {
        Navigator.of(context).pop(saved);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      ),
                      child: const Icon(
                        Icons.health_and_safety_outlined,
                        color: AppColors.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.existingInsurance == null
                                ? 'Add Surgery Insurance'
                                : 'Edit Surgery Insurance',
                            style: AppTypography.headlineMd.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          Text(
                            '${widget.surgery.patientName ?? "Patient"} · ${widget.surgery.displaySurgeryType}',
                            style: AppTypography.bodySm.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Cancel',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.md),

                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.errorContainer,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: AppColors.error, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],

                // Body
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Arrangement Selection (Cashless vs Reimbursement)
                        Text(
                          'Insurance Arrangement *',
                          style: AppTypography.bodySm.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.onSurface,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        SegmentedButton<EyeSurgeryInsuranceArrangement>(
                          segments: const [
                            ButtonSegment(
                              value: EyeSurgeryInsuranceArrangement.cashless,
                              label: Text('Cashless (Clinic Direct)'),
                              icon: Icon(Icons.account_balance_wallet_outlined,
                                  size: 16),
                            ),
                            ButtonSegment(
                              value: EyeSurgeryInsuranceArrangement.reimbursement,
                              label: Text('Reimbursement (Patient Claims)'),
                              icon: Icon(Icons.receipt_long_outlined, size: 16),
                            ),
                          ],
                          selected: {_arrangement},
                          onSelectionChanged: (val) {
                            setState(() => _arrangement = val.first);
                          },
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          _arrangement == EyeSurgeryInsuranceArrangement.cashless
                              ? 'Cashless: Insurance company pays clinic directly for approved amount. Patient pays remaining share.'
                              : 'Reimbursement: Patient pays clinic bill in full, then claims reimbursement from insurer personally.',
                          style: AppTypography.bodySm.copyWith(
                            fontSize: 11,
                            color: AppColors.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),

                        // Insurance Provider
                        Autocomplete<String>(
                          initialValue: TextEditingValue(
                              text: _providerController.text),
                          optionsBuilder: (textEditingValue) {
                            if (textEditingValue.text.isEmpty) {
                              return _commonProviders;
                            }
                            return _commonProviders.where((p) => p
                                .toLowerCase()
                                .contains(textEditingValue.text.toLowerCase()));
                          },
                          onSelected: (selection) {
                            _providerController.text = selection;
                          },
                          fieldViewBuilder:
                              (context, controller, focusNode, onFieldSubmitted) {
                            if (_providerController.text.isNotEmpty &&
                                controller.text.isEmpty) {
                              controller.text = _providerController.text;
                            }
                            controller.addListener(() {
                              _providerController.text = controller.text;
                            });
                            return TextFormField(
                              controller: controller,
                              focusNode: focusNode,
                              decoration: const InputDecoration(
                                labelText: 'Insurance Provider / TPA *',
                                hintText: 'e.g. Star Health, Care Health',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.business_outlined),
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return 'Insurance company / provider is required';
                                }
                                return null;
                              },
                            );
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),

                        // Policy & Member IDs
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _policyNumberController,
                                decoration: const InputDecoration(
                                  labelText: 'Policy Number',
                                  hintText: 'e.g. POL-987654',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.badge_outlined),
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: TextFormField(
                                controller: _memberIdController,
                                decoration: const InputDecoration(
                                  labelText: 'Member / Patient ID',
                                  hintText: 'e.g. MEM-12345',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.perm_identity),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),

                        // Claim Number & Submission Date
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _claimNumberController,
                                decoration: const InputDecoration(
                                  labelText: 'Claim / Reference #',
                                  hintText: 'Optional until available',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.confirmation_number_outlined),
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 16, horizontal: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(AppSpacing.radiusSm),
                                  ),
                                ),
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _claimSubmissionDate ??
                                        DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now()
                                        .add(const Duration(days: 365)),
                                  );
                                  if (picked != null) {
                                    setState(
                                        () => _claimSubmissionDate = picked);
                                  }
                                },
                                icon: const Icon(Icons.calendar_today_outlined,
                                    size: 18),
                                label: Text(
                                  _claimSubmissionDate == null
                                      ? 'Submission Date'
                                      : DateFormat('dd MMM yyyy')
                                          .format(_claimSubmissionDate!),
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),

                        // Estimated Eligible Coverage Amount
                        TextFormField(
                          controller: _estimatedAmountController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Estimated Eligible Coverage (₹)',
                            hintText: 'e.g. 35000',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.currency_rupee),
                          ),
                          validator: (val) {
                            if (val != null && val.trim().isNotEmpty) {
                              final d = double.tryParse(val.trim());
                              if (d == null || d < 0) {
                                return 'Enter a valid non-negative amount';
                              }
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),

                        // Coverage details & Notes
                        TextFormField(
                          controller: _coverageDetailsController,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Coverage & Policy Details',
                            hintText: 'e.g. Room rent limit ₹5000/day, IOL covered up to ₹25000',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.info_outline),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),

                        TextFormField(
                          controller: _notesController,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Internal Insurance Notes',
                            hintText: 'e.g. Documents emailed to TPA; approval expected in 4 hours',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.notes_outlined),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    FilledButton.icon(
                      onPressed: _isSaving ? null : _submit,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_outlined, size: 18),
                      label: Text(_isSaving ? 'Saving...' : 'Save Insurance'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Modal dialog for updating claim status (Approved, Partially Approved, Rejected, etc.)
class EyeSurgeryUpdateClaimDialog extends ConsumerStatefulWidget {
  final EyeSurgeryModel surgery;
  final EyeSurgeryInsuranceModel insurance;

  const EyeSurgeryUpdateClaimDialog({
    super.key,
    required this.surgery,
    required this.insurance,
  });

  @override
  ConsumerState<EyeSurgeryUpdateClaimDialog> createState() =>
      _EyeSurgeryUpdateClaimDialogState();
}

class _EyeSurgeryUpdateClaimDialogState
    extends ConsumerState<EyeSurgeryUpdateClaimDialog> {
  late EyeSurgeryClaimStatus _status;
  late TextEditingController _approvedAmountController;
  late TextEditingController _claimNumberController;
  late TextEditingController _rejectionReasonController;
  DateTime? _submissionDate;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _status = widget.insurance.claimStatus;
    _approvedAmountController = TextEditingController(
      text: widget.insurance.approvedAmount > 0
          ? widget.insurance.approvedAmount.toStringAsFixed(2)
          : widget.insurance.estimatedAmount > 0
              ? widget.insurance.estimatedAmount.toStringAsFixed(2)
              : '',
    );
    _claimNumberController =
        TextEditingController(text: widget.insurance.claimNumber ?? '');
    _rejectionReasonController =
        TextEditingController(text: widget.insurance.rejectionReason ?? '');
    _submissionDate = widget.insurance.claimSubmissionDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _approvedAmountController.dispose();
    _claimNumberController.dispose();
    _rejectionReasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      double? approved;
      if (_status == EyeSurgeryClaimStatus.approved ||
          _status == EyeSurgeryClaimStatus.partiallyApproved) {
        approved = double.tryParse(_approvedAmountController.text.trim());
        if (approved == null || approved < 0) {
          throw 'Please enter a valid approved amount.';
        }
      }

      String? rejectionReason;
      if (_status == EyeSurgeryClaimStatus.rejected) {
        rejectionReason = _rejectionReasonController.text.trim();
        if (rejectionReason.isEmpty) {
          throw 'Please provide a reason for claim rejection.';
        }
      }

      await ref
          .read(eyeSurgeryInsuranceProvider(widget.surgery.id).notifier)
          .updateClaimStatus(
            newStatus: _status,
            approvedAmount: approved,
            rejectionReason: rejectionReason,
            claimNumber: _claimNumberController.text.trim(),
            submissionDate: _submissionDate,
          );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final needsApprovedAmount = _status == EyeSurgeryClaimStatus.approved ||
        _status == EyeSurgeryClaimStatus.partiallyApproved;
    final needsRejectionReason = _status == EyeSurgeryClaimStatus.rejected;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.rule_outlined, color: AppColors.primary),
          const SizedBox(width: AppSpacing.sm),
          const Text('Update Insurance Claim Decision'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.errorContainer,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: AppColors.error, fontSize: 13),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            Text(
              'Select the updated claim status for ${widget.insurance.insuranceProvider}:',
              style: AppTypography.bodySm,
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<EyeSurgeryClaimStatus>(
              initialValue: _status,
              decoration: const InputDecoration(
                labelText: 'Claim Status',
                border: OutlineInputBorder(),
              ),
              items: EyeSurgeryClaimStatus.values.map((s) {
                return DropdownMenuItem(
                  value: s,
                  child: Text(s.label),
                );
              }).toList(),
              onChanged: (newVal) {
                if (newVal != null) setState(() => _status = newVal);
              },
            ),
            const SizedBox(height: AppSpacing.md),

            // Claim Reference Number
            TextField(
              controller: _claimNumberController,
              decoration: const InputDecoration(
                labelText: 'Claim / Reference #',
                hintText: 'Official insurer claim ID',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.tag),
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            if (needsApprovedAmount) ...[
              TextField(
                controller: _approvedAmountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: _status == EyeSurgeryClaimStatus.partiallyApproved
                      ? 'Partially Approved Amount (₹) *'
                      : 'Approved Insurance Amount (₹) *',
                  hintText: 'e.g. 30000',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.currency_rupee),
                  helperText:
                      'Note: Marking approved records coverage, not received payment.',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            if (needsRejectionReason) ...[
              TextField(
                controller: _rejectionReasonController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Rejection Reason *',
                  hintText: 'Specify why the insurer rejected the claim',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.cancel_outlined),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _submit,
          child: Text(_isSaving ? 'Updating...' : 'Update Status'),
        ),
      ],
    );
  }
}

/// Modal dialog for recording an actual insurance payment (or patient reimbursement)
class EyeSurgeryRecordInsurancePaymentDialog extends ConsumerStatefulWidget {
  final EyeSurgeryModel surgery;
  final EyeSurgeryInsuranceModel insurance;

  const EyeSurgeryRecordInsurancePaymentDialog({
    super.key,
    required this.surgery,
    required this.insurance,
  });

  @override
  ConsumerState<EyeSurgeryRecordInsurancePaymentDialog> createState() =>
      _EyeSurgeryRecordInsurancePaymentDialogState();
}

class _EyeSurgeryRecordInsurancePaymentDialogState
    extends ConsumerState<EyeSurgeryRecordInsurancePaymentDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _amountController;
  late TextEditingController _referenceController;
  late TextEditingController _notesController;
  DateTime _paymentDate = DateTime.now();
  String _paymentDestination = 'clinic'; // 'clinic' | 'patient'
  String _paymentMode = 'bank_transfer';
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // For reimbursement, default destination can be 'patient' if insurer pays patient directly
    if (widget.insurance.isReimbursement) {
      _paymentDestination = 'patient';
    } else {
      _paymentDestination = 'clinic';
    }

    final pendingInsurer = (widget.insurance.approvedAmount -
            widget.insurance.totalClinicPaymentsReceived)
        .clamp(0.0, double.infinity);

    _amountController = TextEditingController(
      text: pendingInsurer > 0 ? pendingInsurer.toStringAsFixed(2) : '',
    );
    _referenceController = TextEditingController();
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final amount = double.parse(_amountController.text.trim());

      final payment = EyeSurgeryInsurancePaymentModel(
        insuranceId: widget.insurance.id,
        eyeSurgeryId: widget.surgery.id,
        amount: amount,
        paymentDate: _paymentDate,
        paymentReference: _referenceController.text.trim().isNotEmpty
            ? _referenceController.text.trim()
            : null,
        paymentDestination: _paymentDestination,
        paymentMode: _paymentMode,
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
      );

      await ref
          .read(eyeSurgeryInsuranceProvider(widget.surgery.id).notifier)
          .recordPayment(payment);

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.payment_outlined, color: AppColors.primary),
          const SizedBox(width: AppSpacing.sm),
          const Text('Record Insurance Payment'),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.errorContainer,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Text(
                    _errorMessage!,
                    style:
                        const TextStyle(color: AppColors.error, fontSize: 13),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],

              // Destination: Paid to Clinic vs Paid to Patient (for reimbursement)
              Text(
                'Payment Destination *',
                style: AppTypography.bodySm
                    .copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'clinic',
                    label: Text('Paid to Clinic'),
                    icon: Icon(Icons.local_hospital_outlined, size: 16),
                  ),
                  ButtonSegment(
                    value: 'patient',
                    label: Text('Paid to Patient (Reimbursement)'),
                    icon: Icon(Icons.person_outline, size: 16),
                  ),
                ],
                selected: {_paymentDestination},
                onSelectionChanged: (val) {
                  setState(() => _paymentDestination = val.first);
                },
              ),
              const SizedBox(height: 4),
              Text(
                _paymentDestination == 'clinic'
                    ? 'Records actual money received by the clinic from the insurer.'
                    : 'Reimbursement paid directly to the patient by the insurer. Does not count as clinic revenue.',
                style: AppTypography.bodySm.copyWith(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Amount
              TextFormField(
                controller: _amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount Received (₹) *',
                  hintText: 'e.g. 20000',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.currency_rupee),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Payment amount is required';
                  }
                  final num = double.tryParse(val.trim());
                  if (num == null || num <= 0) {
                    return 'Amount must be greater than zero';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),

              // Date & Mode
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            vertical: 14, horizontal: 8),
                      ),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _paymentDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setState(() => _paymentDate = picked);
                        }
                      },
                      icon: const Icon(Icons.calendar_today_outlined, size: 16),
                      label: Text(
                        DateFormat('dd MMM yyyy').format(_paymentDate),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _paymentMode,
                      decoration: const InputDecoration(
                        labelText: 'Payment Mode',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 10, vertical: 12),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'bank_transfer',
                            child: Text('Bank Transfer (NEFT/RTGS)')),
                        DropdownMenuItem(
                            value: 'upi', child: Text('UPI / Net Banking')),
                        DropdownMenuItem(
                            value: 'cheque', child: Text('Cheque / DD')),
                        DropdownMenuItem(
                            value: 'other', child: Text('Other / TPA Portal')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _paymentMode = val);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // Reference #
              TextField(
                controller: _referenceController,
                decoration: const InputDecoration(
                  labelText: 'UTR / Transaction / Reference #',
                  hintText: 'e.g. UTR-0987123456',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.receipt_outlined),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Notes
              TextField(
                controller: _notesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Payment Notes',
                  hintText: 'e.g. Deducted TDS of ₹1,000 as per insurer statement',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _submit,
          child: Text(_isSaving ? 'Recording...' : 'Record Payment'),
        ),
      ],
    );
  }
}
