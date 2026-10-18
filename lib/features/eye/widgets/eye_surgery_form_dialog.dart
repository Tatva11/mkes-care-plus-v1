import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/providers/auth_provider.dart';
import '../../patients/models/patient_model.dart';
import '../../patients/repositories/patient_repository.dart';
import '../models/eye_surgery_model.dart';
import '../models/eye_surgery_item_model.dart';
import '../providers/eye_surgery_provider.dart';
import 'eye_surgery_item_dialogs.dart';

class FormSurgeryItem {
  final String? id;
  final String inventoryItemId;
  final String inventoryItemName;
  final double currentStock;
  final String unit;
  double plannedQuantity;
  final String source;

  FormSurgeryItem({
    this.id,
    required this.inventoryItemId,
    required this.inventoryItemName,
    required this.currentStock,
    required this.unit,
    required this.plannedQuantity,
    this.source = 'manual',
  });
}

class EyeSurgeryFormDialog extends ConsumerStatefulWidget {
  const EyeSurgeryFormDialog({
    super.key,
    this.existingSurgery,
    this.initialPatientId,
    this.initialPatientName,
    this.initialPatientNumber,
    this.initialSurgeryDate,
    this.initialSurgeryTime,
    this.initialAssignedStaffId,
    this.initialRemarks,
  });

  final EyeSurgeryModel? existingSurgery;
  final String? initialPatientId;
  final String? initialPatientName;
  final String? initialPatientNumber;
  final DateTime? initialSurgeryDate;
  final TimeOfDay? initialSurgeryTime;
  final String? initialAssignedStaffId;
  final String? initialRemarks;

  bool get isEditing => existingSurgery != null;

  @override
  ConsumerState<EyeSurgeryFormDialog> createState() =>
      _EyeSurgeryFormDialogState();
}

