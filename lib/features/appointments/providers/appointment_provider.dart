import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/appointment_model.dart';
import '../repositories/appointment_repository.dart';


final appointmentsNotifierProvider = StateNotifierProvider<AppointmentsNotifier,
    AsyncValue<List<AppointmentModel>>>((ref) {
  final repository = ref.watch(appointmentRepositoryProvider);
  return AppointmentsNotifier(repository);
});

final appointmentStaffCandidatesProvider =
    FutureProvider.family<List<AppointmentStaffCandidate>, String>(
        (ref, departmentId) {
  final repository = ref.watch(appointmentRepositoryProvider);
  return repository.fetchDepartmentStaffCandidates(departmentId);
});

class AppointmentsNotifier
    extends StateNotifier<AsyncValue<List<AppointmentModel>>> {
  final AppointmentRepository _repository;
  DateTime _currentDate;

  AppointmentsNotifier(this._repository)
      : _currentDate = DateTime.now(),
        super(const AsyncValue.loading()) {
    loadTodayAppointments();
  }

  DateTime get currentDate => _currentDate;

  Future<void> loadTodayAppointments(
      {String? doctorId, String? department}) async {
    await loadAppointmentsForDate(DateTime.now(),
        doctorId: doctorId, department: department);
  }

  Future<void> loadAppointmentsForDate(DateTime date,
      {String? doctorId, String? department}) async {
    _currentDate = date;
    state = const AsyncValue.loading();
    try {
      final items = await _repository.fetchAppointments(
        date: date,
        doctorId: doctorId,
        department: department,
      );

      items.sort(AppointmentModel.compareAppointments);
      state = AsyncValue.data(items);
    } catch (e, st) {
      debugPrint('Error loading appointments from Supabase: $e');
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> updateStatus(String appointmentId, String newStatus) async {
    final currentList = state.value ?? [];

    // Optimistic UI update
    final updatedList = currentList.map((item) {
      if (item.id == appointmentId) {
        return item.copyWith(status: newStatus.toLowerCase());
      }
      return item;
    }).toList();

    updatedList.sort(AppointmentModel.compareAppointments);
    state = AsyncValue.data(updatedList);

    try {
      // If it's not a mock ID, update in Supabase
      if (!appointmentId.startsWith('APT-')) {
        await _repository.updateStatus(appointmentId, newStatus);
      }
    } catch (e) {
      debugPrint('Error syncing appointment status to Supabase: $e');
    }
  }

  Future<void> createAppointment(AppointmentModel newAppointment) async {
    try {
      final created = await _repository.createAppointment(newAppointment);
      final currentList = state.value ?? [];
      final nextList = [...currentList, created]
        ..sort(AppointmentModel.compareAppointments);
      state = AsyncValue.data(nextList);
    } catch (e) {
      debugPrint('Error creating appointment in Supabase: $e');
      rethrow;
    }
  }

  Future<void> updateAppointment(
    String appointmentId,
    Map<String, dynamic> updates,
  ) async {
    final currentList = state.value ?? [];
    final updatedList = currentList.map((item) {
      if (item.id == appointmentId) {
        final updatedNotes = updates.containsKey('notes')
            ? updates['notes'] as String?
            : item.notes;
        final updatedDoctorId = updates.containsKey('doctor_id')
            ? updates['doctor_id'] as String?
            : item.doctorId;
        final updatedDoctorName = updates.containsKey('doctor_name')
            ? updates['doctor_name'] as String?
            : (AppointmentModel.extractDoctorNameFromNotes(updatedNotes) ??
                (updatedDoctorId == null ? null : item.doctorName));

        return item.copyWith(
          patientId: updates['patient_id'] ?? item.patientId,
          department: updates['department'] ?? item.department,
          doctorId: updatedDoctorId,
          doctorName: updatedDoctorName,
          appointmentDate: updates['appointment_date'] != null
              ? DateTime.tryParse(updates['appointment_date'] as String) ??
                  item.appointmentDate
              : item.appointmentDate,
          appointmentTime: updates['appointment_time'] ?? item.appointmentTime,
          appointmentType: updates['appointment_type'] ?? item.appointmentType,
          status: updates['status'] ?? item.status,
          notes: updatedNotes,
          updatedAt: DateTime.now(),
        );
      }
      return item;
    }).toList();

    // If appointment moved to another date, remove from today's list
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
    }
  }

  Future<void> deleteAppointment(String appointmentId) async {
    final currentList = state.value ?? [];
    state = AsyncValue.data(
      currentList.where((item) => item.id != appointmentId).toList(),
    );

    try {
      if (!appointmentId.startsWith('APT-')) {
        await _repository.deleteAppointment(appointmentId);
      }
    } catch (e) {
      debugPrint('Error deleting appointment in Supabase: $e');
    }
  }
}
