import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/appointment_model.dart';
import '../repositories/appointment_repository.dart';

/// Fallback appointments matching the initial clinical schedule data.
final List<AppointmentModel> initialFallbackAppointments = [
  AppointmentModel(
    id: 'APT-101',
    appointmentTime: '09:00:00',
    appointmentDate: DateTime.now(),
    patientName: 'Sarah Jenkins',
    patientNumber: 'E1',
    department: 'eye',
    appointmentType: 'regular',
    room: 'Room 102',
    status: 'confirmed',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  ),
  AppointmentModel(
    id: 'APT-102',
    appointmentTime: '10:30:00',
    appointmentDate: DateTime.now(),
    patientName: 'Michael Chen',
    patientNumber: 'E2',
    department: 'eye',
    appointmentType: 'regular',
    room: 'Specialist Suite B',
    status: 'waiting',
    isVisitingDoctor: true,
    doctorName: 'Dr. Robert Sterling',
    specialty: 'Visiting Retina Specialist',
    previousVisitSummary: 'Consulted May 04, 2026 for diabetic eye screening',
    previousTreatment: 'Dilated Macular Exam & 3D Topography',
    currentDiagnosis: 'Mild central macular edema flag; IOP 17 mmHg',
    plannedTreatment: 'High-definition OCT scan & Anti-VEGF evaluation',
    doctorNotes:
        'Patient reports mild central blurring. Please review macular thickness scan before consultation.',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  ),
  AppointmentModel(
    id: 'APT-103',
    appointmentTime: '13:15:00',
    appointmentDate: DateTime.now(),
    patientName: 'Elena Rodriguez',
    patientNumber: 'E3',
    department: 'eye',
    appointmentType: 'follow_up',
    room: 'Room 204',
    status: 'scheduled',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  ),
  AppointmentModel(
    id: 'APT-104',
    appointmentTime: '14:30:00',
    appointmentDate: DateTime.now(),
    patientName: 'James Wilson',
    patientNumber: 'D1',
    department: 'eye',
    appointmentType: 'regular',
    room: 'Room 105',
    status: 'scheduled',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  ),
];

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

  AppointmentsNotifier(this._repository) : super(const AsyncValue.loading()) {
    loadTodayAppointments();
  }

  Future<void> loadTodayAppointments(
      {String? doctorId, String? department}) async {
    try {
      final items = await _repository.fetchTodayAppointments(
        doctorId: doctorId,
        department: department,
      );

      // If backend returns data, use it; otherwise fallback to preserve initial schedule UI.
      if (items.isNotEmpty) {
        state = AsyncValue.data(items);
      } else {
        state = AsyncValue.data(initialFallbackAppointments);
      }
    } catch (e) {
      debugPrint('Error loading appointments from Supabase: $e');
      // If error or network offline, provide fallback gracefully
      state = AsyncValue.data(initialFallbackAppointments);
    }
  }

  Future<void> updateStatus(String appointmentId, String newStatus) async {
    final currentList = state.value ?? initialFallbackAppointments;

    // Optimistic UI update
    final updatedList = currentList.map((item) {
      if (item.id == appointmentId) {
        return item.copyWith(status: newStatus.toLowerCase());
      }
      return item;
    }).toList();

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
      state = AsyncValue.data([...currentList, created]);
    } catch (e) {
      debugPrint('Error creating appointment in Supabase: $e');
      rethrow;
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
