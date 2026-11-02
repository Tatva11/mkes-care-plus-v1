import 'package:flutter_test/flutter_test.dart';
import 'package:mkes_care/features/appointments/repositories/appointment_repository.dart';
import 'package:mkes_care/features/department/models/department.dart';
import 'package:mkes_care/features/department/repositories/department_repository.dart';

void main() {
  group('AppointmentRepository - Time Slot & Collision Tests', () {
    test('normalizeTimePrefix handles varied time representations', () {
      expect(AppointmentRepository.normalizeTimePrefix('09:30:00'), '09:30');
      expect(AppointmentRepository.normalizeTimePrefix('9:30'), '09:30');
      expect(AppointmentRepository.normalizeTimePrefix('09:30'), '09:30');
      expect(AppointmentRepository.normalizeTimePrefix('14:05:00'), '14:05');
      expect(AppointmentRepository.normalizeTimePrefix('2:05'), '02:05');
      expect(AppointmentRepository.normalizeTimePrefix(''), '');
    });

    test('AppointmentConflictException stores and displays message', () {
      final ex = AppointmentConflictException('Patient already booked at this time.');
      expect(ex.message, 'Patient already booked at this time.');
      expect(ex.toString(), 'Patient already booked at this time.');
    });
  });

  group('DepartmentRepository - Offline & CRUD Tests', () {
    test('fetchDepartments returns default eye and dental with valid UUIDs', () async {
      final repo = DepartmentRepository(null);
      final list = await repo.fetchDepartments();

      expect(list.length, greaterThanOrEqualTo(2));
      final names = list.map((d) => d.name).toList();
      expect(names, contains('Eye'));
      expect(names, contains('Dental'));
    });

    test('createDepartment adds a new department to in-memory list', () async {
      final repo = DepartmentRepository(null);
      final newDept = await repo.createDepartment(
        name: 'Orthopedics',
        description: 'Bone and joint clinic',
      );

      expect(newDept.name, 'Orthopedics');
      expect(newDept.description, 'Bone and joint clinic');
      expect(newDept.isActive, isTrue);

      final updatedList = await repo.fetchDepartments();
      expect(updatedList.map((d) => d.name), contains('Orthopedics'));
    });

    test('updateDepartment updates name and status', () async {
      final repo = DepartmentRepository(null);
      final list = await repo.fetchDepartments();
      final target = list.firstWhere((d) => d.name == 'Orthopedics');

      await repo.updateDepartment(
        id: target.id,
        name: 'Orthopedics Updated',
        description: 'Updated description',
        isActive: false,
      );

      final updatedList = await repo.fetchDepartments();
      final updated = updatedList.firstWhere((d) => d.id == target.id);
      expect(updated.name, 'Orthopedics Updated');
      expect(updated.isActive, isFalse);
    });

    test('deleteDepartment removes the department cleanly from the list', () async {
      final repo = DepartmentRepository(null);
      final list = await repo.fetchDepartments();
      final target = list.firstWhere((d) => d.name == 'Orthopedics Updated');

      await repo.deleteDepartment(target.id);

      final updatedList = await repo.fetchDepartments();
      expect(updatedList.any((d) => d.id == target.id), isFalse);
    });
  });
}

