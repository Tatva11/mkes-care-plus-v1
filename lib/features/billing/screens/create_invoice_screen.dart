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
import '../widgets/invoice_line_items_editor.dart';
import '../widgets/invoice_payment_section.dart';
import '../widgets/invoice_success_dialog.dart';
import '../widgets/patient_search_selector.dart';

class CreateInvoiceScreen extends ConsumerStatefulWidget {
  final PatientModel? initialPatient;
  final String? initialDepartment;

  const CreateInvoiceScreen({
    super.key,
    this.initialPatient,
    this.initialDepartment,
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

    // Initial empty service item
    _items = [
      const BillingItemModel(
        serviceName: '',
        quantity: 1,
        unitPrice: 0.0,
      ),
    ];
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  double get _subtotal =>
      _items.fold(0.0, (sum, item) => sum + item.totalAmount);

  double get _finalTotal => (_subtotal - _discount).clamp(0.0, double.infinity);

  void _onDepartmentChanged(String newDept) {
    if (_department == newDept) return;
    setState(() {
      _department = newDept;
      if (_selectedPatient?.department?.toLowerCase() != newDept) {
        _selectedPatient = null;
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

    try {
      final notifier = ref.read(createInvoiceNotifierProvider.notifier);
      final createdInvoice = await notifier.createInvoice(
        patientId: _selectedPatient!.id,
        department: _department,
        discount: _discount,
        items: _items,
        payment: _payment,
        invoiceDate: _invoiceDate,
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
      );

      if (mounted && createdInvoice != null) {
        final enrichedInvoice = createdInvoice.copyWith(
          items: _items,
          patientName: _selectedPatient?.name,
          patientNumber: _selectedPatient?.patientNumber,
          patientMobile: _selectedPatient?.mobile,
        );

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
                      _validationError = null;
                    });
                  },
                ),
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
}
