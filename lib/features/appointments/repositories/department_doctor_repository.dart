import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import '../models/department_doctor_config.dart';

final departmentDoctorRepositoryProvider =
    Provider<DepartmentDoctorRepository>((ref) {
  return DepartmentDoctorRepository(ref.watch(supabaseProvider));
});

/// Repository for managing department doctors with persistent Supabase backend
/// and resilient in-memory seed fallback.
class DepartmentDoctorRepository {
  final SupabaseClient _supabase;

  static final List<DepartmentDoctor> _inMemoryCache = [
    ...DepartmentDoctorConfig.confirmedEyeDoctors,
    ...DepartmentDoctorConfig.confirmedDentalDoctors,
  ];

  DepartmentDoctorRepository(this._supabase);

  /// Initial fallback list of doctors if no records exist in DB.
  static List<DepartmentDoctor> get initialDoctors => [
        ...DepartmentDoctorConfig.confirmedEyeDoctors,
        ...DepartmentDoctorConfig.confirmedDentalDoctors,
      ];

  /// Fetch all configured doctors, optionally filtered by department and active status.
  Future<List<DepartmentDoctor>> fetchDoctors({
    String? department,
    bool? activeOnly,
  }) async {
    List<DepartmentDoctor> doctors = [];

    try {
      var query = _supabase.from('department_doctors').select();
      if (department != null && department.isNotEmpty) {
        query = query.eq('department', department.toLowerCase().trim());
      }
      if (activeOnly == true) {
        query = query.eq('is_active', true);
      }

      final response = await query
          .order('department', ascending: true)
          .order('full_name', ascending: true);

      final list = response as List;
      if (list.isNotEmpty) {
        doctors = list
            .map((json) => DepartmentDoctor.fromJson(
                Map<String, dynamic>.from(json as Map)))
            .toList();
        // Update cache
        await _saveToLocalCache(doctors);
      }
    } catch (e) {
      debugPrint(
          'DepartmentDoctorRepository.fetchDoctors falling back to cache: $e');
    }

    if (doctors.isEmpty) {
      doctors = await _loadFromLocalCache();
    }

    if (doctors.isEmpty) {
      doctors = List<DepartmentDoctor>.from(initialDoctors);
      await _saveToLocalCache(doctors);
    }

    // Apply in-memory filtering if cache was used
    var filtered = doctors;
    if (department != null && department.isNotEmpty) {
      final deptNorm = department.toLowerCase().trim();
      filtered = filtered
          .where((d) => d.department.toLowerCase().trim() == deptNorm)
          .toList();
    }
    if (activeOnly == true) {
      filtered = filtered.where((d) => d.isActive).toList();
    }

    // Keep DepartmentDoctorConfig synchronized
    DepartmentDoctorConfig.syncConfiguredDoctors(doctors);

    return filtered;
  }

  /// Add a new doctor.
  Future<DepartmentDoctor> createDoctor({
    required String fullName,
    required String department,
    String? specialty,
  }) async {
    final cleanName = fullName.trim();
    final cleanDept = department.toLowerCase().trim();
    final cleanSpecialty = specialty?.trim();

    DepartmentDoctor newDoctor = DepartmentDoctor(
      id: '',
      fullName: cleanName,
      department: cleanDept,
      specialty: cleanSpecialty,
      isActive: true,
    );

    try {
      final insertData = {
        'full_name': cleanName,
        'department': cleanDept,
        'is_active': true,
        if (cleanSpecialty != null && cleanSpecialty.isNotEmpty)
          'specialty': cleanSpecialty,
      };

      final response = await _supabase
          .from('department_doctors')
          .insert(insertData)
          .select()
          .single();

      newDoctor =
          DepartmentDoctor.fromJson(Map<String, dynamic>.from(response as Map));
    } catch (e) {
      debugPrint(
          'DepartmentDoctorRepository.createDoctor Supabase fallback: $e');
      // If DB call failed (e.g. migration pending), assign local UUID
      newDoctor = DepartmentDoctor(
        id: 'local-${DateTime.now().millisecondsSinceEpoch}',
        fullName: cleanName,
        department: cleanDept,
        specialty: cleanSpecialty,
        isActive: true,
      );
    }

    final currentList = await _loadFromLocalCache();
    // Avoid duplicate names in same department
    final existingIndex = currentList.indexWhere((d) =>
        d.fullName.toLowerCase().trim() == cleanName.toLowerCase() &&
        d.department.toLowerCase().trim() == cleanDept);

    if (existingIndex >= 0) {
      currentList[existingIndex] = newDoctor;
    } else {
      currentList.add(newDoctor);
    }

    await _saveToLocalCache(currentList);
    DepartmentDoctorConfig.syncConfiguredDoctors(currentList);
    return newDoctor;
  }

  /// Edit existing doctor name, specialty, or active status.
  Future<DepartmentDoctor> updateDoctor({
    required String id,
    required String fullName,
    required String department,
    String? specialty,
    required bool isActive,
  }) async {
    final cleanName = fullName.trim();
    final cleanDept = department.toLowerCase().trim();
    final cleanSpecialty = specialty?.trim();

    DepartmentDoctor updated = DepartmentDoctor(
      id: id,
      fullName: cleanName,
      department: cleanDept,
      specialty: cleanSpecialty,
      isActive: isActive,
    );

    try {
      final updateData = <String, dynamic>{
        'full_name': cleanName,
        'department': cleanDept,
        'is_active': isActive,
        'specialty': cleanSpecialty,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (id.isNotEmpty && !id.startsWith('local-')) {
        final response = await _supabase
            .from('department_doctors')
            .update(updateData)
            .eq('id', id)
            .select()
            .single();

        updated = DepartmentDoctor.fromJson(
            Map<String, dynamic>.from(response as Map));
      } else {
        // Match by department + full_name
        final response = await _supabase
            .from('department_doctors')
            .update(updateData)
            .eq('department', cleanDept)
            .eq('full_name', cleanName)
            .select()
            .maybeSingle();

        if (response != null) {
          updated = DepartmentDoctor.fromJson(
              Map<String, dynamic>.from(response as Map));
        }
      }
    } catch (e) {
      debugPrint(
          'DepartmentDoctorRepository.updateDoctor Supabase fallback: $e');
    }

    final currentList = await _loadFromLocalCache();
    final index = currentList.indexWhere((d) =>
        (id.isNotEmpty && d.id == id) ||
        (d.fullName.toLowerCase().trim() == cleanName.toLowerCase() &&
            d.department.toLowerCase().trim() == cleanDept));

    if (index >= 0) {
      currentList[index] = updated;
    } else {
      currentList.add(updated);
    }

    await _saveToLocalCache(currentList);
    DepartmentDoctorConfig.syncConfiguredDoctors(currentList);
    return updated;
  }

  /// Toggle active/deactive status of a doctor.
  Future<void> setDoctorActive(
      String id, String fullName, String department, bool isActive) async {
    await updateDoctor(
      id: id,
      fullName: fullName,
      department: department,
      isActive: isActive,
    );
  }

  // ── Cache ─────────────────────────────────────────────────────────────────

  Future<void> _saveToLocalCache(List<DepartmentDoctor> doctors) async {
    _inMemoryCache.clear();
    _inMemoryCache.addAll(doctors);
  }

  Future<List<DepartmentDoctor>> _loadFromLocalCache() async {
    if (_inMemoryCache.isEmpty) {
      _inMemoryCache.addAll(initialDoctors);
    }
    return List<DepartmentDoctor>.from(_inMemoryCache);
  }
}
