with open('lib/features/appointments/widgets/appointment_form_dialog.dart', 'r', encoding='utf-8') as f:
    text = f.read()

# 1. Past appointment check only for new appointments
old_past_check = '''    final isToday = _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
    if (isToday) {
      final slotDateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );
      if (slotDateTime.isBefore(now.subtract(const Duration(minutes: 1)))) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Cannot book an appointment in the past. Please select an upcoming valid time slot.'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
    }'''

new_past_check = '''    final isToday = _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
    if (!widget.isEditing && isToday) {
      final slotDateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );
      if (slotDateTime.isBefore(now.subtract(const Duration(minutes: 1)))) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Cannot book an appointment in the past. Please select an upcoming valid time slot.'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
    }'''

# 2. Preserve status when editing
old_status_edit = "'status': _selectedType == 'walk_in' ? 'waiting' : 'scheduled',"
new_status_edit = "'status': widget.existingAppointment!.status,"

# 3. Reload current date's appointments
old_reload = '''      await ref
          .read(appointmentsNotifierProvider.notifier)
          .loadTodayAppointments();'''

new_reload = '''      final currentViewDate =
          ref.read(appointmentsNotifierProvider.notifier).currentDate;
      await ref
          .read(appointmentsNotifierProvider.notifier)
          .loadAppointmentsForDate(currentViewDate);'''

# Apply replacements
if old_past_check in text:
    text = text.replace(old_past_check, new_past_check)
elif old_past_check.replace('\n', '\r\n') in text:
    text = text.replace(old_past_check.replace('\n', '\r\n'), new_past_check.replace('\n', '\r\n'))

# Only replace old_status_edit inside the isEditing block
old_updates_block = '''        final updates = <String, dynamic>{
          'patient_id': _selectedPatientId,
          'department': _selectedDepartment,
          'doctor_id': DepartmentDoctorConfig.isValidUuid(_selectedDoctorId)
              ? _selectedDoctorId
              : null,
          'appointment_date': _selectedDate.toIso8601String().split('T').first,
          'appointment_time': _formatTimeOfDay(_selectedTime),
          'appointment_type': _selectedType,
          'status': _selectedType == 'walk_in' ? 'waiting' : 'scheduled',
          if (formattedNotes.isNotEmpty) 'notes': formattedNotes,
          if (formattedNotes.isEmpty) 'notes': null,
        };'''

new_updates_block = '''        final updates = <String, dynamic>{
          'patient_id': _selectedPatientId,
          'department': _selectedDepartment,
          'doctor_id': DepartmentDoctorConfig.isValidUuid(_selectedDoctorId)
              ? _selectedDoctorId
              : null,
          'appointment_date': _selectedDate.toIso8601String().split('T').first,
          'appointment_time': _formatTimeOfDay(_selectedTime),
          'appointment_type': _selectedType,
          'status': widget.existingAppointment!.status,
          if (formattedNotes.isNotEmpty) 'notes': formattedNotes,
          if (formattedNotes.isEmpty) 'notes': null,
        };'''

if old_updates_block in text:
    text = text.replace(old_updates_block, new_updates_block)
elif old_updates_block.replace('\n', '\r\n') in text:
    text = text.replace(old_updates_block.replace('\n', '\r\n'), new_updates_block.replace('\n', '\r\n'))

if old_reload in text:
    text = text.replace(old_reload, new_reload)
elif old_reload.replace('\n', '\r\n') in text:
    text = text.replace(old_reload.replace('\n', '\r\n'), new_reload.replace('\n', '\r\n'))

with open('lib/features/appointments/widgets/appointment_form_dialog.dart', 'w', encoding='utf-8') as f:
    f.write(text)

print('Updated appointment_form_dialog.dart successfully!')