class _EyeSurgeryFormDialogState extends ConsumerState<EyeSurgeryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _searchController = TextEditingController();
  final _customTypeController = TextEditingController();
  final _iolController = TextEditingController();
  final _remarksController = TextEditingController();
  final Map<String, bool> _checklist = {};
  List<PatientModel> _searchResults = [];
  String? _selectedPatientId;
  String? _selectedPatientName;
  String? _selectedPatientNumber;
  String? _eyeSide;
  String? _assignedStaffId;
  late String _surgeryTypeCategory;
  late DateTime _surgeryDate;
  TimeOfDay? _surgeryTime;
  bool _isLoading = false;
  int _searchRequestId = 0;

  /// Surgery items list for this surgery.
  List<FormSurgeryItem> _surgeryItems = [];
  String? _loadedSurgeryTypeForTemplates;
  bool _existingItemsLoaded = false;

  bool get _isLocked => widget.existingSurgery?.inventoryConsumedAt != null;

  @override
  void initState() {
    super.initState();
    final surgery = widget.existingSurgery;
    _selectedPatientId = surgery?.patientId ?? widget.initialPatientId;
    _selectedPatientName = surgery?.patientName ?? widget.initialPatientName;
    _selectedPatientNumber =
        surgery?.patientNumber ?? widget.initialPatientNumber;
    _surgeryTypeCategory = surgery?.surgeryTypeCategory ??
        EyeSurgeryModel.surgeryTypeOptions.first;
    _customTypeController.text = surgery?.customSurgeryType ??
        (surgery?.surgeryTypeCategory == 'Other' ? surgery?.surgeryType : '') ??
        '';
    _eyeSide = surgery?.eyeSide;
    _assignedStaffId = surgery?.assignedStaffId?.trim().toLowerCase() ??
        widget.initialAssignedStaffId?.trim().toLowerCase();
    _surgeryDate =
        surgery?.surgeryDate ?? widget.initialSurgeryDate ?? DateTime.now();
    _surgeryTime =
        _parseTime(surgery?.surgeryTime) ?? widget.initialSurgeryTime;
    _checklist.addAll(surgery?.preOpChecklist ?? const {});
    _iolController.text = surgery?.iolDetails ?? '';
    _remarksController.text = surgery?.remarks ?? widget.initialRemarks ?? '';

    if (widget.isEditing) {
      _loadedSurgeryTypeForTemplates = _surgeryTypeCategory;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _customTypeController.dispose();
    _iolController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  TimeOfDay? _parseTime(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parts = value.trim().split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  String? _formattedTime() {
    final time = _surgeryTime;
    if (time == null) return null;
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:00';
  }

  Future<void> _searchPatients(String query) async {
    final requestId = ++_searchRequestId;
    final normalized = query.trim();
    if (normalized.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    try {
      final results = await ref.read(patientRepositoryProvider).fetchPatients(
            department: 'eye',
            searchQuery: normalized,
          );
      if (mounted && requestId == _searchRequestId) {
        setState(() => _searchResults = results);
      }
    } catch (_) {
      if (mounted && requestId == _searchRequestId) {
        setState(() => _searchResults = []);
      }
    }
  }

  void _selectPatient(PatientModel patient) {
    setState(() {
      _selectedPatientId = patient.id;
      _selectedPatientName = patient.name;
      _selectedPatientNumber = patient.patientNumber;
      _searchController.clear();
      _searchResults = [];
    });
  }

  Future<void> _addInventoryItem() async {
    if (_isLocked) return;
    final excluded = _surgeryItems.map((i) => i.inventoryItemId).toSet();
    final result = await EyeSurgeryInventoryPickerDialog.show(
      context,
      excludedItemIds: excluded,
    );
    if (result == null || result.isEmpty) return;

    for (final entry in result) {
      final existingIndex = _surgeryItems.indexWhere(
        (i) => i.inventoryItemId == entry.item.id,
      );

      if (existingIndex >= 0) {
        setState(() {
          _surgeryItems[existingIndex].plannedQuantity += entry.quantity;
        });
        if (widget.isEditing && _surgeryItems[existingIndex].id != null) {
          try {
            await ref
                .read(eyeSurgeryItemsProvider(widget.existingSurgery!.id)
                    .notifier)
                .updateItem(
                  itemId: _surgeryItems[existingIndex].id!,
                  plannedQuantity: _surgeryItems[existingIndex].plannedQuantity,
                  actualQuantity: _surgeryItems[existingIndex].plannedQuantity,
                );
          } catch (_) {}
        }
      } else {
        if (widget.isEditing) {
          try {
            await ref
                .read(eyeSurgeryItemsProvider(widget.existingSurgery!.id)
                    .notifier)
                .addItem(
                  inventoryItemId: entry.item.id,
                  plannedQuantity: entry.quantity,
                  source: 'manual',
                );
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Unable to add item: $e')),
              );
            }
          }
        } else {
          setState(() {
            _surgeryItems.add(FormSurgeryItem(
              inventoryItemId: entry.item.id,
              inventoryItemName: entry.item.name,
              currentStock: entry.item.currentStock,
              unit: entry.item.unit,
              plannedQuantity: entry.quantity,
              source: 'manual',
            ));
          });
        }
      }
    }
    if (widget.isEditing) {
      ref.invalidate(eyeSurgeryItemsProvider(widget.existingSurgery!.id));
    }
  }

  Future<void> _editItemQuantity(FormSurgeryItem item) async {
    if (_isLocked) return;
    final controller = TextEditingController(text: '${item.plannedQuantity}');
    final newQty = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Quantity: ${item.inventoryItemName}'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Planned Quantity (${item.unit})',
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final val = double.tryParse(controller.text.trim());
              if (val != null && val > 0) Navigator.pop(ctx, val);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newQty != null && newQty > 0) {
      setState(() {
        item.plannedQuantity = newQty;
      });
      if (widget.isEditing && item.id != null) {
        try {
          await ref
              .read(
                  eyeSurgeryItemsProvider(widget.existingSurgery!.id).notifier)
              .updateItem(
                itemId: item.id!,
                plannedQuantity: newQty,
                actualQuantity: newQty,
              );
        } catch (_) {}
      }
    }
  }

  Future<void> _removeItem(FormSurgeryItem item) async {
    if (_isLocked) return;
    setState(() {
      _surgeryItems.remove(item);
    });
    if (widget.isEditing && item.id != null) {
      try {
        await ref
            .read(eyeSurgeryItemsProvider(widget.existingSurgery!.id).notifier)
            .removeItem(item.id!);
      } catch (_) {}
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final validationError = EyeSurgeryModel.validateFields(
      patientId: _selectedPatientId ?? '',
      surgeryType: _surgeryTypeCategory == 'Other'
          ? _customTypeController.text
          : _surgeryTypeCategory,
      surgeryTypeCategory: _surgeryTypeCategory,
      customSurgeryType: _customTypeController.text,
      eyeSide: _eyeSide ?? '',
      preOpDate: _surgeryDate,
      surgeryDate: _surgeryDate,
      surgeryTime: _formattedTime(),
      status: widget.existingSurgery?.status ?? 'scheduled',
    );
    if (validationError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(validationError)),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final surgeryType = _surgeryTypeCategory == 'Other'
          ? _customTypeController.text.trim()
          : _surgeryTypeCategory;
      final customSurgeryType = _surgeryTypeCategory == 'Other'
          ? _customTypeController.text.trim()
          : null;
      final notifier = ref.read(eyeSurgeryListProvider.notifier);
      final existing = widget.existingSurgery;
      final role = ref.read(currentUserRoleProvider).valueOrNull;
      final isAdmin = role == 'admin';
      final effectiveAssignedStaffId =
          isAdmin ? _assignedStaffId : existing?.assignedStaffId;

      if (existing == null) {
        final initialItems = _surgeryItems
            .map((item) => (
                  inventoryItemId: item.inventoryItemId,
                  plannedQuantity: item.plannedQuantity,
                  source: item.source,
                ))
            .toList();

        await notifier.createSurgery(
          patientId: _selectedPatientId!,
          surgeryType: surgeryType,
          surgeryTypeCategory: _surgeryTypeCategory,
          customSurgeryType: customSurgeryType,
          eyeSide: _eyeSide!,
          surgeryDate: _surgeryDate,
          assignedStaffId: effectiveAssignedStaffId,
          surgeryTime: _formattedTime(),
          preOpChecklist: _checklist,
          iolDetails: _iolController.text,
          remarks: _remarksController.text,
          initialItems: initialItems,
        );
      } else {
        await notifier.updateSurgery(
          EyeSurgeryModel(
            id: existing.id,
            patientId: _selectedPatientId!,
            surgeryType: surgeryType,
            surgeryTypeCategory: _surgeryTypeCategory,
            customSurgeryType: customSurgeryType,
            eyeSide: _eyeSide!,
            assignedStaffId: effectiveAssignedStaffId,
            assignedStaffName: existing.assignedStaffName,
            preOpDate: _surgeryDate,
            surgeryDate: _surgeryDate,
            surgeryTime: _formattedTime(),
            status: existing.status,
            preOpChecklist: Map.unmodifiable(_checklist),
            iolDetails: _iolController.text.trim().isEmpty
                ? null
                : _iolController.text.trim(),
            remarks: _remarksController.text.trim().isEmpty
                ? null
                : _remarksController.text.trim(),
            createdAt: existing.createdAt,
            updatedAt: existing.updatedAt,
            patientName: _selectedPatientName,
            patientNumber: _selectedPatientNumber,
            inventoryConsumedAt: existing.inventoryConsumedAt,
          ),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to save surgery: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final height = MediaQuery.sizeOf(context).height;
    final role = ref.watch(currentUserRoleProvider).valueOrNull;
    final isAdmin = role == 'admin';
    final staffAsync = ref.watch(eyeSurgeryStaffCandidatesProvider);
    final templatesAsync =
        ref.watch(eyeSurgeryItemTemplatesProvider(_surgeryTypeCategory));

    // Auto-populate templates for NEW surgery
    if (!widget.isEditing &&
        _loadedSurgeryTypeForTemplates != _surgeryTypeCategory) {
      templatesAsync.whenData((templates) {
        if (_loadedSurgeryTypeForTemplates != _surgeryTypeCategory) {
          _loadedSurgeryTypeForTemplates = _surgeryTypeCategory;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                final customItems =
                    _surgeryItems.where((i) => i.source == 'manual').toList();
                final customIds =
                    customItems.map((c) => c.inventoryItemId).toSet();
                final templateItems = templates
                    .where((t) => !customIds.contains(t.inventoryItemId))
                    .map((t) => FormSurgeryItem(
                          inventoryItemId: t.inventoryItemId,
                          inventoryItemName: t.inventoryItemName,
                          currentStock: t.currentStock,
                          unit: t.unit,
                          plannedQuantity: t.defaultQuantity,
                          source: 'template',
                        ))
                    .toList();
                _surgeryItems = [...templateItems, ...customItems];
              });
            }
          });
        }
      });
    }

    // Load existing items for EDIT surgery
    if (widget.isEditing && !_existingItemsLoaded) {
      final existingItemsAsync =
          ref.watch(eyeSurgeryItemsProvider(widget.existingSurgery!.id));
      existingItemsAsync.whenData((items) {
        if (!_existingItemsLoaded) {
          _existingItemsLoaded = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _surgeryItems = items
                    .map((i) => FormSurgeryItem(
                          id: i.id,
                          inventoryItemId: i.inventoryItemId,
                          inventoryItemName: i.inventoryItemName,
                          currentStock: i.currentStock,
                          unit: i.unit,
                          plannedQuantity: i.plannedQuantity,
                          source: i.source,
                        ))
                    .toList();
              });
            }
          });
        }
      });
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: (width - 24).clamp(280.0, 700.0),
          maxHeight: (height - 32).clamp(320.0, 840.0),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                child: Row(
                  children: [
                    const Icon(Icons.visibility_outlined,
                        color: AppColors.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        widget.isEditing
                            ? 'Edit Eye Surgery'
                            : 'Schedule Eye Surgery',
                        style: AppTypography.headlineMd,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('PATIENT',
                          style: AppTypography.labelCaps
                              .copyWith(color: AppColors.primary)),
                      const SizedBox(height: AppSpacing.xs),
                      if (_selectedPatientId != null)
                        InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Eye patient *',
                            border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(AppSpacing.radiusMd)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${_selectedPatientName ?? 'Patient'}${_selectedPatientNumber == null ? '' : ' • $_selectedPatientNumber'}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Change patient',
                                onPressed: () => setState(() {
                                  _selectedPatientId = null;
                                  _selectedPatientName = null;
                                  _selectedPatientNumber = null;
                                }),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        TextFormField(
                          controller: _searchController,
                          decoration: const InputDecoration(
                            labelText: 'Search Eye patient *',
                            hintText: 'Name, patient number, or mobile',
                            prefixIcon: Icon(Icons.person_search_outlined),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: _searchPatients,
                          validator: (_) => _selectedPatientId == null
                              ? 'Select an Eye department patient.'
                              : null,
                        ),
                        if (_searchResults.isNotEmpty)
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 180),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: _searchResults.length,
                              itemBuilder: (context, index) {
                                final patient = _searchResults[index];
                                return ListTile(
                                  dense: true,
                                  title: Text(patient.name,
                                      overflow: TextOverflow.ellipsis),
                                  subtitle: Text(patient.patientNumber),
                                  onTap: () => _selectPatient(patient),
                                );
                              },
                            ),
                          ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      DropdownButtonFormField<String>(
                        initialValue: _surgeryTypeCategory,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Surgery type *',
                          prefixIcon: Icon(Icons.medical_services_outlined),
                          border: OutlineInputBorder(),
                        ),
                        items: EyeSurgeryModel.surgeryTypeOptions
                            .map((option) => DropdownMenuItem(
                                  value: option,
                                  child: Text(option,
                                      overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (value) {
                          if (value != null && value != _surgeryTypeCategory) {
                            setState(() {
                              _surgeryTypeCategory = value;
                              if (!widget.isEditing) {
                                // Clear previous unsaved default item list and trigger reload
                                _loadedSurgeryTypeForTemplates = null;
                                _surgeryItems = [];
                              }
                            });
                          }
                        },
                      ),
                      if (_surgeryTypeCategory == 'Other') ...[
                        const SizedBox(height: AppSpacing.sm),
                        TextFormField(
                          controller: _customTypeController,
                          decoration: const InputDecoration(
                            labelText: 'Custom surgery type *',
                            hintText: 'Enter surgery type',
                            border: OutlineInputBorder(),
                          ),
                          textCapitalization: TextCapitalization.sentences,
                          validator: (value) =>
                              _surgeryTypeCategory == 'Other' &&
                                      (value == null || value.trim().isEmpty)
                                  ? 'Enter the custom surgery type.'
                                  : null,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      DropdownButtonFormField<String>(
                        initialValue: _eyeSide,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Eye side *',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: 'left', child: Text('Left eye')),
                          DropdownMenuItem(
                              value: 'right', child: Text('Right eye')),
                          DropdownMenuItem(
                              value: 'both', child: Text('Both eyes')),
                        ],
                        validator: (value) =>
                            value == null ? 'Select the eye side.' : null,
                        onChanged: (value) => setState(() => _eyeSide = value),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      // --- Assigned Staff field (Admin-only editable) ---
                      _buildAssignedStaffField(staffAsync, isAdmin),
                      const SizedBox(height: AppSpacing.md),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final dateField = Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text('Surgery Date *',
                                  style: AppTypography.labelCaps),
                              const SizedBox(height: AppSpacing.xs),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _surgeryDate,
                                    firstDate: DateTime(1900),
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked != null) {
                                    setState(() => _surgeryDate = picked);
                                  }
                                },
                                icon: const Icon(Icons.calendar_today_outlined),
                                label: Text(
                                  DateFormat('dd/MM/yyyy').format(_surgeryDate),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          );
                          final timeField = Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text('Surgery Time *',
                                  style: AppTypography.labelCaps),
                              const SizedBox(height: AppSpacing.xs),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final picked = await showTimePicker(
                                    context: context,
                                    initialTime: _surgeryTime ??
                                        const TimeOfDay(hour: 9, minute: 0),
                                  );
                                  if (picked != null) {
                                    setState(() => _surgeryTime = picked);
                                  }
                                },
                                icon: const Icon(Icons.access_time_outlined),
                                label: Text(
                                  _surgeryTime != null
                                      ? _surgeryTime!.format(context)
                                      : 'Select Time *',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          );
                          if (constraints.maxWidth < 440) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                dateField,
                                const SizedBox(height: AppSpacing.sm),
                                timeField,
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: dateField),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(child: timeField),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Status',
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          (widget.existingSurgery?.status ?? 'scheduled')
                              .replaceAll('_', ' ')
                              .toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('PRE-OP CHECKLIST',
                              style: AppTypography.labelCaps
                                  .copyWith(color: AppColors.primary)),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color:
                                  _checklist.values.where((v) => v).length == 8
                                      ? Colors.green.withValues(alpha: 0.15)
                                      : Colors.orange.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${_checklist.values.where((v) => v).length} / 8 completed',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color:
                                    _checklist.values.where((v) => v).length ==
                                            8
                                        ? Colors.green.shade800
                                        : Colors.orange.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      ...EyeSurgeryModel.checklistItems.entries.map((item) {
                        final isDone = _checklist[item.key] ?? false;
                        return CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(
                            item.value,
                            style: TextStyle(
                              color: isDone ? null : AppColors.onSurfaceVariant,
                            ),
                          ),
                          value: isDone,
                          onChanged: (checked) => setState(
                              () => _checklist[item.key] = checked ?? false),
                        );
                      }),
                      const SizedBox(height: AppSpacing.lg),
                      // --- SURGERY ITEMS SECTION ---
                      _buildSurgeryItemsSection(templatesAsync),
                      const SizedBox(height: AppSpacing.lg),
                      TextFormField(
                        controller: _iolController,
                        decoration: const InputDecoration(
                          labelText: 'IOL details',
                          hintText: 'Lens model and power details',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextFormField(
                        controller: _remarksController,
                        decoration: const InputDecoration(
                          labelText: 'Remarks / post-op information',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    TextButton(
                      onPressed:
                          _isLoading ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isLoading ? null : _submit,
                        icon: _isLoading
                            ? const SizedBox.square(
                                dimension: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.save_outlined),
                        label: Text(widget.isEditing
                            ? 'Save changes'
                            : 'Schedule surgery'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAssignedStaffField(
    AsyncValue<List<EyeSurgeryStaffCandidate>> staffAsync,
    bool isAdmin,
  ) {
    if (!isAdmin) {
      final staffName = widget.existingSurgery?.assignedStaffName ??
          staffAsync.valueOrNull
              ?.where((s) => s.id == _assignedStaffId)
              .firstOrNull
              ?.fullName ??
          'No staff assigned';
      return InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Assigned Staff',
          prefixIcon: Icon(Icons.person_outline),
          border: OutlineInputBorder(),
          helperText: 'Assigned Staff is read-only (Admin assignment required)',
        ),
        child: Text(
          staffName,
          style: const TextStyle(fontWeight: FontWeight.w500),
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    return _buildAssignedStaffDropdown(staffAsync);
  }

  Widget _buildAssignedStaffDropdown(
    AsyncValue<List<EyeSurgeryStaffCandidate>> staffAsync,
  ) {
    return staffAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (error, _) => Text('Unable to load Assigned Staff: $error'),
      data: (staff) {
        final uniqueStaff = uniqueEyeSurgeryStaffCandidates(staff);

        // If the surgery already has an assigned staff member not present in uniqueStaff,
        // preserve it in the dropdown list so it is not dropped
        final savedStaffId = _assignedStaffId;
        final listHasSelected = savedStaffId == null ||
            uniqueStaff.any((item) => item.id == savedStaffId);

        final displayStaff = List<EyeSurgeryStaffCandidate>.of(uniqueStaff);
        if (savedStaffId != null && !listHasSelected) {
          displayStaff.insert(
            0,
            EyeSurgeryStaffCandidate(
              id: savedStaffId,
              fullName:
                  widget.existingSurgery?.assignedStaffName ?? 'Assigned Staff',
            ),
          );
        }

        final selectedStaffId = _assignedStaffId;

        final items = <DropdownMenuItem<String?>>[
          const DropdownMenuItem(value: null, child: Text('Unassigned')),
          ...displayStaff.map((candidate) => DropdownMenuItem<String?>(
                value: candidate.id,
                child:
                    Text(candidate.fullName, overflow: TextOverflow.ellipsis),
              )),
        ];

        return DropdownButtonFormField<String?>(
          key: ValueKey(
            '${displayStaff.map((item) => item.id).join('|')}:$selectedStaffId',
          ),
          initialValue: selectedStaffId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Assigned Staff',
            prefixIcon: Icon(Icons.person_outline),
            border: OutlineInputBorder(),
          ),
          items: items,
          onChanged: (value) => setState(() => _assignedStaffId = value),
        );
      },
    );
  }

  Widget _buildSurgeryItemsSection(
    AsyncValue<List<EyeSurgeryItemTemplateModel>> templatesAsync,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            Text(
              'SURGERY ITEMS',
              style: AppTypography.labelCaps.copyWith(color: AppColors.primary),
            ),
            if (!_isLocked)
              OutlinedButton.icon(
                onPressed: _addInventoryItem,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Inventory Item'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        if (_isLocked)
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: const Row(
              children: [
                Icon(Icons.lock_outline, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Inventory has been consumed; items are locked.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        if (_surgeryItems.isEmpty)
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: Column(
              children: [
                Text(
                  templatesAsync.valueOrNull?.isEmpty == true
                      ? 'No preset items configured for $_surgeryTypeCategory.'
                      : 'No surgery items added yet.',
                  style: TextStyle(color: AppColors.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Add required consumables and medications below.',
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (!_isLocked) ...[
                  const SizedBox(height: AppSpacing.sm),
                  FilledButton.icon(
                    onPressed: _addInventoryItem,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Inventory Item'),
                  ),
                ],
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _surgeryItems.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xs),
            itemBuilder: (context, index) {
              final item = _surgeryItems[index];
              final outOfStock = item.currentStock <= 0;

              return Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.inventoryItemName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!_isLocked) ...[
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              tooltip: 'Edit quantity',
                              onPressed: () => _editItemQuantity(item),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18),
                              tooltip: 'Remove item',
                              onPressed: () => _removeItem(item),
                            ),
                          ],
                        ],
                      ),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          Text(
                            'Planned: ${item.plannedQuantity} ${item.unit}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            'Stock: ${item.currentStock} ${item.unit}',
                            style: TextStyle(
                              fontSize: 12,
                              color: outOfStock ? AppColors.error : null,
                            ),
                          ),
                        ],
                      ),
                      if (outOfStock) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.error.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Out of Stock',
                                style: TextStyle(
                                  color: AppColors.error,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 6),
                              ),
                              onPressed: () =>
                                  openEyeSurgeryPurchaseOrders(context),
                              icon: const Icon(Icons.receipt_long_outlined,
                                  size: 14),
                              label: const Text('Go to Purchase Orders',
                                  style: TextStyle(fontSize: 11)),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
