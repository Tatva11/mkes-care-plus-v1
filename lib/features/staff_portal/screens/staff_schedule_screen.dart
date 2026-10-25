import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../appointments/models/appointment_model.dart';
import '../../appointments/providers/appointment_provider.dart';
import '../../appointments/widgets/appointment_form_dialog.dart';
import '../../auth/providers/auth_provider.dart';
import '../../billing/models/billing_invoice_model.dart';
import '../../billing/screens/create_invoice_screen.dart';
import '../../eye/models/eye_surgery_model.dart';
import '../../eye/providers/eye_surgery_provider.dart';
import '../../eye/screens/eye_surgery_screen.dart';
import '../../patients/models/patient_model.dart';
import '../../department/providers/departments_provider.dart';
import '../../staff/models/shift_configuration.dart';
import '../../staff/providers/attendance_provider.dart';
import '../../whatsapp/providers/whatsapp_appointment_provider.dart';
import '../../whatsapp/widgets/whatsapp_requests_view.dart';

class StaffScheduleScreen extends ConsumerStatefulWidget {
  const StaffScheduleScreen({super.key});

  @override
  ConsumerState<StaffScheduleScreen> createState() =>
      _StaffScheduleScreenState();
}

class _StaffScheduleScreenState extends ConsumerState<StaffScheduleScreen> {
  final DateTime _selectedDate = DateTime.now();
  String _selectedDepartment =
      'all'; // 'all', 'eye', 'dental', 'it', 'rental', 'common'

