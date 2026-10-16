import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../patients/models/patient_model.dart';
import '../models/billing_invoice_model.dart';
import '../models/billing_item_model.dart';
import '../models/billing_payment_model.dart';
import '../providers/billing_provider.dart';
import '../repositories/billing_repository.dart';
import '../widgets/invoice_line_items_editor.dart';
import '../widgets/invoice_payment_section.dart';
import '../widgets/invoice_success_dialog.dart';
import '../widgets/patient_search_selector.dart';

class CreateInvoiceScreen extends ConsumerStatefulWidget {
  final PatientModel? initialPatient;
  final String? initialDepartment;
  final String? initialEyeSurgeryId;
  final List<BillingItemModel>? initialItems;

  const CreateInvoiceScreen({
    super.key,
    this.initialPatient,
    this.initialDepartment,
    this.initialEyeSurgeryId,
    this.initialItems,
  });

  @override
  ConsumerState<CreateInvoiceScreen> createState() => _CreateInvoiceScreenState();
}

class _CreateInvoiceScreenState extends ConsumerState<CreateInvoiceScreen> {
  late String _department;
  late DateTime _invoiceDate;
  PatientModel? _selectedPatient;

  List<BillingItemModel> _items = [];
  double _discount = 0.0;
  BillingPaymentModel? _payment;
  final TextEditingController _notesController = TextEditingController();

  String? _validationError;

  // Previous Outstanding Balance state
  bool _includePreviousBalance = false;
  List<BillingInvoiceModel> _outstandingInvoices = [];
  bool _isLoadingOutstanding = false;

  @override
  void initState() {
    super.initState();
    _selectedPatient = widget.initialPatient;
    _department = widget.initialDepartment?.toLowerCase() ??
        widget.initialPatient?.department?.toLowerCase() ??
        'eye';
    if (_department != 'eye' && _department != 'dental') {
      _department = 'eye';
    }
    _invoiceDate = DateTime.now();

    // Initial items or empty service item
    if (widget.initialItems != null && widget.initialItems!.isNotEmpty) {
      _items = List<BillingItemModel>.from(widget.initialItems!);
    } else {
      _items = [
        const BillingItemModel(
          serviceName: '',
          quantity: 1,
          unitPrice: 0.0,
        ),
      ];
    }

    if (_selectedPatient != null) {
      _fetchOutstandingBalance(_selectedPatient!.id);
    }
  }

