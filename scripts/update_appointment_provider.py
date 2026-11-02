with open('lib/features/appointments/providers/appointment_provider.dart', 'r', encoding='utf-8') as f:
    text = f.read()

target = '''    // If appointment moved to another date, remove from today's list
    final now = DateTime.now();
    final remainingForToday = updatedList.where((item) {
      return item.appointmentDate.year == now.year &&
          item.appointmentDate.month == now.month &&
          item.appointmentDate.day == now.day;
    }).toList();

    remainingForToday.sort(AppointmentModel.compareAppointments);
    state = AsyncValue.data(remainingForToday);

    try {
      if (!appointmentId.startsWith('APT-')) {
        await _repository.updateAppointment(appointmentId, updates);
      }
    } catch (e) {
      debugPrint('Error syncing appointment update to Supabase: $e');
    }'''

replacement = '''    // If appointment moved to another date, remove from currently viewed date's list
    final remainingForCurrentDate = updatedList.where((item) {
      return item.appointmentDate.year == _currentDate.year &&
          item.appointmentDate.month == _currentDate.month &&
          item.appointmentDate.day == _currentDate.day;
    }).toList();

    remainingForCurrentDate.sort(AppointmentModel.compareAppointments);
    state = AsyncValue.data(remainingForCurrentDate);

    try {
      if (!appointmentId.startsWith('APT-')) {
        await _repository.updateAppointment(appointmentId, updates);
      }
    } catch (e) {
      debugPrint('Error syncing appointment update to Supabase: $e');
      await loadAppointmentsForDate(_currentDate);
      rethrow;
    }'''

if target in text:
    text = text.replace(target, replacement)
elif target.replace('\n', '\r\n') in text:
    text = text.replace(target.replace('\n', '\r\n'), replacement.replace('\n', '\r\n'))
else:
    print('Target not found directly in appointment_provider.dart')

with open('lib/features/appointments/providers/appointment_provider.dart', 'w', encoding='utf-8') as f:
    f.write(text)

print('Updated appointment_provider.dart successfully!')

