import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../appointments/models/department_doctor_config.dart';
import '../models/whatsapp_appointment_request.dart';
import '../providers/whatsapp_appointment_provider.dart';
import '../screens/whatsapp_inbox_screen.dart';
import 'whatsapp_admin_settings_card.dart';

class WhatsAppRequestsView extends ConsumerStatefulWidget {
  const WhatsAppRequestsView({super.key});

  @override
  ConsumerState<WhatsAppRequestsView> createState() => _WhatsAppRequestsViewState();
}

class _WhatsAppRequestsViewState extends ConsumerState<WhatsAppRequestsView> {
  String _selectedStatus = 'pending_review';
  String _selectedDepartment = 'all';
  bool _showDaemonSettings = false;

  @override
  Widget build(BuildContext context) {
    final requestsAsync = ref.watch(whatsappRequestsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFilterHeader(),
        const Divider(height: 1, color: AppColors.outlineVariant),
        if (_showDaemonSettings) ...[
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.45,
            ),
            child: const SingleChildScrollView(
              padding: EdgeInsets.all(AppSpacing.md),
              child: WhatsAppAdminSettingsCard(),
            ),
          ),
          const Divider(height: 1, color: AppColors.outlineVariant),
        ],
        Expanded(
          child: requestsAsync.when(
            loading: () => const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: AppSpacing.md),
                  Text('Loading WhatsApp appointment requests...'),
                ],
              ),
            ),
            error: (err, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Failed to load requests',
                      style: AppTypography.headlineMd.copyWith(fontSize: 18, color: AppColors.error),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(err.toString(), textAlign: TextAlign.center),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton.icon(
                      onPressed: () => ref
                          .read(whatsappRequestsProvider.notifier)
                          .loadRequests(status: _selectedStatus, department: _selectedDepartment),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
            data: (requests) {
              if (requests.isEmpty) {
                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.mark_chat_read_outlined,
                            size: 56,
                            color: AppColors.onSurfaceVariant,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'No WhatsApp requests found',
                            style: AppTypography.headlineMd.copyWith(
                              fontSize: 18,
                              color: AppColors.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            _selectedStatus == 'pending_review'
                                ? 'All incoming WhatsApp booking requests have been reviewed!'
                                : 'No requests match the selected status and department filters.',
                            style: AppTypography.bodySm.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () async {
                  await ref
                      .read(whatsappRequestsProvider.notifier)
                      .loadRequests(status: _selectedStatus, department: _selectedDepartment);
                },
                child: ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: requests.length,
                  separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
                  itemBuilder: (ctx, index) {
                    final req = requests[index];
                    return _WhatsAppRequestCard(request: req);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFilterHeader() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Filter Chips Section: Horizontally scrollable
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.filter_list, size: 16, color: AppColors.primary),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      'Status:',
                      style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(width: AppSpacing.xs),
                _statusChip('Pending Review', 'pending_review'),
                const SizedBox(width: 4),
                _statusChip('Approved', 'approved'),
                const SizedBox(width: 4),
                _statusChip('Rejected', 'rejected'),
                const SizedBox(width: 4),
                _statusChip('All', 'all'),
                const SizedBox(width: AppSpacing.md),
                Container(width: 1, height: 20, color: AppColors.outlineVariant),
                const SizedBox(width: AppSpacing.md),
                Text(
                  'Dept:',
                  style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w600, fontSize: 12),
                ),
                const SizedBox(width: AppSpacing.xs),
                _deptChip('All', 'all'),
                const SizedBox(width: 4),
                _deptChip('Eye', 'eye'),
                const SizedBox(width: 4),
                _deptChip('Dental', 'dental'),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // Action Buttons Section
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const WhatsAppInboxScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.forum_outlined, size: 16),
                label: const Text('Shared Inbox'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() => _showDaemonSettings = !_showDaemonSettings);
                },
                icon: Icon(
                  _showDaemonSettings ? Icons.close : Icons.tune_outlined,
                  size: 16,
                ),
                label: Text(_showDaemonSettings ? 'Hide Settings' : 'Bot & Outbox Settings'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String label, String value) {
    final isSelected = _selectedStatus == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _selectedStatus = value);
          ref
              .read(whatsappRequestsProvider.notifier)
              .loadRequests(status: value, department: _selectedDepartment);
        }
      },
      selectedColor: AppColors.primaryContainer,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        color: isSelected ? AppColors.primary : AppColors.onSurface,
      ),
    );
  }

  Widget _deptChip(String label, String value) {
    final isSelected = _selectedDepartment == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _selectedDepartment = value);
          ref
              .read(whatsappRequestsProvider.notifier)
              .loadRequests(status: _selectedStatus, department: value);
        }
      },
      selectedColor: AppColors.secondaryContainer,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        color: isSelected ? AppColors.secondary : AppColors.onSurface,
      ),
    );
  }
}

