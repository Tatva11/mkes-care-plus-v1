import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../appointments/models/appointment_model.dart';
import '../../appointments/widgets/appointment_form_dialog.dart';
import '../models/dental_lab_model.dart';
import '../providers/dental_lab_provider.dart';
import '../widgets/dental_lab_form_dialog.dart';
import '../widgets/dental_lab_whatsapp_dialog.dart';

/// Full screen container for Dental Lab Tracking.
class DentalLabScreen extends StatelessWidget {
  const DentalLabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Dental Lab Tracking'),
        backgroundColor: AppColors.surface,
        elevation: 0,
      ),
      body: const DentalLabContent(),
    );
  }
}

/// Embeddable content widget for Dental Lab Tracking.
class DentalLabContent extends ConsumerStatefulWidget {
  const DentalLabContent({super.key});

  @override
  ConsumerState<DentalLabContent> createState() => _DentalLabContentState();
}

class _DentalLabContentState extends ConsumerState<DentalLabContent> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openCreateDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const DentalLabFormDialog(),
    );
  }

  void _openEditDialog(DentalLabModel item) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => DentalLabFormDialog(initialCase: item),
    );
  }

  Future<void> _editLinkedAppointment(DentalLabModel item) async {
    if (item.appointmentId == null || item.patientId == null) return;

    final initialAppointment = AppointmentModel(
      id: item.appointmentId!,
      patientId: item.patientId,
      patientName: item.patientName ?? 'Patient',
      patientNumber: item.patientNumber ?? 'Unknown ID',
      department: 'dental',
      appointmentDate: item.appointmentDate ?? DateTime.now(),
      appointmentTime: item.appointmentTime ?? '10:30:00',
      appointmentType: 'follow_up',
      status: item.appointmentStatus ?? 'scheduled',
      notes: item.remarks,
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AppointmentFormDialog(
        existingAppointment: initialAppointment,
        initialPatientId: item.patientId,
        initialPatientName: item.patientName,
      ),
    );

    if (saved != true || !mounted) return;
    await ref.read(dentalLabListProvider.notifier).refresh();
  }

  Future<void> _transitionStatus(DentalLabModel item, String newStatus) async {
    final statusLabel = newStatus == 'ready' ? 'Ready' : 'Delivered';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Mark Case as $statusLabel?'),
        content: Text(
          'Update case #${item.caseNumber} (${item.caseType}) for ${item.patientName ?? "patient"} to "$statusLabel"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: newStatus == 'ready' ? AppColors.secondary : Colors.green,
            ),
            child: Text('Confirm $statusLabel'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final updated = await ref
          .read(dentalLabListProvider.notifier)
          .updateStatus(id: item.id, newStatus: newStatus);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: newStatus == 'ready' ? AppColors.secondary : Colors.green.shade700,
            content: Text('Case #${updated.caseNumber} marked as ${updated.statusLabel}.'),
            action: newStatus == 'ready'
                ? SnackBarAction(
                    label: 'WhatsApp',
                    textColor: Colors.white,
                    onPressed: () => DentalLabWhatsAppDialog.show(context, updated),
                  )
                : null,
          ),
        );

        // If moved to ready, optionally prompt WhatsApp notification
        if (newStatus == 'ready') {
          DentalLabWhatsAppDialog.show(context, updated);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.error,
            content: Text('Error updating status: $e'),
          ),
        );
      }
    }
  }

  Future<void> _deleteCase(DentalLabModel item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Lab Case'),
        content: Text(
          'Are you sure you want to delete case #${item.caseNumber}? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await ref.read(dentalLabListProvider.notifier).deleteCase(item.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Case #${item.caseNumber} deleted successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.error,
            content: Text('Error deleting case: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(dentalLabStatsProvider);
    final currentFilter = ref.watch(dentalLabStatusFilterProvider);
    final cases = ref.watch(filteredDentalLabListProvider);
    final rawAsync = ref.watch(dentalLabListProvider);

    final isDesktop = MediaQuery.sizeOf(context).width >= 768;

    return RefreshIndicator(
      onRefresh: () => ref.read(dentalLabListProvider.notifier).refresh(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(
          isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── KPI Summary Cards ─────────────────────────────────────
            _buildKpiRow(stats, isDesktop),
            const SizedBox(height: AppSpacing.md),

            // ── Controls Header: Search, Filter, Add ──────────────────
            _buildControlsHeader(isDesktop, currentFilter),
            const SizedBox(height: AppSpacing.md),

            // ── Main Content / Table ──────────────────────────────────
            rawAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (err, _) => Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.errorContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  border: Border.all(color: AppColors.error),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.error_outline, size: 40, color: AppColors.error),
                    const SizedBox(height: AppSpacing.xs),
                    Text('Failed to load dental lab cases', style: AppTypography.headlineMd),
                    const SizedBox(height: 4),
                    Text('$err', style: AppTypography.bodySm.copyWith(color: AppColors.error)),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton.icon(
                      onPressed: () => ref.read(dentalLabListProvider.notifier).refresh(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (_) {
                if (cases.isEmpty) {
                  return _buildEmptyState();
                }
                return _buildCasesCard(cases, isDesktop);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiRow(DentalLabStats stats, bool isDesktop) {
    final cards = [
      _KpiCard(
        title: 'Total Cases',
        count: '${stats.total}',
        icon: Icons.biotech_outlined,
        color: AppColors.primary,
        onTap: () => ref.read(dentalLabStatusFilterProvider.notifier).state = 'all',
        isActive: ref.watch(dentalLabStatusFilterProvider) == 'all',
      ),
      _KpiCard(
        title: 'In Processing',
        count: '${stats.processing}',
        icon: Icons.hourglass_top_outlined,
        color: Colors.amber.shade800,
        onTap: () => ref.read(dentalLabStatusFilterProvider.notifier).state = 'processing',
        isActive: ref.watch(dentalLabStatusFilterProvider) == 'processing',
      ),
      _KpiCard(
        title: 'Ready for Fit',
        count: '${stats.ready}',
        icon: Icons.verified_outlined,
        color: AppColors.secondary,
        onTap: () => ref.read(dentalLabStatusFilterProvider.notifier).state = 'ready',
        isActive: ref.watch(dentalLabStatusFilterProvider) == 'ready',
      ),
      _KpiCard(
        title: 'Delivered',
        count: '${stats.delivered}',
        icon: Icons.check_circle_outline,
        color: Colors.green.shade700,
        onTap: () => ref.read(dentalLabStatusFilterProvider.notifier).state = 'delivered',
        isActive: ref.watch(dentalLabStatusFilterProvider) == 'delivered',
      ),
    ];

    if (isDesktop) {
      return Row(
        children: cards
            .map((c) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: c,
                  ),
                ))
            .toList(),
      );
    } else {
      return Column(
        children: cards
            .map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: c,
                ))
            .toList(),
      );
    }
  }

  Widget _buildControlsHeader(bool isDesktop, String currentFilter) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Search input
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by Case #, patient name, restoration...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              ref.read(dentalLabSearchQueryProvider.notifier).state = '';
                              setState(() {});
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onChanged: (val) {
                    ref.read(dentalLabSearchQueryProvider.notifier).state = val;
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // Add button
              FilledButton.icon(
                onPressed: _openCreateDialog,
                icon: const Icon(Icons.add, size: 18),
                label: Text(isDesktop ? 'New Lab Case' : 'New'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // Status filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('All Cases', 'all', currentFilter),
                const SizedBox(width: 8),
                _buildFilterChip('Processing', 'processing', currentFilter),
                const SizedBox(width: 8),
                _buildFilterChip('Ready', 'ready', currentFilter),
                const SizedBox(width: 8),
                _buildFilterChip('Delivered', 'delivered', currentFilter),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, String current) {
    final selected = current == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        ref.read(dentalLabStatusFilterProvider.notifier).state = value;
      },
      selectedColor: AppColors.primaryContainer.withValues(alpha: 0.25),
      labelStyle: TextStyle(
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        color: selected ? AppColors.primary : AppColors.onSurfaceVariant,
        fontSize: 13,
      ),
    );
  }

  Widget _buildCasesCard(List<DentalLabModel> items, bool isDesktop) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.outlineVariant),
        itemBuilder: (context, index) {
          final item = items[index];
          return _DentalLabCaseRow(
            item: item,
            isDesktop: isDesktop,
            onTransitionStatus: (status) => _transitionStatus(item, status),
            onEdit: () => _openEditDialog(item),
            onEditAppointment: () => _editLinkedAppointment(item),
            onDelete: () => _deleteCase(item),
            onWhatsApp: () => DentalLabWhatsAppDialog.show(context, item),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.biotech_outlined,
              size: 56,
              color: AppColors.outline.withValues(alpha: 0.4),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('No Dental Lab Cases Found', style: AppTypography.headlineMd),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'No cases match the active filter or search query. Click "New Lab Case" to log an order.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: _openCreateDialog,
              icon: const Icon(Icons.add),
              label: const Text('Create Dental Lab Case'),
            ),
          ],
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.count,
    required this.icon,
    required this.color,
    required this.onTap,
    this.isActive = false,
  });

  final String title;
  final String count;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.1) : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(
            color: isActive ? color : AppColors.outlineVariant,
            width: isActive ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    count,
                    style: AppTypography.headlineMd.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                      color: color,
                    ),
                  ),
                  Text(
                    title,
                    style: AppTypography.labelCaps.copyWith(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 11,
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
}

class _DentalLabCaseRow extends StatelessWidget {
  const _DentalLabCaseRow({
    required this.item,
    required this.isDesktop,
    required this.onTransitionStatus,
    required this.onEdit,
    required this.onEditAppointment,
    required this.onDelete,
    required this.onWhatsApp,
  });

  final DentalLabModel item;
  final bool isDesktop;
  final ValueChanged<String> onTransitionStatus;
  final VoidCallback onEdit;
  final VoidCallback onEditAppointment;
  final VoidCallback onDelete;
  final VoidCallback onWhatsApp;

  Color _getStatusBg() {
    if (item.isProcessing) return Colors.amber.shade100;
    if (item.isReady) return AppColors.secondaryContainer.withValues(alpha: 0.3);
    return Colors.green.shade100;
  }

  Color _getStatusFg() {
    if (item.isProcessing) return Colors.amber.shade900;
    if (item.isReady) return AppColors.secondary;
    return Colors.green.shade800;
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy');
    final sentStr = dateFormat.format(item.sentDate);
    final readyStr = item.readyDate != null ? dateFormat.format(item.readyDate!) : '-';
    final deliveredStr = item.deliveredDate != null ? dateFormat.format(item.deliveredDate!) : '-';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left Status Indicator Strip
          Container(
            width: 4,
            height: 48,
            decoration: BoxDecoration(
              color: _getStatusFg(),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),

          // Case ID & Type
          Expanded(
            flex: isDesktop ? 3 : 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      item.caseNumber,
                      style: AppTypography.dataMono.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getStatusBg(),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        item.statusLabel.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: _getStatusFg(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  item.caseType,
                  style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w600),
                ),
                if (item.remarks != null && item.remarks!.isNotEmpty)
                  Text(
                    'Notes: ${item.remarks!}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),

          // Patient Info
          Expanded(
            flex: isDesktop ? 3 : 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person_outline, size: 14, color: AppColors.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        item.patientName ?? 'Unknown Patient',
                        style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'ID: ${item.patientNumber ?? "-"} • Mobile: ${item.patientMobile ?? "None"}',
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Dates Column (desktop only)
          if (isDesktop)
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sent: $sentStr', style: const TextStyle(fontSize: 12)),
                  if (item.readyDate != null)
                    Text('Ready: $readyStr', style: TextStyle(fontSize: 11, color: AppColors.secondary)),
                  if (item.appointmentDate != null)
                    Text(
                      'Appt: ${item.formattedAppointmentDateTime ?? item.formattedAppointmentDate ?? '-'}',
                      style: TextStyle(fontSize: 11, color: AppColors.primary),
                    ),
                  if (item.deliveredDate != null)
                    Text('Delivered: $deliveredStr', style: TextStyle(fontSize: 11, color: Colors.green.shade700)),
                ],
              ),
            ),

          // Actions
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Advance to Ready
              if (item.isProcessing)
                OutlinedButton.icon(
                  onPressed: () => onTransitionStatus('ready'),
                  icon: const Icon(Icons.verified_outlined, size: 14),
                  label: const Text('Mark Ready'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.secondary,
                    side: const BorderSide(color: AppColors.secondary),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                ),

              // Advance to Delivered
              if (item.isReady) ...[
                IconButton(
                  icon: const Icon(Icons.message, color: Color(0xFF25D366), size: 20),
                  tooltip: 'Patient WhatsApp Notice',
                  onPressed: onWhatsApp,
                ),
                OutlinedButton.icon(
                  onPressed: () => onTransitionStatus('delivered'),
                  icon: const Icon(Icons.check_circle_outline, size: 14),
                  label: const Text('Mark Delivered'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.green.shade700,
                    side: BorderSide(color: Colors.green.shade700),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],

              if (item.isDelivered)
                Tooltip(
                  message: 'Case delivered to patient',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                      const SizedBox(width: 4),
                      Text(
                        'Completed',
                        style: TextStyle(fontSize: 11, color: Colors.green.shade800, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),

              const SizedBox(width: 4),

              // More options menu
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20, color: AppColors.onSurfaceVariant),
                onSelected: (val) {
                  if (val == 'edit') onEdit();
                  if (val == 'edit_appointment') onEditAppointment();
                  if (val == 'whatsapp') onWhatsApp();
                  if (val == 'delete') onDelete();
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 16),
                        SizedBox(width: 8),
                        Text('Edit Case'),
                      ],
                    ),
                  ),
                  if (item.appointmentId != null)
                    const PopupMenuItem(
                      value: 'edit_appointment',
                      child: Row(
                        children: [
                          Icon(Icons.calendar_month_outlined, size: 16),
                          SizedBox(width: 8),
                          Text('Edit Linked Appointment'),
                        ],
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'whatsapp',
                    child: Row(
                      children: [
                        Icon(Icons.message_outlined, size: 16, color: Color(0xFF25D366)),
                        SizedBox(width: 8),
                        Text('WhatsApp Notice'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 16, color: AppColors.error),
                        SizedBox(width: 8),
                        Text('Delete Case', style: TextStyle(color: AppColors.error)),
                      ],
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
}
