import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../admin/models/user_profile.dart';
import '../repositories/department_doctor_repository.dart';

/// Represents a configured doctor for a clinical department.
class DepartmentDoctor {
  final String id;
  final String fullName;
  final String department; // 'eye' | 'dental'
  final String? specialty;
  final bool isActive;

  const DepartmentDoctor({
    required this.id,
    required this.fullName,
    required this.department,
    this.specialty,
    this.isActive = true,
  });

  /// Whether this doctor has a valid database UUID.
  bool get hasValidDatabaseId => DepartmentDoctorConfig.isValidUuid(id);

  factory DepartmentDoctor.fromJson(Map<String, dynamic> json) {
    return DepartmentDoctor(
      id: json['id'] as String? ?? '',
      fullName: json['full_name'] as String,
      department: (json['department'] as String? ?? 'eye').toLowerCase().trim(),
      specialty: json['specialty'] as String?,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'full_name': fullName,
      'department': department,
      if (specialty != null) 'specialty': specialty,
      'is_active': isActive,
    };
  }

  DepartmentDoctor copyWith({
    String? id,
    String? fullName,
    String? department,
    String? specialty,
    bool? isActive,
  }) {
    return DepartmentDoctor(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      department: department ?? this.department,
      specialty: specialty ?? this.specialty,
      isActive: isActive ?? this.isActive,
    );
  }
}

/// Maintainable configuration layer for department-specific doctors.
///
/// Sprint 11 Authoritative Confirmed Roster:
/// - Eye Department: Dr Mitesh, Dr Varun
/// - Dental Department: Dr Nimisha, Dr Vikas
///
/// Rules:
/// 1. Eye appointments show only confirmed Eye doctors.
/// 2. Dental appointments show only confirmed Dental doctors.
/// 3. Doctor IDs must be valid PostgreSQL UUIDs matching active database profiles.
/// 4. Fabricated string IDs (e.g. 'doc-eye-mitesh') are strictly forbidden.
/// 5. When doctors are missing matching profiles in the database, report the missing mapping.
class DepartmentDoctorConfig {
  DepartmentDoctorConfig._();

  /// Canonical confirmed static doctor entries for Eye Department.
  static const List<DepartmentDoctor> confirmedEyeDoctors = [
    DepartmentDoctor(
      id: '',
      fullName: 'Dr Mitesh Jain',
      department: 'eye',
      specialty: 'Ophthalmology',
    ),
    DepartmentDoctor(
      id: '',
      fullName: 'Dr Varun',
      department: 'eye',
      specialty: 'Ophthalmology',
    ),
  ];

  /// Canonical confirmed static doctor entries for Dental Department.
  static const List<DepartmentDoctor> confirmedDentalDoctors = [
    DepartmentDoctor(
      id: '',
      fullName: 'Dr Nimisha',
      department: 'dental',
      specialty: 'General Dentistry',
    ),
    DepartmentDoctor(
      id: '',
      fullName: 'Dr Vikas',
      department: 'dental',
      specialty: 'Dental Surgery',
    ),
  ];

  static final Map<String, List<DepartmentDoctor>> _configuredDoctors = {
    'eye': List<DepartmentDoctor>.from(confirmedEyeDoctors),
    'dental': List<DepartmentDoctor>.from(confirmedDentalDoctors),
  };

  /// Validates whether a given string is a valid canonical PostgreSQL UUID.
  static bool isValidUuid(String? val) {
    if (val == null) return false;
    final clean = val.trim();
    if (clean.length != 36) return false;
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(clean);
  }

  /// Set configured doctors for a department (for testing or runtime initialization).
  static void setDoctorsForDepartment(
    String department,
    List<DepartmentDoctor> doctors,
  ) {
    _configuredDoctors[department.toLowerCase().trim()] =
        List.unmodifiable(doctors);
  }

  /// Reset configured doctors to the confirmed authoritative roster.
  static void reset() {
    _configuredDoctors['eye'] =
        List<DepartmentDoctor>.from(confirmedEyeDoctors);
    _configuredDoctors['dental'] =
        List<DepartmentDoctor>.from(confirmedDentalDoctors);
  }

  /// Clears configured doctors to an empty state (useful for testing fallback UI).
  static void clear() {
    _configuredDoctors['eye'] = <DepartmentDoctor>[];
    _configuredDoctors['dental'] = <DepartmentDoctor>[];
  }

