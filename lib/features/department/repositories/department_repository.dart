import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import '../models/department.dart';

final departmentRepositoryProvider = Provider<DepartmentRepository>((ref) {
  return DepartmentRepository(ref.watch(supabaseProvider));
});

class DepartmentRepository {
  DepartmentRepository(this._supabase);

  final SupabaseClient _supabase;

  Future<List<Department>> fetchDepartments() async {
    final response = await _supabase.from('departments').select().order('name');
    return (response as List)
        .map((json) => Department.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<void> createDepartment(
      {required String name, String? description}) async {
    await _supabase.from('departments').insert({
      'name': name,
      'description': description,
    });
  }

  Future<void> updateDepartment({
    required String id,
    required String name,
    String? description,
    required bool isActive,
  }) async {
    await _supabase.from('departments').update({
      'name': name,
      'description': description,
      'is_active': isActive,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  Future<void> deleteDepartment(String id) async {
    await _supabase.from('departments').delete().eq('id', id);
  }
}
