import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../models/inventory_item.dart';
import '../models/inventory_transaction.dart';
import '../providers/inventory_provider.dart';
import '../../patients/models/patient_model.dart';
import '../../patients/providers/patients_provider.dart';
import '../../vendors/providers/vendor_provider.dart';

/// Supported types of stock operations in the dialog.
enum StockOperationType { stockIn, stockOut }

/// Modal dialog allowing staff and admin to perform atomic Stock In or Stock Out operations.
/// Includes real-time preview of current stock, change, and projected resulting stock.
class StockOperationDialog extends ConsumerStatefulWidget {
  const StockOperationDialog({
    super.key,
    required this.item,
    required this.operationType,
  });

  /// Factory constructor for Stock In.
  const StockOperationDialog.stockIn({
    super.key,
    required this.item,
  }) : operationType = StockOperationType.stockIn;

  /// Factory constructor for Stock Out.
  const StockOperationDialog.stockOut({
    super.key,
    required this.item,
  }) : operationType = StockOperationType.stockOut;

  final InventoryItem item;
  final StockOperationType operationType;

  @override
  ConsumerState<StockOperationDialog> createState() =>
      _StockOperationDialogState();
}

class _StockOperationDialogState extends ConsumerState<StockOperationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _totalAmountController = TextEditingController();
  final _customReasonController = TextEditingController();
  final _remarksController = TextEditingController();
  final _patientSearchController = TextEditingController();

  late String _selectedReason;
  PatientModel? _selectedPatient;
  String? _selectedVendorId;
  double _inputQuantity = 0.0;
  bool _isSubmitting = false;

  bool get isStockIn => widget.operationType == StockOperationType.stockIn;

  bool get _isRestockOrDelivery =>
      isStockIn &&
      (_selectedReason == 'Restock' ||
          _selectedReason == 'Restock / New Purchase' ||
          _selectedReason == 'Supplier Delivery' ||
          _selectedReason.startsWith('Restock'));

  List<String> get _defaultReasons =>
      isStockIn ? StockInReasons.defaults : StockOutReasons.defaults;

  @override
  void initState() {
    super.initState();
    _selectedReason = _defaultReasons.first;
    _selectedVendorId = widget.item.vendorId;
    _quantityController.addListener(_onQuantityChanged);
    _totalAmountController.addListener(_onTotalAmountChanged);
  }

  void _onQuantityChanged() {
    final parsed = double.tryParse(_quantityController.text.trim()) ?? 0.0;
    if (parsed != _inputQuantity) {
      setState(() {
        _inputQuantity = parsed;
      });
    }
  }

  void _onTotalAmountChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _quantityController.removeListener(_onQuantityChanged);
    _quantityController.dispose();
    _totalAmountController.removeListener(_onTotalAmountChanged);
    _totalAmountController.dispose();
    _customReasonController.dispose();
    _remarksController.dispose();
    _patientSearchController.dispose();
    super.dispose();
  }

  double get _projectedStock {
    if (isStockIn) {
      return widget.item.currentStock + _inputQuantity;
    } else {
      return widget.item.currentStock - _inputQuantity;
    }
  }

  bool get _willBeLowStock {
    if (widget.item.minimumStock == null) return _projectedStock <= 0;
    return _projectedStock <= widget.item.minimumStock!;
  }

  String _formatNumber(double val) {
    if (val % 1 == 0) return val.toInt().toString();
    return val.toStringAsFixed(2);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final isDispensedToPatient =
        !isStockIn && _selectedReason == StockOutReasons.dispensedToPatient;
    final patientId = isDispensedToPatient ? _selectedPatient?.id : null;

    if (isDispensedToPatient && patientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.error,
          content: Text('Please select a patient.'),
        ),
      );
      return;
    }

    final reason = _selectedReason == 'Other'
        ? _customReasonController.text.trim()
        : _selectedReason;

    final remarks = _remarksController.text.trim();

    setState(() => _isSubmitting = true);

    try {
      final notifier = ref.read(inventoryProvider.notifier);
      final InventoryTransaction tx;

      if (isStockIn) {
        final totalAmount = _isRestockOrDelivery
            ? double.tryParse(_totalAmountController.text.trim())
            : null;
        tx = await notifier.stockIn(
          itemId: widget.item.id,
          quantity: _inputQuantity,
          reason: reason,
          remarks: remarks.isNotEmpty ? remarks : null,
          totalAmount: totalAmount,
          vendorId: _isRestockOrDelivery ? _selectedVendorId : null,
        );
      } else {
        tx = await notifier.stockOut(
          itemId: widget.item.id,
          quantity: _inputQuantity,
          reason: reason,
          remarks: remarks.isNotEmpty ? remarks : null,
          patientId: patientId,
        );
      }

      // Refresh item transaction history provider
      ref.invalidate(itemTransactionsProvider(widget.item.id));

      if (mounted) {
        Navigator.of(context).pop(tx);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: isStockIn ? Colors.green.shade700 : const Color(0xFFE65100),
            behavior: SnackBarBehavior.floating,
            content: Row(
              children: [
                Icon(
                  isStockIn ? Icons.check_circle_outline : Icons.inventory_2_outlined,
                  color: Colors.white,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    isStockIn
                        ? 'Successfully added ${_formatNumber(_inputQuantity)} ${widget.item.unit} to stock.'
                        : 'Successfully deducted ${_formatNumber(_inputQuantity)} ${widget.item.unit} from stock.',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        final cleanMsg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Operation failed: $cleanMsg',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = isStockIn ? Colors.green.shade700 : const Color(0xFFE65100);
    final themeBg = isStockIn
        ? Colors.green.withValues(alpha: 0.1)
        : const Color(0xFFE65100).withValues(alpha: 0.1);
    final isDesktop = MediaQuery.sizeOf(context).width > 600;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      ),
      backgroundColor: AppColors.surfaceContainerLowest,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.lg,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isDesktop ? 540 : 420,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Banner
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              decoration: BoxDecoration(
                color: themeBg,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppSpacing.radiusXl),
                  topRight: Radius.circular(AppSpacing.radiusXl),
                ),
                border: Border(
                  bottom: BorderSide(
                    color: themeColor.withValues(alpha: 0.3),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    decoration: BoxDecoration(
                      color: themeColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: Icon(
                      isStockIn ? Icons.add_circle : Icons.remove_circle,
                      color: themeColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isStockIn ? 'Stock In (Add Stock)' : 'Stock Out (Dispense Stock)',
                          style: AppTypography.headlineMd.copyWith(
                            fontWeight: FontWeight.w700,
                            color: themeColor,
                          ),
                        ),
                        Text(
                          widget.item.name,
                          style: AppTypography.bodySm.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Form Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Projected Stock Preview Card
                      _buildStockPreviewCard(themeColor),
                      const SizedBox(height: AppSpacing.lg),

                      // Quantity Input
                      Text(
                        'QUANTITY (${widget.item.unit.toUpperCase()}) *',
                        style: AppTypography.labelCaps.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      TextFormField(
                        controller: _quantityController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                        ],
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'Enter quantity to ${isStockIn ? 'add' : 'deduct'}',
                          prefixIcon: Icon(
                            isStockIn ? Icons.add : Icons.remove,
                            color: themeColor,
                          ),
                          suffixText: widget.item.unit,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                          ),
                          filled: true,
                          fillColor: AppColors.surfaceContainerLow,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Quantity is required.';
                          }
                          final parsed = double.tryParse(value.trim());
                          if (parsed == null || parsed <= 0) {
                            return 'Quantity must be greater than 0.';
                          }
                          if (!isStockIn && parsed > widget.item.currentStock) {
                            return 'Cannot dispense more than available stock (${_formatNumber(widget.item.currentStock)} ${widget.item.unit}).';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // Reason Selection
                      Text(
                        'REASON *',
                        style: AppTypography.labelCaps.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedReason,
                        isExpanded: true,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                          ),
                          filled: true,
                          fillColor: AppColors.surfaceContainerLow,
                        ),
                        items: _defaultReasons.map((r) {
                          return DropdownMenuItem<String>(
                            value: r,
                            child: Text(r, style: AppTypography.bodyMd),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedReason = val;
                              // If user switches away from Dispensed to Patient, clear selected patient
                              if (_selectedReason !=
                                  StockOutReasons.dispensedToPatient) {
                                _selectedPatient = null;
                                _patientSearchController.clear();
                              }
                            });
                          }
                        },
                      ),

                      // Conditional Patient Selector (Only when Reason = "Dispensed to Patient")
                      if (!isStockIn &&
                          _selectedReason == StockOutReasons.dispensedToPatient) ...[
                        const SizedBox(height: AppSpacing.md),
                        Row(
                          children: [
                            Text(
                              'PATIENT *',
                              style: AppTypography.labelCaps.copyWith(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '(Required)',
                              style: AppTypography.labelCaps.copyWith(
                                color: AppColors.error,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        _buildPatientSelector(),
                      ],

                      // Custom Reason Input if 'Other' selected
                      if (_selectedReason == 'Other') ...[
                        const SizedBox(height: AppSpacing.sm),
                        TextFormField(
                          controller: _customReasonController,
                          decoration: InputDecoration(
                            hintText: 'Specify custom reason...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                            ),
                            filled: true,
                            fillColor: AppColors.surfaceContainerLow,
                          ),
                          validator: (val) {
                            if (_selectedReason == 'Other' &&
                                (val == null || val.trim().isEmpty)) {
                              return 'Please specify the custom reason.';
                            }
                            return null;
                          },
                        ),
                      ],
                      // Conditional Pricing Section (Only when Stock In reason is Restock or Supplier Delivery)
                      if (_isRestockOrDelivery) ...[
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'TOTAL AMOUNT PAID (₹) *',
                          style: AppTypography.labelCaps.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        TextFormField(
                          controller: _totalAmountController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                          ],
                          decoration: InputDecoration(
                            hintText: 'Enter total amount paid (e.g. 5000)',
                            prefixIcon: const Icon(Icons.currency_rupee, color: Colors.green),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                            ),
                            filled: true,
                            fillColor: AppColors.surfaceContainerLow,
                          ),
                          validator: (value) {
                            if (!_isRestockOrDelivery) return null;
                            if (value == null || value.trim().isEmpty) {
                              return 'Total amount paid is required.';
                            }
                            final parsed = double.tryParse(value.trim());
                            if (parsed == null || parsed < 0) {
                              return 'Enter a valid non-negative amount.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),

                        // Auto-Calculated Price Per Piece Card
                        _buildPriceCalculationCard(),
                        const SizedBox(height: AppSpacing.md),

                        // Optional Vendor Selection
                        _buildVendorSelector(),
                      ],
                      const SizedBox(height: AppSpacing.md),

                      // Remarks / Notes (Optional)
                      Text(
                        'REMARKS / REFERENCE (OPTIONAL)',
                        style: AppTypography.labelCaps.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      TextFormField(
                        controller: _remarksController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: 'E.g. Batch #B-402, Patient ID, or transfer details',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                          ),
                          filled: true,
                          fillColor: AppColors.surfaceContainerLow,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.outlineVariant),

            // Footer Actions
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton.icon(
                    onPressed: _isSubmitting ? null : _submit,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            isStockIn ? Icons.arrow_upward : Icons.arrow_downward,
                            size: 18,
                          ),
                    label: Text(
                      _isSubmitting
                          ? 'Recording...'
                          : isStockIn
                              ? 'Confirm Stock In'
                              : 'Confirm Stock Out',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: themeColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.sm,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStockPreviewCard(Color themeColor) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'STOCK PREVIEW',
                style: AppTypography.labelCaps.copyWith(
                  color: AppColors.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
              if (_willBeLowStock && !isStockIn && _inputQuantity > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.errorContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.error, width: 0.8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 12, color: AppColors.error),
                      SizedBox(width: 4),
                      Text(
                        'ENTERS LOW STOCK',
                        style: TextStyle(
                          color: AppColors.error,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              // Current Stock
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.item.formattedStock,
                      style: AppTypography.bodyMd.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),

              // Operator Arrow
              Icon(
                Icons.arrow_forward_rounded,
                size: 20,
                color: AppColors.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),

              // Operation Delta
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      isStockIn ? 'Adding' : 'Deducting',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _inputQuantity > 0
                          ? '${isStockIn ? '+' : '-'}${_formatNumber(_inputQuantity)} ${widget.item.unit}'
                          : '—',
                      style: AppTypography.bodyMd.copyWith(
                        fontWeight: FontWeight.w700,
                        color: themeColor,
                      ),
                    ),
                  ],
                ),
              ),

              // Operator Equals
              const Text('=', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(width: AppSpacing.sm),

              // Resulting Stock
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'New Stock',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_formatNumber(_projectedStock)} ${widget.item.unit}',
                      style: AppTypography.bodyMd.copyWith(
                        fontWeight: FontWeight.w800,
                        color: _willBeLowStock ? AppColors.error : AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPatientSelector() {
    if (_selectedPatient != null) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.primaryContainer.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.person, color: AppColors.primary, size: 22),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _selectedPatient!.name,
                    style: AppTypography.bodyMd.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                    ),
                  ),
                  Text(
                    'ID: ${_selectedPatient!.patientNumber}${_selectedPatient!.mobile != null && _selectedPatient!.mobile!.isNotEmpty ? ' • ${_selectedPatient!.mobile}' : ''}',
                    style: AppTypography.labelCaps.copyWith(
                      fontSize: 11,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Clear patient',
              onPressed: () {
                setState(() {
                  _selectedPatient = null;
                  _patientSearchController.clear();
                });
              },
            ),
          ],
        ),
      );
    }

    final patientsAsync = ref.watch(patientsProvider);
    final search = _patientSearchController.text.trim().toLowerCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _patientSearchController,
          decoration: InputDecoration(
            hintText: 'Search patient by name, ID, or mobile...',
            prefixIcon: const Icon(Icons.person_search_outlined),
            suffixIcon: _patientSearchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _patientSearchController.clear();
                      setState(() {});
                    },
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            filled: true,
            fillColor: AppColors.surfaceContainerLow,
          ),
          onChanged: (_) => setState(() {}),
          validator: (_) {
            if (_selectedPatient == null) {
              return 'Please select a patient.';
            }
            return null;
          },
        ),
        const SizedBox(height: AppSpacing.xs),
        patientsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'Could not load patients: $e',
              style: AppTypography.bodySm.copyWith(color: AppColors.error),
            ),
          ),
          data: (patients) {
            final matches = search.isEmpty
                ? patients.take(4).toList()
                : patients.where((p) {
                    return p.name.toLowerCase().contains(search) ||
                        p.patientNumber.toLowerCase().contains(search) ||
                        (p.mobile != null && p.mobile!.toLowerCase().contains(search));
                  }).take(5).toList();

            if (matches.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  search.isEmpty
                      ? 'No registered patients found.'
                      : 'No patients matching "$search".',
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              );
            }

            return Container(
              constraints: const BoxConstraints(maxHeight: 180),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: AppColors.outlineVariant),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: matches.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final p = matches[index];
                  return Material(
                    color: Colors.transparent,
                    child: ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.person_outline,
                        size: 20,
                        color: AppColors.primary,
                      ),
                      title: Text(
                        p.name,
                        style: AppTypography.bodyMd.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        'ID: ${p.patientNumber}${p.mobile != null && p.mobile!.isNotEmpty ? ' • ${p.mobile}' : ''}',
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                      onTap: () {
                        setState(() {
                          _selectedPatient = p;
                          _patientSearchController.clear();
                        });
                      },
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildPriceCalculationCard() {
    final qty = _inputQuantity;
    final total = double.tryParse(_totalAmountController.text.trim()) ?? 0.0;
    final pricePerPiece = (qty > 0 && total >= 0) ? (total / qty) : null;

    final priceStr = pricePerPiece != null
        ? '₹${pricePerPiece.toStringAsFixed(2)} / ${widget.item.unit}'
        : '—';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calculate_outlined, size: 16, color: Colors.green),
              const SizedBox(width: 6),
              Text(
                'AUTOMATIC PRICE PER PIECE',
                style: AppTypography.labelCaps.copyWith(
                  color: Colors.green.shade800,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quantity: ${_formatNumber(qty)} ${widget.item.unit}',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      'Total Paid: ₹${total.toStringAsFixed(2)}',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Price Per Piece',
                    style: AppTypography.labelCaps.copyWith(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 9,
                    ),
                  ),
                  Text(
                    priceStr,
                    style: AppTypography.headlineMd.copyWith(
                      fontSize: 18,
                      color: Colors.green.shade800,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVendorSelector() {
    final vendorsAsync = ref.watch(vendorsProvider);
    final vendors = (vendorsAsync.value ?? []).where((v) => v.isActive).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SUPPLIER / VENDOR (OPTIONAL)',
          style: AppTypography.labelCaps.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        DropdownButtonFormField<String?>(
          initialValue: _selectedVendorId,
          isExpanded: true,
          decoration: InputDecoration(
            hintText: 'Select supplier vendor...',
            prefixIcon: const Icon(Icons.storefront_outlined),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            filled: true,
            fillColor: AppColors.surfaceContainerLow,
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('None / Unknown Vendor', style: TextStyle(color: AppColors.onSurfaceVariant)),
            ),
            ...vendors.map((v) {
              return DropdownMenuItem<String?>(
                value: v.id,
                child: Text(
                  v.contactPerson != null ? '${v.name} (${v.contactPerson})' : v.name,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }),
          ],
          onChanged: (val) {
            setState(() {
              _selectedVendorId = val;
            });
          },
        ),
      ],
    );
  }
}