class _WhatsAppRequestCard extends ConsumerStatefulWidget {
  final WhatsAppAppointmentRequest request;

  const _WhatsAppRequestCard({required this.request});

  @override
  ConsumerState<_WhatsAppRequestCard> createState() => _WhatsAppRequestCardState();
}

class _WhatsAppRequestCardState extends ConsumerState<_WhatsAppRequestCard> {
  bool _isProcessing = false;

  String _formatTime(String rawTime) {
    try {
      final parts = rawTime.split(':');
      var hour = int.parse(parts[0]);
      final minute = parts[1];
      final ampm = hour >= 12 ? 'PM' : 'AM';
      hour = hour % 12;
      if (hour == 0) hour = 12;
      final hourStr = hour < 10 ? '0$hour' : '$hour';
      return '$hourStr:$minute $ampm';
    } catch (_) {
      return rawTime;
    }
  }

  void _showApproveDialog() {
    final isEye = widget.request.department.toLowerCase() == 'eye';
    final doctors = isEye
        ? DepartmentDoctorConfig.confirmedEyeDoctors
        : DepartmentDoctorConfig.confirmedDentalDoctors;

    DepartmentDoctor? selectedDoctor = doctors.isNotEmpty ? doctors.first : null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: AppColors.secondary, size: 24),
              const SizedBox(width: AppSpacing.sm),
              const Text('Approve WhatsApp Booking'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Patient: ${widget.request.patientName} (${widget.request.patientPhone})',
                style: AppTypography.bodyMd.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Department: ${widget.request.department.toUpperCase()} Clinic',
                style: AppTypography.bodySm,
              ),
              Text(
                'Requested: ${DateFormat('EEE, dd MMM yyyy').format(widget.request.requestedDate)} at ${_formatTime(widget.request.requestedTime)} (${widget.request.durationMinutes} min)',
                style: AppTypography.bodySm,
              ),
              const SizedBox(height: AppSpacing.md),
              const Divider(),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Assign Attending Doctor:',
                style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.xs),
              DropdownButtonFormField<DepartmentDoctor>(
                initialValue: selectedDoctor,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                ),
                items: doctors.map((doc) {
                  return DropdownMenuItem<DepartmentDoctor>(
                    value: doc,
                    child: Text('${doc.fullName} (${doc.specialty ?? doc.department})'),
                  );
                }).toList(),
                onChanged: (val) {
                  setDialogState(() => selectedDoctor = val);
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'ℹ️ Approving will promote this into clinical appointments and send an automated WhatsApp confirmation.',
                style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant, fontSize: 11),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.secondary),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.of(ctx).pop();
                setState(() => _isProcessing = true);

                final result = await ref.read(whatsappRequestsProvider.notifier).approveRequest(
                      requestId: widget.request.id,
                      doctorId: selectedDoctor?.id.isNotEmpty == true ? selectedDoctor?.id : null,
                      doctorName: selectedDoctor?.fullName,
                    );

                if (mounted) {
                  setState(() => _isProcessing = false);
                  if (result['success'] == true) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('Appointment approved for ${widget.request.patientName}!'),
                        backgroundColor: AppColors.secondary,
                      ),
                    );
                  } else {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('Approval failed: ${result['message']}'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                }
              },
              child: const Text('Confirm & Approve'),
            ),
          ],
        ),
      ),
    );
  }

  void _showRejectDialog() {
    final reasonController = TextEditingController(text: 'Selected slot is no longer available.');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.cancel_outlined, color: AppColors.error, size: 24),
            const SizedBox(width: AppSpacing.sm),
            const Text('Reject Request'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Patient: ${widget.request.patientName} (${widget.request.patientPhone})',
              style: AppTypography.bodyMd.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text('Reason for rejection (will be communicated to patient):'),
            const SizedBox(height: AppSpacing.xs),
            TextField(
              controller: reasonController,
              maxLines: 2,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Enter rejection reason...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) return;

              final messenger = ScaffoldMessenger.of(context);
              Navigator.of(ctx).pop();
              setState(() => _isProcessing = true);

              final result = await ref
                  .read(whatsappRequestsProvider.notifier)
                  .rejectRequest(requestId: widget.request.id, reason: reason);

              if (mounted) {
                setState(() => _isProcessing = false);
                if (result['success'] == true) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Request rejected for ${widget.request.patientName}.'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                } else {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Rejection failed: ${result['message']}'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            child: const Text('Reject Request'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final req = widget.request;
    final isEye = req.department.toLowerCase() == 'eye';
    final deptColor = isEye ? AppColors.primary : AppColors.secondary;
    final dateFormatted = DateFormat('EEE, dd MMM yyyy').format(req.requestedDate);
    final timeFormatted = _formatTime(req.requestedTime);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: req.isPending ? AppColors.outlineVariant : Colors.transparent,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: deptColor.withValues(alpha: 0.15),
                  child: Icon(
                    isEye ? Icons.visibility_outlined : Icons.health_and_safety_outlined,
                    color: deptColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              req.patientName,
                              style: AppTypography.headlineMd.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: deptColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              req.department.toUpperCase(),
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: deptColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.chat_bubble_outline, size: 12, color: Color(0xFF25D366)),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              req.patientPhone,
                              style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                _buildStatusBadge(req),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.event_outlined, size: 16, color: AppColors.primary),
                            const SizedBox(width: AppSpacing.xs),
                            Flexible(
                              child: Text(
                                dateFormatted,
                                style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.schedule_outlined, size: 16, color: AppColors.primary),
                            const SizedBox(width: AppSpacing.xs),
                            Flexible(
                              child: Text(
                                '$timeFormatted (${req.durationMinutes} min)',
                                style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            if (req.isRejected && req.staffRemarks != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Rejection Reason: ${req.staffRemarks}',
                style: AppTypography.bodySm.copyWith(color: AppColors.error, fontStyle: FontStyle.italic),
              ),
            ],
            if (req.isApproved && req.promotedAppointmentId != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                '✓ Promoted to Appointment ID: ${req.promotedAppointmentId}',
                style: AppTypography.bodySm.copyWith(color: AppColors.secondary, fontWeight: FontWeight.w500),
              ),
            ],
            if (req.isPending) ...[
              const SizedBox(height: AppSpacing.md),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (_isProcessing)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else ...[
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
                      ),
                      onPressed: _showRejectDialog,
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Reject'),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.secondary),
                      onPressed: _showApproveDialog,
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Approve & Book'),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(WhatsAppAppointmentRequest req) {
    Color bg;
    Color fg;
    String text;

    if (req.isPending) {
      bg = Colors.amber.shade100;
      fg = Colors.amber.shade900;
      text = 'Pending';
    } else if (req.isApproved) {
      bg = Colors.green.shade100;
      fg = Colors.green.shade900;
      text = 'Approved';
    } else if (req.isRejected) {
      bg = Colors.red.shade100;
      fg = Colors.red.shade900;
      text = 'Rejected';
    } else {
      bg = Colors.grey.shade200;
      fg = Colors.grey.shade800;
      text = req.status.toUpperCase();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}