  Future<void> _handleStatusChange(
      AppointmentModel appointment, String newStatus) async {
    if (newStatus.toLowerCase() == 'completed') {
      if (!appointment.isPresent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Cannot complete visit: Patient must be marked present first.'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
      if (!appointment.isBilled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Cannot complete visit: Please create a Billing invoice or confirm as a No-Charge visit first.'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
    }

    await ref
        .read(appointmentsNotifierProvider.notifier)
        .updateStatus(appointment.id, newStatus);

    if (newStatus.toLowerCase() == 'completed' ||
        newStatus.toLowerCase() == 'cancelled') {
      _promptScheduleNextAppointment(appointment, newStatus);
    }
  }

  Future<void> _handleMarkPresent(AppointmentModel appointment) async {
    if (appointment.isPresent) return;

    await ref
        .read(appointmentsNotifierProvider.notifier)
        .updateStatus(appointment.id, 'waiting');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${appointment.patientName ?? "Patient"} marked present. Ready for Billing.'),
          backgroundColor: AppColors.secondary,
        ),
      );
    }
  }

  Future<void> _handleOpenBilling(AppointmentModel appointment) async {
    final patient = appointment.patient ??
        (appointment.patientId != null
            ? PatientModel(
                id: appointment.patientId!,
                patientNumber: appointment.patientNumber ?? '',
                name: appointment.patientName ?? 'Patient',
                department: appointment.department,
                createdAt: appointment.createdAt,
                updatedAt: appointment.updatedAt,
              )
            : null);

    final createdInvoice =
        await Navigator.of(context).push<BillingInvoiceModel>(
      MaterialPageRoute(
        builder: (_) => CreateInvoiceScreen(
          initialPatient: patient,
          initialDepartment: appointment.department,
        ),
      ),
    );

    if (createdInvoice != null && mounted) {
      final currentNotes = appointment.notes ?? '';
      final tag = '[BILLED: ${createdInvoice.invoiceNumber}]';
      final updatedNotes = currentNotes.isEmpty ? tag : '$currentNotes | $tag';

      await ref.read(appointmentsNotifierProvider.notifier).updateAppointment(
        appointment.id,
        {'notes': updatedNotes},
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Invoice ${createdInvoice.invoiceNumber} recorded for ${appointment.patientName ?? "Patient"}. Visit can now be completed.'),
          backgroundColor: AppColors.primary,
        ),
      );
    }
  }

  Future<void> _handleMarkNoCharge(AppointmentModel appointment) async {
    final reasonController =
        TextEditingController(text: 'Routine Consultation / Follow-up');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm No-Charge Visit'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Confirm that no billing charge is required for ${appointment.patientName ?? "Patient"}:',
              style: AppTypography.bodySm,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason for No-Charge',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm No-Charge'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final reason = reasonController.text.trim();
      final currentNotes = appointment.notes ?? '';
      final tag = '[NO_CHARGE: ${reason.isEmpty ? "No-Charge Visit" : reason}]';
      final updatedNotes = currentNotes.isEmpty ? tag : '$currentNotes | $tag';

      await ref.read(appointmentsNotifierProvider.notifier).updateAppointment(
        appointment.id,
        {'notes': updatedNotes},
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Marked as no-charge visit for ${appointment.patientName ?? "Patient"}. Visit can now be completed.'),
          backgroundColor: AppColors.primary,
        ),
      );
    }
  }

  void _handleReschedule(AppointmentModel appointment) {
    showDialog(
      context: context,
      builder: (_) => AppointmentFormDialog(
        existingAppointment: appointment,
      ),
    );
  }

  void _openNewAppointmentDialog({
    DateTime? initialDate,
    String? initialPatientId,
    String? initialPatientName,
    String initialType = 'regular',
  }) {
    showDialog(
      context: context,
      builder: (context) => AppointmentFormDialog(
        initialDate: initialDate,
        initialPatientId: initialPatientId,
        initialPatientName: initialPatientName,
        initialAppointmentType: initialType,
      ),
    );
  }

  void _openWhatsAppRequestsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.chat_bubble_outline,
                          color: Color(0xFF25D366)),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'WhatsApp Booking Requests',
                        style: AppTypography.headlineMd
                            .copyWith(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            const Expanded(child: WhatsAppRequestsView()),
          ],
        ),
      ),
    );
  }

  void _promptScheduleNextAppointment(
      AppointmentModel appointment, String triggerReason) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        // Ensure content is never hidden behind the keyboard.
        final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
        return Container(
          padding: EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            top: AppSpacing.lg,
            bottom: bottomInset + AppSpacing.lg,
          ),
          decoration: const BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppSpacing.radiusXl)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    triggerReason == 'Completed'
                        ? Icons.check_circle_outline
                        : Icons.cancel_outlined,
                    color: triggerReason == 'Completed'
                        ? AppColors.primaryContainer
                        : AppColors.error,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'Appointment $triggerReason',
                    style: AppTypography.headlineMd,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Prompt follow-up for ${appointment.patientName ?? "Patient"} (${appointment.patientNumber ?? "Unknown ID"})',
                style: AppTypography.bodySm
                    .copyWith(color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.md),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.md),
              Text('Schedule Next Appointment:',
                  style: AppTypography.labelCaps
                      .copyWith(color: AppColors.primary)),
              const SizedBox(height: AppSpacing.sm),

              // Option 1: Tomorrow
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  side: const BorderSide(color: AppColors.outlineVariant),
                ),
                leading: const Icon(Icons.today, color: AppColors.primary),
                title: const Text('Tomorrow'),
                subtitle: const Text('Schedule for Aug 4, 2026'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  _openNewAppointmentDialog(
                    initialDate: DateTime.now().add(const Duration(days: 1)),
                    initialPatientId: appointment.patientId,
                    initialPatientName: appointment.patientName,
                    initialType: 'follow_up',
                  );
                },
              ),
              const SizedBox(height: AppSpacing.xs),

              // Option 2: Next Week
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  side: const BorderSide(color: AppColors.outlineVariant),
                ),
                leading:
                    const Icon(Icons.date_range, color: AppColors.secondary),
                title: const Text('Next Week'),
                subtitle: const Text('Schedule for Aug 10, 2026'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  _openNewAppointmentDialog(
                    initialDate: DateTime.now().add(const Duration(days: 7)),
                    initialPatientId: appointment.patientId,
                    initialPatientName: appointment.patientName,
                    initialType: 'follow_up',
                  );
                },
              ),
              const SizedBox(height: AppSpacing.xs),

              // Option 3: Schedule Later
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  side: const BorderSide(color: AppColors.outlineVariant),
                ),
                leading:
                    const Icon(Icons.edit_calendar, color: AppColors.tertiary),
                title: const Text('Schedule Later'),
                subtitle: const Text('Select a custom future date'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  Navigator.pop(context);
                  final pickedDate = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now().add(const Duration(days: 14)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (pickedDate != null) {
                    _openNewAppointmentDialog(
                      initialDate: pickedDate,
                      initialPatientId: appointment.patientId,
                      initialPatientName: appointment.patientName,
                      initialType: 'follow_up',
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showWhatsAppReminderModal(AppointmentModel item) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg)),
          titlePadding: const EdgeInsets.all(AppSpacing.md),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.xs),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Color(0xFF25D366),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.message, color: Colors.white, size: 18),
              ),
              const SizedBox(width: AppSpacing.xs),
              const Expanded(
                child: Text('Automated WhatsApp Reminder',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: const Color(0xFF25D366).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    border: Border.all(
                        color: const Color(0xFF25D366).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome,
                          color: Color(0xFF128C7E), size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Visiting Doctor Clinical Context automatically attached.',
                          style: AppTypography.labelCaps.copyWith(
                              color: const Color(0xFF128C7E), fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECE5DD),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '📋 *VISITING DOCTOR CLINICAL SUMMARY*',
                        style: AppTypography.labelCaps.copyWith(
                            color: const Color(0xFF075E54),
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                          '👤 *Patient Name:* ${item.patientName ?? "Unknown"} (${item.patientNumber ?? "Unknown ID"})',
                          style: AppTypography.bodySm),
                      Text(
                          '📅 *Appointment:* Today @ ${item.formattedTime} (${item.room ?? "Room 102"})',
                          style: AppTypography.bodySm),
                      Text(
                          '👨‍⚕️ *Visiting Specialist:* ${item.doctorName ?? "Visiting Specialist"} (${item.specialty ?? "Retina Specialist"})',
                          style: AppTypography.bodySm),
                      const Divider(height: 12),
                      Text(
                          '🔍 *Previous Visit Summary:* ${item.previousVisitSummary ?? "Diabetic eye screening"}',
                          style: AppTypography.bodySm),
                      Text(
                          '💉 *Previous Treatment:* ${item.previousTreatment ?? "Dilated Macular Exam"}',
                          style: AppTypography.bodySm),
                      Text(
                          '🩺 *Current Diagnosis:* ${item.currentDiagnosis ?? "Mild central macular edema flag; IOP 17 mmHg"}',
                          style: AppTypography.bodySm),
                      Text(
                          '🎯 *Planned Treatment:* ${item.plannedTreatment ?? "High-definition OCT scan"}',
                          style: AppTypography.bodySm),
                      Text('📌 *Important Notes:* "${item.doctorNotes ?? ""}"',
                          style: AppTypography.bodySm
                              .copyWith(fontStyle: FontStyle.italic)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: const Color(0xFF128C7E),
                    behavior: SnackBarBehavior.floating,
                    content: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.white),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                              'WhatsApp reminder with clinical summary sent to ${item.doctorName}'),
                        ),
                      ],
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.send, size: 16),
              label: const Text('Send WhatsApp Reminder'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 768.0;
    final currentUser = ref.watch(currentUserProvider);
    final appointmentsAsync = ref.watch(appointmentsNotifierProvider);
    final appointments = appointmentsAsync.value ?? initialFallbackAppointments;

    // Assigned Eye Surgeries on staff's schedule (Requirement 5)
    final allSurgeries =
        ref.watch(eyeSurgeryListProvider).valueOrNull ?? const [];
    final staffSurgeries = allSurgeries.where((s) {
      if (currentUser == null) return false;
      if (s.assignedStaffId != currentUser.id) return false;
      if (!EyeSurgeryModel.isSameCalendarDay(s.surgeryDate, _selectedDate)) {
        return false;
      }
      if (s.status.toLowerCase() == 'cancelled') return false;
      return true;
    }).toList();

    // Unified schedule items sorted chronologically by actual scheduled time (Requirement 5 & 8)
    final scheduleItems = <_ScheduleTimelineEntry>[
      ...appointments.map((a) => _ScheduleTimelineEntry.appointment(a)),
      ...staffSurgeries.map((s) => _ScheduleTimelineEntry.surgery(s)),
    ];
    scheduleItems.sort((a, b) {
      final timeComp = a.timeMinutes.compareTo(b.timeMinutes);
      if (timeComp != 0) return timeComp;
      final createdComp = a.createdAt.compareTo(b.createdAt);
      if (createdComp != 0) return createdComp;
      return a.id.compareTo(b.id);
    });

    // Department options & staff access control (Part 5)
    final currentProfile = ref.watch(currentProfileProvider).valueOrNull;
    final staffDept = currentProfile?.department?.trim().toLowerCase();
    final isRestrictedStaff = currentProfile != null &&
        currentProfile.role.toLowerCase() != 'admin' &&
        staffDept != null &&
        staffDept.isNotEmpty &&
        (staffDept == 'eye' || staffDept == 'dental');

    final departmentsAsync = ref.watch(departmentsProvider);
    final dbDepts = departmentsAsync.valueOrNull ?? [];

    final Map<String, String> departmentOptions = {
      'all': 'All Departments',
      'eye': 'Eye',
      'dental': 'Dental',
    };

    for (final d in dbDepts) {
      if (!d.isActive) continue;
      final key = d.name.trim().toLowerCase();
      if (key == 'it') departmentOptions['it'] = 'IT';
      if (key.contains('rent')) departmentOptions['rental'] = 'Rental';
      if (key.contains('common') || key.contains('share')) {
        departmentOptions['common'] = 'Common / Shared';
      }
    }
    if (!departmentOptions.containsKey('common')) {
      departmentOptions['common'] = 'Common / Shared';
    }

    // Filter by canonical department while strictly enforcing role/department authorization
    final filteredScheduleItems = scheduleItems.where((entry) {
      if (isRestrictedStaff && entry.canonicalDepartment != staffDept) {
        return false;
      }
      if (_selectedDepartment == 'all') return true;
      if (_selectedDepartment == 'common') {
        return entry.canonicalDepartment == 'common' ||
            entry.canonicalDepartment == 'shared';
      }
      return entry.canonicalDepartment == _selectedDepartment;
    }).toList();

    final formattedHeaderDate =
        'Today, ${DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate)}';

    // Dynamic AI scheduling tip grounded in verified schedule data (Issue 6)
    final String aiTipText;
    if (filteredScheduleItems.isEmpty) {
      aiTipText = _selectedDepartment == 'all'
          ? 'AI Tip: No consultations or procedures scheduled for this date. Clinical triage and patient queue remain ready for walk-in arrivals.'
          : 'AI Tip: No ${_selectedDepartment.toUpperCase()} consultations or procedures scheduled for this session.';
    } else {
      final validAppointments = filteredScheduleItems
          .where((i) => !i.isSurgery && i.appointment != null)
          .map((i) => i.appointment!)
          .toList();
      final validSurgeries = filteredScheduleItems
          .where((i) => i.isSurgery && i.surgery != null)
          .map((i) => i.surgery!)
          .toList();

      if (validAppointments.isNotEmpty) {
        final firstAppt = validAppointments.first;
        final doc = firstAppt.doctorName?.trim() ?? '';
        final hasDoctor =
            doc.isNotEmpty && !doc.toLowerCase().startsWith('select');
        final dept = firstAppt.department.trim().isNotEmpty
            ? '${firstAppt.department} Department'
            : 'Clinic';
        if (hasDoctor) {
          aiTipText =
              'AI Tip: $doc consults today in $dept starting at ${firstAppt.formattedTime}. ${validAppointments.length} appointment(s) scheduled for this session.';
        } else {
          aiTipText =
              'AI Tip: $dept consultations begin at ${firstAppt.formattedTime}. ${validAppointments.length} appointment(s) scheduled for this date.';
        }
      } else if (validSurgeries.isNotEmpty) {
        final firstSurgery = validSurgeries.first;
        aiTipText =
            'AI Tip: ${validSurgeries.length} Eye surgery procedure(s) scheduled for today. First case starts at ${_ScheduleTimelineEntry.formatSurgeryTime(firstSurgery.surgeryTime)}.';
      } else {
        aiTipText =
            'AI Tip: Schedule is confirmed. Please review patient history before upcoming consultations.';
      }
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(
          isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('My Schedule',
                          style: AppTypography.displayLg
                              .copyWith(color: AppColors.onBackground)),
                      const SizedBox(height: AppSpacing.xs),
                      Text(formattedHeaderDate,
                          style: AppTypography.bodyLg
                              .copyWith(color: AppColors.onSurfaceVariant)),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: _openWhatsAppRequestsSheet,
                  icon: const Icon(Icons.chat_bubble_outline,
                      size: 18, color: Color(0xFF25D366)),
                  label: Consumer(
                    builder: (context, ref, _) {
                      final pendingCount =
                          ref.watch(pendingWhatsAppRequestsCountProvider);
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('WhatsApp Requests'),
                          if (pendingCount > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade800,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$pendingCount',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton.icon(
                  onPressed: () => _openNewAppointmentDialog(),
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('Book Appointment'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (currentUser != null)
                  _StaffShiftHeaderBadge(
                    staffId: currentUser.id,
                    selectedDate: _selectedDate,
                  )
                else
                  const _UnassignedShiftBadge(),
              ],
            )
          else ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('My Schedule',
                    style: AppTypography.displayLg
                        .copyWith(color: AppColors.onBackground, fontSize: 28)),
                const SizedBox(height: AppSpacing.xs),
                Text(formattedHeaderDate,
                    style: AppTypography.bodyLg
                        .copyWith(color: AppColors.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _openNewAppointmentDialog(),
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: const Text('Book Appointment'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusMd),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (currentUser != null)
                  _StaffShiftHeaderBadge(
                    staffId: currentUser.id,
                    selectedDate: _selectedDate,
                  )
                else
                  const _UnassignedShiftBadge(),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openWhatsAppRequestsSheet,
                icon: const Icon(Icons.chat_bubble_outline,
                    size: 18, color: Color(0xFF25D366)),
                label: Consumer(
                  builder: (context, ref, _) {
                    final pendingCount =
                        ref.watch(pendingWhatsAppRequestsCountProvider);
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('WhatsApp Requests'),
                        if (pendingCount > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade800,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$pendingCount',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
          ],

          const SizedBox(height: AppSpacing.lg),

          // AI Scheduling Tip Card
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.secondaryContainer.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              border:
                  Border.all(color: AppColors.secondary.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome,
                    color: AppColors.secondary, size: 24),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    aiTipText,
                    style: AppTypography.bodyMd
                        .copyWith(color: AppColors.onSurface),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          // Appointment & Surgery Timeline Header with Department Filter (Part 5)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text("Today's Schedule", style: AppTypography.headlineMd),
              if (!isRestrictedStaff)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    border: Border.all(color: AppColors.outlineVariant),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      key: const Key('staff_schedule_department_dropdown'),
                      value: departmentOptions.containsKey(_selectedDepartment)
                          ? _selectedDepartment
                          : 'all',
                      icon: const Icon(Icons.filter_list,
                          size: 18, color: AppColors.primary),
                      isDense: true,
                      style: AppTypography.bodySm.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                      items: departmentOptions.entries.map((entry) {
                        return DropdownMenuItem<String>(
                          value: entry.key,
                          child: Text(entry.value),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedDepartment = val);
                        }
                      },
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // Horizontal department chips for quick one-tap filtering
          if (!isRestrictedStaff) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: departmentOptions.entries.map((entry) {
                  final isSelected = _selectedDepartment == entry.key;
                  return Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.xs),
                    child: FilterChip(
                      key: Key('staff_schedule_dept_chip_${entry.key}'),
                      label: Text(entry.value),
                      selected: isSelected,
                      selectedColor:
                          AppColors.primaryContainer.withValues(alpha: 0.2),
                      checkmarkColor: AppColors.primary,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.onSurfaceVariant,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      onSelected: (selected) {
                        setState(() =>
                            _selectedDepartment = selected ? entry.key : 'all');
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ] else ...[
            const SizedBox(height: AppSpacing.md),
          ],

          if (appointmentsAsync.isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: CircularProgressIndicator(),
              ),
            )
          else if (filteredScheduleItems.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.event_available,
                        size: 48, color: AppColors.outline),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _selectedDepartment == 'all'
                          ? 'No appointments or surgeries scheduled for today.'
                          : 'No ${_selectedDepartment.toUpperCase()} appointments or procedures scheduled for this session.',
                      style: AppTypography.bodyLg
                          .copyWith(color: AppColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          else
            ...filteredScheduleItems.map((entry) {
              if (entry.isSurgery) {
                return _buildSurgeryTimelineCard(entry.surgery!);
              }
              return _buildTimelineCard(entry.appointment!);
            }),
        ],
      ),
    );
  }

  Widget _buildTimelineCard(AppointmentModel item) {
    final patientDisplayName = item.patientName ?? 'Unknown Patient';
    final patientIdDisplay = item.patientNumber ?? 'Unknown ID';

    // Part 2: Display actual assigned doctor name instead of generic 'Doctor Appointment'
    final hasDoctor =
        item.doctorName != null && item.doctorName!.trim().isNotEmpty;
    final doctorDisplay =
        hasDoctor ? item.doctorName!.trim() : 'Doctor not assigned';
    final isFollowUp = item.appointmentType.toLowerCase().trim() == 'follow_up';
    final appointmentLabel = isFollowUp ? 'Follow-Up' : 'Consultation';
    final departmentLabel = item.department.trim().isNotEmpty
        ? '${item.department.toUpperCase()} Clinic'
        : 'Clinic';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              item.formattedTime,
              style: AppTypography.dataMono.copyWith(
                  fontWeight: FontWeight.bold, color: AppColors.primary),
            ),
          ),
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(top: 4, right: 12),
            decoration:
                BoxDecoration(shape: BoxShape.circle, color: item.statusColor),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                border: Border.all(
                  color: item.isVisitingDoctor
                      ? AppColors.secondary.withValues(alpha: 0.5)
                      : AppColors.outlineVariant,
                  width: item.isVisitingDoctor ? 1.5 : 1.0,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(patientDisplayName,
                                    style: AppTypography.bodyMd
                                        .copyWith(fontWeight: FontWeight.bold)),
                                const SizedBox(width: 8),
                                Text('($patientIdDisplay)',
                                    style: AppTypography.dataMono.copyWith(
                                        fontSize: 12,
                                        color: AppColors.outline)),
                                if (item.isVisitingDoctor) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.secondaryContainer
                                          .withValues(alpha: 0.3),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                          color: AppColors.secondary
                                              .withValues(alpha: 0.5)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.person_pin_outlined,
                                            size: 12,
                                            color: AppColors.secondary),
                                        const SizedBox(width: 4),
                                        Text(
                                          'VISITING DOCTOR',
                                          style: AppTypography.labelCaps
                                              .copyWith(
                                                  color: AppColors.secondary,
                                                  fontSize: 10),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            // Simplified department & appointment label
                            Text(
                              '$departmentLabel • $appointmentLabel',
                              style: AppTypography.bodySm
                                  .copyWith(color: AppColors.onSurfaceVariant),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            // Part 2: Display assigned doctor name or "Doctor not assigned"
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.person_pin_outlined,
                                  size: 14,
                                  color: hasDoctor
                                      ? AppColors.primary
                                      : AppColors.outline,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    doctorDisplay,
                                    style: AppTypography.bodySm.copyWith(
                                      color: hasDoctor
                                          ? AppColors.onSurface
                                          : AppColors.outline,
                                      fontWeight: hasDoctor
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                      fontStyle: hasDoctor
                                          ? FontStyle.normal
                                          : FontStyle.italic,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            if (item.isVisitingDoctor &&
                                item.doctorName != null &&
                                item.specialty != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                '${item.doctorName} (${item.specialty})',
                                style: AppTypography.bodySm.copyWith(
                                    color: AppColors.secondary,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: item.statusColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              item.statusLabel,
                              style: AppTypography.labelCaps
                                  .copyWith(color: item.statusColor),
                            ),
                          ),
                          if (item.isBilled) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border:
                                    Border.all(color: Colors.green.shade300),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.receipt_outlined,
                                      size: 10, color: Colors.green.shade800),
                                  const SizedBox(width: 4),
                                  Text(
                                    item.billingReference ?? 'Billed',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Divider(height: 1),
                  const SizedBox(height: AppSpacing.xs),

                  // Actions Row - Patient Visit Workflow: Mark Present -> Billing -> Mark Completed
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (item.isVisitingDoctor)
                        OutlinedButton.icon(
                          onPressed: () => _showWhatsAppReminderModal(item),
                          icon: const Icon(Icons.message,
                              size: 14, color: Color(0xFF128C7E)),
                          label: const Text('WhatsApp Reminder'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF128C7E),
                            side: const BorderSide(color: Color(0xFF25D366)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        )
                      else
                        Text(
                          'Visit Flow:',
                          style: AppTypography.labelCaps
                              .copyWith(color: AppColors.outline),
                        ),
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // STEP 1: Mark Present
                          if (!item.isPresent &&
                              item.status.toLowerCase() != 'completed' &&
                              item.status.toLowerCase() != 'cancelled')
                            FilledButton.tonalIcon(
                              onPressed: () => _handleMarkPresent(item),
                              icon: const Icon(Icons.person_pin_circle_outlined,
                                  size: 14),
                              label: const Text('Mark Present'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),

                          // STEP 2: Billing (Revealed after marked present)
                          if (item.isPresent &&
                              item.status.toLowerCase() != 'completed' &&
                              item.status.toLowerCase() != 'cancelled') ...[
                            if (!item.isBilled) ...[
                              FilledButton.icon(
                                onPressed: () => _handleOpenBilling(item),
                                icon: const Icon(Icons.receipt_long_outlined,
                                    size: 14),
                                label: const Text('Bill Patient'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                              OutlinedButton(
                                onPressed: () => _handleMarkNoCharge(item),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text('No-Charge Visit'),
                              ),
                            ] else ...[
                              OutlinedButton.icon(
                                onPressed: () => _handleOpenBilling(item),
                                icon: const Icon(Icons.check_circle,
                                    size: 14, color: Colors.green),
                                label: Text(
                                  'Billed (${item.billingReference ?? "Recorded"})',
                                  style: TextStyle(
                                      color: Colors.green.shade800,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side:
                                      BorderSide(color: Colors.green.shade400),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ],
                          ],

                          // STEP 3: Mark as Completed
                          if (item.status.toLowerCase() != 'completed' &&
                              item.status.toLowerCase() != 'cancelled')
                            TextButton.icon(
                              onPressed: (item.isPresent && item.isBilled)
                                  ? () => _handleStatusChange(item, 'completed')
                                  : () {
                                      final missingStep = !item.isPresent
                                          ? 'Mark patient present first'
                                          : 'Create an invoice or confirm no-charge first';
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                              'Cannot complete visit: $missingStep.'),
                                          backgroundColor: AppColors.error,
                                        ),
                                      );
                                    },
                              icon: Icon(
                                Icons.check_circle,
                                size: 14,
                                color: (item.isPresent && item.isBilled)
                                    ? AppColors.primaryContainer
                                    : AppColors.outlineVariant,
                              ),
                              label: Text(
                                'Mark Completed',
                                style: TextStyle(
                                  color: (item.isPresent && item.isBilled)
                                      ? AppColors.primaryContainer
                                      : AppColors.outline,
                                  fontWeight: (item.isPresent && item.isBilled)
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),

                          // Reschedule & Cancel
                          if (item.status.toLowerCase() != 'completed' &&
                              item.status.toLowerCase() != 'cancelled') ...[
                            TextButton.icon(
                              onPressed: () => _handleReschedule(item),
                              icon: const Icon(Icons.edit_calendar, size: 14),
                              label: const Text('Reschedule'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.onSurfaceVariant,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () =>
                                  _handleStatusChange(item, 'cancelled'),
                              icon: const Icon(Icons.cancel,
                                  size: 14, color: AppColors.error),
                              label: const Text('Cancel'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.error,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ],
                          if (item.status.toLowerCase() == 'missed') ...[
                            FilledButton.tonalIcon(
                              onPressed: () => _handleReschedule(item),
                              icon: const Icon(Icons.replay, size: 14),
                              label: const Text('Reschedule Missed'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSurgeryTimelineCard(EyeSurgeryModel surgery) {
    final patientDisplayName = surgery.patientName ?? 'Unknown Patient';
    final patientIdDisplay = surgery.patientNumber ?? 'Unknown ID';
    final surgeryTimeFormatted =
        _ScheduleTimelineEntry.formatSurgeryTime(surgery.surgeryTime);

    Color statusColor;
    String statusLabel;
    switch (surgery.status.toLowerCase()) {
      case 'discharged':
        statusColor = const Color(0xFF2E7D32);
        statusLabel = 'DISCHARGED';
        break;
      case 'in_surgery':
        statusColor = AppColors.primaryContainer;
        statusLabel = 'IN SURGERY';
        break;
      case 'pre_op':
        statusColor = AppColors.secondary;
        statusLabel = 'PRE-OP';
        break;
      case 'post_op':
        statusColor = const Color(0xFFE65100);
        statusLabel = 'POST-OP';
        break;
      case 'billing':
        statusColor = const Color(0xFF1565C0);
        statusLabel = 'BILLING';
        break;
      case 'cancelled':
        statusColor = AppColors.error;
        statusLabel = 'CANCELLED';
        break;
      default:
        statusColor = AppColors.primary;
        statusLabel = 'SCHEDULED';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              surgeryTimeFormatted,
              style: AppTypography.dataMono.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ),
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(top: 4, right: 12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor,
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  patientDisplayName,
                                  style: AppTypography.bodyMd.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '($patientIdDisplay)',
                                  style: AppTypography.dataMono.copyWith(
                                    fontSize: 12,
                                    color: AppColors.outline,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.person_outline,
                                          size: 12, color: AppColors.primary),
                                      const SizedBox(width: 4),
                                      Text(
                                        'ASSIGNED TO YOU',
                                        style: AppTypography.labelCaps.copyWith(
                                          color: AppColors.primary,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            // Requirement 6: Simplified department & surgery labels
                            Text(
                              'Eye Department Patient • Eye Surgery',
                              style: AppTypography.bodySm.copyWith(
                                color: AppColors.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${surgery.displaySurgeryType} (${surgery.eyeSide.toUpperCase()} Eye)',
                              style: AppTypography.bodySm.copyWith(
                                color: AppColors.primary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          statusLabel,
                          style: AppTypography.labelCaps.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Divider(height: 1),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Surgery Procedure',
                        style: AppTypography.labelCaps
                            .copyWith(color: AppColors.outline),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const EyeSurgeryScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.visibility_outlined, size: 14),
                        label: const Text('View Surgery Details'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleTimelineEntry {
  final bool isSurgery;
  final AppointmentModel? appointment;
  final EyeSurgeryModel? surgery;
  final int timeMinutes;
  final String formattedTime;
  final DateTime createdAt;
  final String id;

  _ScheduleTimelineEntry.appointment(AppointmentModel item)
      : isSurgery = false,
        appointment = item,
        surgery = null,
        timeMinutes = AppointmentModel.timeToMinutes(item.appointmentTime),
        formattedTime = item.formattedTime,
        createdAt = item.createdAt,
        id = item.id;

  _ScheduleTimelineEntry.surgery(EyeSurgeryModel item)
      : isSurgery = true,
        appointment = null,
        surgery = item,
        timeMinutes = AppointmentModel.timeToMinutes(item.surgeryTime ?? ''),
        formattedTime = formatSurgeryTime(item.surgeryTime),
        createdAt = item.createdAt,
        id = item.id;

  String get canonicalDepartment {
    if (isSurgery) return 'eye';
    final dept = appointment?.department.trim().toLowerCase() ?? '';
    if (dept.isEmpty) return '';
    if (dept.contains('eye')) return 'eye';
    if (dept.contains('dental')) return 'dental';
    if (dept.contains('it')) return 'it';
    if (dept.contains('rent')) return 'rental';
    if (dept.contains('common') || dept.contains('shared')) return 'common';
    return dept;
  }

  static String formatSurgeryTime(String? timeStr) {
    if (timeStr == null || timeStr.trim().isEmpty) return 'TBD';
    final minutes = AppointmentModel.timeToMinutes(timeStr);
    final hour = minutes ~/ 60;
    final minute = minutes % 60;
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '${hour12.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $period';
  }
}

class _StaffShiftHeaderBadge extends ConsumerWidget {
  const _StaffShiftHeaderBadge({
    required this.staffId,
    required this.selectedDate,
  });

  final String staffId;
  final DateTime selectedDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shiftAsync = ref.watch(staffAssignedShiftForDateProvider(
        (staffId: staffId, date: selectedDate)));
    final configsAsync = ref.watch(shiftConfigurationsProvider);

    return shiftAsync.when(
      data: (shift) {
        final configs = configsAsync.valueOrNull ??
            const [
              ShiftConfiguration.defaultMorning,
              ShiftConfiguration.defaultAfternoon,
            ];
        final morningConfig = configs.firstWhere(
          (c) => c.name == 'morning',
          orElse: () => ShiftConfiguration.defaultMorning,
        );
        final eveningConfig = configs.firstWhere(
          (c) =>
              c.name == 'afternoon' || c.name == 'evening' || c.name == 'night',
          orElse: () => ShiftConfiguration.defaultAfternoon,
        );

        IconData icon;
        Color color;
        String title;
        String timing;

        if (shift == 'morning') {
          icon = Icons.wb_sunny_outlined;
          color = AppColors.primaryContainer;
          title = 'MORNING SHIFT';
          timing = morningConfig.formattedTiming;
        } else if (shift == 'afternoon' ||
            shift == 'evening' ||
            shift == 'night') {
          icon = Icons.nights_stay_outlined;
          color = AppColors.secondary;
          title = 'EVENING SHIFT';
          timing = eveningConfig.formattedTiming;
        } else if (shift == 'both') {
          icon = Icons.all_inclusive;
          color = AppColors.primary;
          title = 'BOTH SHIFTS';
          timing =
              '${morningConfig.formattedStart} – ${eveningConfig.formattedEnd}';
        } else {
          icon = Icons.event_busy_outlined;
          color = AppColors.outline;
          title = 'NOT SCHEDULED';
          timing = 'No shift assigned';
        }

        return Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.labelCaps.copyWith(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    timing,
                    style: AppTypography.dataMono.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
      loading: () => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Text('Shift info unavailable', style: AppTypography.labelCaps),
      ),
    );
  }
}

class _UnassignedShiftBadge extends StatelessWidget {
  const _UnassignedShiftBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.event_busy_outlined,
              color: AppColors.outline, size: 20),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'NOT SCHEDULED',
                style: AppTypography.labelCaps.copyWith(
                  color: AppColors.outline,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'No shift assigned',
                style: AppTypography.dataMono.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.outline,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
