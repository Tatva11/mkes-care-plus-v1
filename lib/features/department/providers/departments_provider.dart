import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/department.dart';
import '../repositories/department_repository.dart';

final departmentsProvider =
    StateNotifierProvider<DepartmentsNotifier, AsyncValue<List<Department>>>(
  (ref) => DepartmentsNotifier(ref.watch(departmentRepositoryProvider)),
);

class DepartmentsNotifier extends StateNotifier<AsyncValue<List<Department>>> {
  DepartmentsNotifier(this._repository) : super(const AsyncValue.loading()) {
    fetchDepartments();
  }

  final DepartmentRepository _repository;

  Future<void> fetchDepartments() async {
    state = const AsyncValue.loading();
    try {
      state = AsyncValue.data(await _repository.fetchDepartments());
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> createDepartment(
      {required String name, String? description}) async {
    await _repository.createDepartment(name: name, description: description);
    await fetchDepartments();
  }

  Future<void> updateDepartment({
    required String id,
    required String name,
    String? description,
    required bool isActive,
  }) async {
    await _repository.updateDepartment(
      id: id,
      name: name,
      description: description,
      isActive: isActive,
    );
    await fetchDepartments();
  }

  Future<void> deleteDepartment(String id) async {
    await _repository.deleteDepartment(id);
    await fetchDepartments();
  }
}