  /// Synchronizes configured doctors with updated roster list.
  static void syncConfiguredDoctors(List<DepartmentDoctor> doctors) {
    final eye = doctors
        .where((d) => d.department.toLowerCase().trim() == 'eye')
        .toList();
    final dental = doctors
        .where((d) => d.department.toLowerCase().trim() == 'dental')
        .toList();
    if (eye.isNotEmpty) _configuredDoctors['eye'] = List.unmodifiable(eye);
    if (dental.isNotEmpty) {
      _configuredDoctors['dental'] = List.unmodifiable(dental);
    }
  }

  /// Returns configured doctors for [department].
  static List<DepartmentDoctor> getDoctorsForDepartment(
    String department, {
    List<UserProfile>? users,
    bool activeOnly = false,
  }) {
    final key = department.toLowerCase().trim();
    if (users != null && users.isNotEmpty) {
      syncWithDatabaseProfiles(users);
    }
    var list = _configuredDoctors[key] ?? const [];
    if (activeOnly) {
      list = list.where((d) => d.isActive).toList();
    }
    return list;
  }

  /// Validates whether [doctorName] is a valid static doctor for [department].
  /// Null or empty represents Unassigned / General Queue.
  /// When [activeOnly] is true, only currently active doctors are valid (e.g. for booking new appointments).
  /// When [activeOnly] is false, both active and historical doctors are accepted.
  static bool isValidDoctorNameForDepartment(
    String? doctorName,
    String department, {
    bool activeOnly = false,
  }) {
    if (doctorName == null || doctorName.trim().isEmpty) {
      return true;
    }
    final normName = doctorName.trim().toLowerCase();
    final doctors = getDoctorsForDepartment(department, activeOnly: activeOnly);
    return doctors.any((d) => d.fullName.toLowerCase() == normName);
  }

  /// Validates whether [doctorIdOrName] is a configured doctor for [department].
  /// Null or empty doctor ID/name represents General Queue / Unassigned, which is always valid.
  static bool isValidDoctorForDepartment(
    String? doctorIdOrName,
    String department, {
    List<UserProfile>? users,
    bool activeOnly = false,
  }) {
    if (doctorIdOrName == null || doctorIdOrName.trim().isEmpty) {
      return true;
    }
    if (isValidDoctorNameForDepartment(doctorIdOrName, department,
        activeOnly: activeOnly)) {
      return true;
    }
    if (isValidUuid(doctorIdOrName)) {
      final doctors = getDoctorsForDepartment(department,
          users: users, activeOnly: activeOnly);
      return doctors.any((d) => d.id == doctorIdOrName);
    }
    return false;
  }

  /// Synchronizes confirmed roster doctors with database user profiles when available.
  static Map<String, String?> syncWithDatabaseProfiles(
      List<UserProfile> profiles) {
    final Map<String, String?> mapping = {
      'Dr Mitesh Jain': null,
      'Dr Mitesh': null,
      'Dr Varun': null,
      'Dr Nimisha': null,
      'Dr Vikas': null,
    };

    final updatedEye = <DepartmentDoctor>[];
    for (final doc in confirmedEyeDoctors) {
      final nameKey = doc.fullName.replaceAll('Dr ', '').trim().toLowerCase();
      final firstName = nameKey.split(' ').first;
      final matchingProfiles = profiles.where((p) {
        if (!p.isActive) return false;
        final fullNameLower = p.fullName.toLowerCase();
        final nameMatch = fullNameLower.contains(nameKey) ||
            fullNameLower.contains(firstName);
        final deptStr = (p.departmentName ?? p.department ?? '').toLowerCase();
        final deptMatch = deptStr.contains('eye') ||
            deptStr.contains('clinical') ||
            deptStr.isEmpty;
        return nameMatch && deptMatch;
      }).toList();

      if (matchingProfiles.length == 1) {
        final profile = matchingProfiles.first;
        if (isValidUuid(profile.id)) {
          mapping[doc.fullName] = profile.id;
          if (doc.fullName == 'Dr Mitesh Jain') {
            mapping['Dr Mitesh'] = profile.id;
          }
          updatedEye.add(doc.copyWith(id: profile.id));
          continue;
        }
      }
      updatedEye.add(doc);
    }
    _configuredDoctors['eye'] = List.unmodifiable(updatedEye);

    final updatedDental = <DepartmentDoctor>[];
    for (final doc in confirmedDentalDoctors) {
      final nameKey = doc.fullName.replaceAll('Dr ', '').trim().toLowerCase();
      final firstName = nameKey.split(' ').first;
      final matchingProfiles = profiles.where((p) {
        if (!p.isActive) return false;
        final fullNameLower = p.fullName.toLowerCase();
        final nameMatch = fullNameLower.contains(nameKey) ||
            fullNameLower.contains(firstName);
        final deptStr = (p.departmentName ?? p.department ?? '').toLowerCase();
        final deptMatch = deptStr.contains('dental') ||
            deptStr.contains('clinical') ||
            deptStr.isEmpty;
        return nameMatch && deptMatch;
      }).toList();

      if (matchingProfiles.length == 1) {
        final profile = matchingProfiles.first;
        if (isValidUuid(profile.id)) {
          mapping[doc.fullName] = profile.id;
          updatedDental.add(doc.copyWith(id: profile.id));
          continue;
        }
      }
      updatedDental.add(doc);
    }
    _configuredDoctors['dental'] = List.unmodifiable(updatedDental);

    return mapping;
  }

