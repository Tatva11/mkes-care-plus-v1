import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import '../models/department.dart';

final departmentRepositoryProvider = Provider<DepartmentRepository>((ref) {
  try {
    return DepartmentRepository(ref.watch(supabaseProvider));
  } catch (_) {
    return DepartmentRepository(null);
  }
});

class DepartmentRepository {
  DepartmentRepository([this._supabase]);

  final SupabaseClient? _supabase;

  static final List<Department> _inMemoryDepartments = [
    const Department(
      id: 'c1000000-0000-0000-0000-000000000001',
      name: 'Eye',
      description: 'Comprehensive Eye Care and Ophthalmology',
      isActive: true,
    ),
    const Department(
      id: 'c1000000-0000-0000-0000-000000000002',
      name: 'Dental',
      description: 'Advanced Dental Care and Oral Surgery',
      isActive: true,
    ),
  ];

  Future<List<Department>> fetchDepartments() async {
    if (_supabase == null) {
      return List.unmodifiable(_inMemoryDepartments);
    }
    try {
      final response = await _supabase.from('departments').select().order('name');
      final list = (response as List)
          .map((json) => Department.fromJson(json as Map<String, dynamic>))
          .toList();
      _inMemoryDepartments
        ..clear()
        ..addAll(list);
      return list;
    } catch (_) {
      return List.unmodifiable(_inMemoryDepartments);
    }
  }

  Future<Department> createDepartment({
    required String name,
    String? description,
  }) async {
    if (_supabase != null) {
      final response = await _supabase.from('departments').insert({
        'name': name,
        'description': description,
        'is_active': true,
      }).select().single();
      final dept = Department.fromJson(response);
      _inMemoryDepartments.removeWhere((d) => d.id == dept.id);
      _inMemoryDepartments.add(dept);
      return dept;
    } else {
      final newDept = Department(
        id: 'c1000000-0000-0000-0000-${DateTime.now().millisecondsSinceEpoch.toRadixString(16).padLeft(12, '0').substring(0, 12)}',
        name: name,
        description: description,
        isActive: true,
      );
      _inMemoryDepartments.add(newDept);
      return newDept;
    }
  }

  Future<void> updateDepartment({
    required String id,
    required String name,
    String? description,
    required bool isActive,
  }) async {
    if (_supabase != null) {
      await _supabase.from('departments').update({
        'name': name,
        'description': description,
        'is_active': isActive,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);
    }
    final idx = _inMemoryDepartments.indexWhere((d) => d.id == id);
    if (idx != -1) {
      _inMemoryDepartments[idx] = Department(
        id: id,
        name: name,
        description: description,
        isActive: isActive,
      );
    }
  }

  Future<void> deleteDepartment(String id) async {
    if (_supabase != null) {
      // 1. Unlink profiles assigned to this department to avoid foreign key violations (error 23503)
      try {
        await _supabase
            .from('profiles')
            .update({'department_id': null})
            .eq('department_id', id);
      } catch (_) {}

      // 2. Clear any dependent stock requests or inventory child rows for this department
      try {
        await _supabase
            .from('stock_requests')
            .delete()
            .eq('department_id', id);
      } catch (_) {}

      try {
        await _supabase
            .from('department_inventory')
            .delete()
            .eq('department_id', id);
      } catch (_) {}

      // 3. Delete department row
      await _supabase.from('departments').delete().eq('id', id);
    }

    // 4. Always update in-memory cache
    _inMemoryDepartments.removeWhere((d) => d.id == id);
  }
}
