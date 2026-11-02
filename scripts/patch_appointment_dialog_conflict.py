import re

file_path = "lib/features/appointments/widgets/appointment_form_dialog.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# Make sure appointmentRepositoryProvider is imported if needed
if "appointment_repository.dart" not in content:
    content = re.sub(
        r"(import '\.\./providers/appointment_provider\.dart';)",
        r"\1\nimport '../repositories/appointment_repository.dart';",
        content
    )

submit_pattern = """    setState(() => _isLoading = true);
    try {"""

submit_replacement = """    setState(() => _isLoading = true);
    try {
      final conflict = await ref
          .read(appointmentRepositoryProvider)
          .checkAppointmentConflict(
            date: _selectedDate,
            time: _formatTimeOfDay(_selectedTime),
            department: _selectedDepartment,
            patientId: _selectedPatientId,
            doctorId: _selectedDoctorId,
            doctorName: _selectedDoctorName,
            excludeAppointmentId: widget.existingAppointment?.id,
          );

      if (conflict != null) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              icon: const Icon(Icons.event_busy, color: AppColors.error, size: 36),
              title: const Text('Appointment Time Conflict'),
              content: Text(
                conflict,
                style: AppTypography.bodyMd,
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Change Time Slot'),
                ),
              ],
            ),
          );
        }
        return;
      }"""

content = content.replace(submit_pattern, submit_replacement)

with open(file_path, "w", encoding="utf-8", newline="") as f:
    f.write(content)

print("Updated appointment_form_dialog.dart successfully")