  /// Identifies which doctors from the confirmed roster are missing corresponding database profiles.
  static List<String> findMissingDatabaseProfiles(List<UserProfile> profiles) {
    final mapping = syncWithDatabaseProfiles(profiles);
    return mapping.entries
        .where((e) => e.value == null)
        .map((e) => e.key)
        .toList();
  }
}

/// Riverpod provider for department-specific active doctors (used in appointment booking dropdown).
final departmentDoctorsProvider =
    Provider.family<List<DepartmentDoctor>, String>((ref, department) {
  // Watch adminDoctorsProvider to reactively update when doctors are added/edited/toggled
  final adminDocsAsync = ref.watch(adminDoctorsProvider);
  final allDocs = adminDocsAsync.valueOrNull;
  if (allDocs != null && allDocs.isNotEmpty) {
    final deptKey = department.toLowerCase().trim();
    return allDocs
        .where(
            (d) => d.department.toLowerCase().trim() == deptKey && d.isActive)
        .toList();
  }
  return DepartmentDoctorConfig.getDoctorsForDepartment(department,
      activeOnly: true);
});

/// Riverpod provider for all doctors in a department (including inactive, for history/validation).
final allDepartmentDoctorsProvider =
    Provider.family<List<DepartmentDoctor>, String>((ref, department) {
  final adminDocsAsync = ref.watch(adminDoctorsProvider);
  final allDocs = adminDocsAsync.valueOrNull;
  if (allDocs != null && allDocs.isNotEmpty) {
    final deptKey = department.toLowerCase().trim();
    return allDocs
        .where((d) => d.department.toLowerCase().trim() == deptKey)
        .toList();
  }
  return DepartmentDoctorConfig.getDoctorsForDepartment(department,
      activeOnly: false);
});

/// StateNotifier for admin management of department doctors.
final adminDoctorsProvider = StateNotifierProvider<AdminDoctorsNotifier,
    AsyncValue<List<DepartmentDoctor>>>((ref) {
  final repo = ref.watch(departmentDoctorRepositoryProvider);
  return AdminDoctorsNotifier(repo);
});

class AdminDoctorsNotifier
    extends StateNotifier<AsyncValue<List<DepartmentDoctor>>> {
  final DepartmentDoctorRepository _repository;

  AdminDoctorsNotifier(this._repository) : super(const AsyncValue.loading()) {
    loadDoctors();
  }

  Future<void> loadDoctors() async {
    state = const AsyncValue.loading();
    try {
      final doctors = await _repository.fetchDoctors();
      state = AsyncValue.data(doctors);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> addDoctor({
    required String fullName,
    required String department,
    String? specialty,
  }) async {
    try {
      final created = await _repository.createDoctor(
        fullName: fullName,
        department: department,
        specialty: specialty,
      );
      final current = state.valueOrNull ?? [];
      final updated = [...current, created];
      state = AsyncValue.data(updated);
    } catch (e) {
      debugPrint('Error adding doctor: $e');
      rethrow;
    }
  }

  Future<void> editDoctor({
    required String id,
    required String fullName,
    required String department,
    String? specialty,
    required bool isActive,
  }) async {
    try {
      final updatedDoctor = await _repository.updateDoctor(
        id: id,
        fullName: fullName,
        department: department,
        specialty: specialty,
        isActive: isActive,
      );
      final current = state.valueOrNull ?? [];
      final updatedList = current.map((d) {
        if ((id.isNotEmpty && d.id == id) ||
            (d.fullName.toLowerCase() == fullName.toLowerCase() &&
                d.department.toLowerCase() == department.toLowerCase())) {
          return updatedDoctor;
        }
        return d;
      }).toList();
      state = AsyncValue.data(updatedList);
    } catch (e) {
      debugPrint('Error editing doctor: $e');
      rethrow;
    }
  }

  Future<void> toggleDoctorActive(DepartmentDoctor doctor) async {
    await editDoctor(
      id: doctor.id,
      fullName: doctor.fullName,
      department: doctor.department,
      specialty: doctor.specialty,
      isActive: !doctor.isActive,
    );
  }
}