  Future<void> _fetchOutstandingBalance(String? patientId) async {
    if (patientId == null || patientId.trim().isEmpty) {
      setState(() {
        _outstandingInvoices = [];
        _includePreviousBalance = false;
        _isLoadingOutstanding = false;
      });
      return;
    }

    setState(() => _isLoadingOutstanding = true);
    try {
      final repo = ref.read(billingRepositoryProvider);
      final invoices = await repo.fetchPatientOutstandingInvoices(patientId);
      if (mounted) {
        setState(() {
          _outstandingInvoices = invoices;
          _isLoadingOutstanding = false;
          if (invoices.isEmpty) {
            _includePreviousBalance = false;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingOutstanding = false);
      }
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  double get _newChargesSubtotal =>
      _items.fold(0.0, (sum, item) => sum + item.totalAmount);

  double get _outstandingBalance =>
      _outstandingInvoices.fold(0.0, (sum, inv) => sum + inv.remainingAmount);

  double get _previousBalanceIncluded =>
      _includePreviousBalance ? _outstandingBalance : 0.0;

  double get _subtotal => _newChargesSubtotal + _previousBalanceIncluded;

  double get _finalTotal => (_subtotal - _discount).clamp(0.0, double.infinity);

  void _onDepartmentChanged(String newDept) {
    if (_department == newDept) return;
    setState(() {
      _department = newDept;
      if (_selectedPatient?.department?.toLowerCase() != newDept) {
        _selectedPatient = null;
        _outstandingInvoices = [];
        _includePreviousBalance = false;
      }
      // Reset items for new department catalogue
      _items = [
        const BillingItemModel(
          serviceName: '',
          quantity: 1,
          unitPrice: 0.0,
        ),
      ];
      _discount = 0.0;
      _payment = null;
      _validationError = null;
    });
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _invoiceDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _invoiceDate = picked;
      });
    }
  }

  Future<void> _submitInvoice() async {
    setState(() {
      _validationError = null;
    });

    // 1. Patient validation
    if (_selectedPatient == null) {
      setState(() {
        _validationError = 'Please search and select a patient for this invoice.';
      });
      return;
    }

    // 2. Line items validation
    if (_items.isEmpty) {
      setState(() {
        _validationError = 'Please add at least one line item to the invoice.';
      });
      return;
    }

    for (int i = 0; i < _items.length; i++) {
      final item = _items[i];
      if (item.serviceName.trim().isEmpty) {
        setState(() {
          _validationError =
              'Line item #${i + 1} is missing a service name. Please select or enter a service.';
        });
        return;
      }
      if (item.quantity <= 0) {
        setState(() {
          _validationError = 'Quantity for "${item.serviceName}" must be at least 1.';
        });
        return;
      }
      if (item.unitPrice < 0) {
        setState(() {
          _validationError = 'Price for "${item.serviceName}" cannot be negative.';
        });
        return;
      }
    }

    // 3. Discount validation
    if (_discount < 0) {
      setState(() {
        _validationError = 'Discount cannot be negative.';
      });
      return;
    }
    if (_discount > _subtotal) {
      setState(() {
        _validationError =
            'Discount (₹${_discount.toStringAsFixed(2)}) cannot exceed subtotal (₹${_subtotal.toStringAsFixed(2)}).';
      });
      return;
    }

    // 4. Payment validation
    if (_payment != null && _payment!.amount > _finalTotal) {
      setState(() {
        _validationError =
            'Payment amount (₹${_payment!.amount.toStringAsFixed(2)}) cannot exceed final total (₹${_finalTotal.toStringAsFixed(2)}).';
      });
      return;
    }

    final submissionItems = List<BillingItemModel>.from(_items);
    if (_includePreviousBalance && _outstandingBalance > 0) {
      submissionItems.add(
        BillingItemModel(
          serviceName: 'Previous Outstanding Balance',
          quantity: 1,
          unitPrice: _outstandingBalance,
          isCustom: true,
        ),
      );
    }

    try {
      final notifier = ref.read(createInvoiceNotifierProvider.notifier);
      final createdInvoice = await notifier.createInvoice(
        patientId: _selectedPatient!.id,
        department: _department,
        discount: _discount,
        items: submissionItems,
        payment: _payment,
        invoiceDate: _invoiceDate,
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
        eyeSurgeryId: widget.initialEyeSurgeryId,
      );

      if (mounted && createdInvoice != null) {
        // If previous balance was included, consolidate previous invoices atomically
        if (_includePreviousBalance && _outstandingInvoices.isNotEmpty) {
          await ref.read(billingRepositoryProvider).consolidateInvoices(
            previousInvoices: _outstandingInvoices,
            newInvoiceNumber: createdInvoice.invoiceNumber,
            newInvoiceId: createdInvoice.id,
          );
          ref.invalidate(billingInvoicesProvider);
        }

        final enrichedInvoice = createdInvoice.copyWith(
          items: submissionItems,
          patientName: _selectedPatient?.name,
          patientNumber: _selectedPatient?.patientNumber,
          patientMobile: _selectedPatient?.mobile,
        );

        if (!mounted) return;

        // Show success modal
        await showDialog<BillingInvoiceModel>(
          context: context,
          barrierDismissible: false,
          builder: (_) => InvoiceSuccessDialog(
            invoice: enrichedInvoice,
            onCreateAnother: () {
              setState(() {
                _items = [
                  const BillingItemModel(
                    serviceName: '',
                    quantity: 1,
                    unitPrice: 0.0,
                  ),
                ];
                _discount = 0.0;
                _payment = null;
                _notesController.clear();
                _selectedPatient = null;
                _outstandingInvoices = [];
                _includePreviousBalance = false;
                _validationError = null;
              });
            },
          ),
        );

        if (mounted) {
          Navigator.of(context).pop(createdInvoice);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _validationError = 'Failed to create invoice: ${e.toString()}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 768;
    final createInvoiceState = ref.watch(createInvoiceNotifierProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('New Billing Invoice'),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: OutlinedButton.icon(
              onPressed: _selectDate,
              icon: const Icon(Icons.calendar_today_outlined, size: 16),
              label: Text(
                DateFormat('dd MMM yyyy').format(_invoiceDate),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.onSurface,
                side: const BorderSide(color: AppColors.outlineVariant),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(
          isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile,
        ),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Department selector card
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    border: Border.all(color: AppColors.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'Department:',
                        style: AppTypography.bodyMd.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'eye',
                              label: Text('Eye Department (Opthalmology)'),
                              icon: Icon(Icons.visibility_outlined, size: 18),
                            ),
                            ButtonSegment(
                              value: 'dental',
                              label: Text('Dental Department'),
                              icon: Icon(Icons.medical_services_outlined, size: 18),
                            ),
                          ],
                          selected: {_department},
                          onSelectionChanged: (selection) {
                            _onDepartmentChanged(selection.first);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Patient search & selection section
                Text(
                  'Patient Selection',
                  style: AppTypography.bodyMd.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                PatientSearchSelector(
                  department: _department,
                  selectedPatient: _selectedPatient,
                  onPatientSelected: (p) {
                    setState(() {
                      _selectedPatient = p;
                      if (p?.department != null &&
                          (p!.department == 'eye' || p.department == 'dental')) {
                        _department = p.department!;
                      }
                      _includePreviousBalance = false;
                      _validationError = null;
                    });
                    if (p != null) {
                      _fetchOutstandingBalance(p.id);
                    } else {
                      _fetchOutstandingBalance(null);
                    }
                  },
                ),
                _buildPreviousOutstandingBalanceSection(),
                const SizedBox(height: AppSpacing.lg),

                // Line items editor
                InvoiceLineItemsEditor(
                  department: _department,
                  items: _items,
                  onChanged: (updated) {
                    setState(() {
                      _items = updated;
                      _validationError = null;
                    });
                  },
                ),
                const SizedBox(height: AppSpacing.lg),

                // Financial summary & payment section
                InvoicePaymentSection(
                  subtotal: _subtotal,
                  discount: _discount,
                  finalTotal: _finalTotal,
                  newCharges: _newChargesSubtotal,
                  previousBalanceIncluded: _previousBalanceIncluded,
                  onDiscountChanged: (d) {
                    setState(() {
                      _discount = d;
                    });
                  },
                  payment: _payment,
                  onPaymentChanged: (p) {
                    setState(() {
                      _payment = p;
                    });
                  },
                ),
                const SizedBox(height: AppSpacing.md),

                // Notes / Remarks field
                TextField(
                  controller: _notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notes / Remarks (Optional)',
                    hintText: 'e.g. Referred by Dr. Smith, special instructions...',
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Validation Error Banner
                if (_validationError != null) ...[
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.errorContainer,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      border: Border.all(color: AppColors.error),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            _validationError!,
                            style: AppTypography.bodySm.copyWith(
                              color: AppColors.onErrorContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: createInvoiceState.isLoading
                          ? null
                          : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      ),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    FilledButton.icon(
                      onPressed: createInvoiceState.isLoading ? null : _submitInvoice,
                      icon: createInvoiceState.isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.receipt_outlined, size: 18),
                      label: Text(
                        createInvoiceState.isLoading
                            ? 'Creating Invoice...'
                            : 'Create Invoice (₹${_finalTotal.toStringAsFixed(2)})',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreviousOutstandingBalanceSection() {
    if (_selectedPatient == null) {
      return const SizedBox.shrink();
    }

    if (_isLoadingOutstanding) {
      return const Padding(
        padding: EdgeInsets.only(top: AppSpacing.sm),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: AppSpacing.sm),
            Text(
              'Checking for previous outstanding balances...',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (_outstandingBalance <= 0) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: _includePreviousBalance
            ? AppColors.primaryContainer.withValues(alpha: 0.4)
            : AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
          color: _includePreviousBalance
              ? AppColors.primary
              : AppColors.outlineVariant,
          width: _includePreviousBalance ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                color: _includePreviousBalance ? AppColors.primary : const Color(0xFFB25E00),
                size: 22,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Previous Outstanding Balance',
                      style: AppTypography.bodyMd.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.onSurface,
                      ),
                    ),
                    Text(
                      'Patient owes ₹${_outstandingBalance.toStringAsFixed(2)} across ${_outstandingInvoices.length} unpaid / partially paid invoice(s)',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '₹${_outstandingBalance.toStringAsFixed(2)}',
                style: AppTypography.bodyLg.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: _outstandingInvoices.map((inv) {
              return Chip(
                padding: EdgeInsets.zero,
                labelPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                backgroundColor: AppColors.surfaceContainerLow,
                side: const BorderSide(color: AppColors.outlineVariant),
                label: Text(
                  '${inv.invoiceNumber}: due ₹${inv.remainingAmount.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!_includePreviousBalance)
                FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _includePreviousBalance = true;
                    });
                  },
                  icon: const Icon(Icons.add_circle_outline, size: 16),
                  label: const Text('Add to This Invoice'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: AppColors.primary,
                  ),
                )
              else ...[
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, color: AppColors.primary, size: 16),
                    SizedBox(width: 4),
                    Text(
                      'Added to Invoice',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _includePreviousBalance = false;
                    });
                  },
                  icon: const Icon(Icons.remove_circle_outline, size: 16),
                  label: const Text('Remove from Invoice'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
