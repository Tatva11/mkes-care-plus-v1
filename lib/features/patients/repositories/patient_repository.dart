import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import '../models/patient_model.dart';

final patientRepositoryProvider = Provider<PatientRepository>((ref) {
  return PatientRepository(ref.watch(supabaseProvider));
});

class PatientRepository {
  static final _digitsRegex = RegExp(r'\D');
  final SupabaseClient _supabase;
  final Map<String, PatientModel> _patientCache = {};

  PatientRepository(this._supabase);

  /// Returns an unmodifiable view of cached patients or gets a cached patient by ID.
  PatientModel? getCachedPatient(String id) => _patientCache[id.trim()];

  /// Populate cache with a single patient.
  void cachePatient(PatientModel patient) {
    _patientCache[patient.id] = patient;
  }

  /// Populate cache with multiple patients.
  void cachePatients(Iterable<PatientModel> patients) {
    for (final p in patients) {
      _patientCache[p.id] = p;
    }
  }

  /// Clear in-memory patient cache.
  void clearCache() {
    _patientCache.clear();
  }

  /// Fetch paginated list of patients from Supabase with search and department filtering.
  /// Uses the high-performance [search_patients] RPC when available, falling back to
  /// paginated direct queries with indexed range constraints.
  Future<List<PatientModel>> fetchPatients({
    String? department,
    String? searchQuery,
    int limit = 50,
    int offset = 0,
  }) async {
    final cleanDept = department?.trim().toLowerCase();
    if (cleanDept != null &&
        cleanDept.isNotEmpty &&
        cleanDept != 'all' &&
        cleanDept != 'eye' &&
        cleanDept != 'dental') {
      throw ArgumentError.value(
          department, 'department', 'Must be eye, dental, or all.');
    }

    final normalizedSearch = searchQuery?.trim();
    final effectiveLimit = limit.clamp(1, 200);
    final effectiveOffset = offset < 0 ? 0 : offset;

    // 1. Try high-performance server-side search RPC
    try {
      final rpcParams = <String, dynamic>{
        'p_department': (cleanDept == null || cleanDept.isEmpty || cleanDept == 'all') ? null : cleanDept,
        'p_query': (normalizedSearch == null || normalizedSearch.isEmpty) ? null : normalizedSearch,
        'p_limit': effectiveLimit,
        'p_offset': effectiveOffset,
      };

      final response = await _supabase.rpc('search_patients', params: rpcParams);
      if (response is List) {
        final patients = response
            .map((json) => PatientModel.fromJson(json as Map<String, dynamic>))
            .toList();
        cachePatients(patients);
        debugPrint(
          'PatientRepository.fetchPatients [RPC] dept=$cleanDept query="$normalizedSearch" limit=$effectiveLimit returned=${patients.length}',
        );
        return patients;
      }
    } catch (e) {
      debugPrint('PatientRepository.fetchPatients RPC failed, falling back to direct query: $e');
    }

    // 2. Direct query fallback with strict server-side range pagination and canonical digit matching
    var query = _supabase.from('patients').select();

    if (cleanDept != null && cleanDept.isNotEmpty && cleanDept != 'all') {
      query = query.eq('department', cleanDept);
    }

    if (normalizedSearch != null && normalizedSearch.isNotEmpty) {
      final sanitizedSearch = normalizedSearch.replaceAll(',', ' ').trim();
      if (sanitizedSearch.isNotEmpty) {
        final digits = sanitizedSearch.replaceAll(_digitsRegex, '');
        final orFilters = <String>[
          'name.ilike.%$sanitizedSearch%',
          'patient_number.ilike.%$sanitizedSearch%',
          'mobile.ilike.%$sanitizedSearch%',
        ];
        if (digits.isNotEmpty) {
          orFilters.add('patient_number.ilike.%$digits%');
          orFilters.add('patient_number.eq.$digits');
        }
        query = query.or(orFilters.join(','));
      }
    }

    final response = await query
        .order('name', ascending: true)
        .order('patient_number', ascending: true)
        .range(effectiveOffset, effectiveOffset + effectiveLimit - 1);

    final patients = (response as List)
        .map((json) => PatientModel.fromJson(json as Map<String, dynamic>))
        .toList();
    cachePatients(patients);
    debugPrint(
      'PatientRepository.fetchPatients [Fallback] dept=$cleanDept returned=${patients.length}',
    );
    return patients;
  }

  /// Fetch only patients registered today in clinic local time.
  /// Prevents loading all 17,682 records on the dashboard just for daily metrics.
  Future<List<PatientModel>> fetchTodayRegisteredPatients({
    String? department,
  }) async {
    final cleanDept = department?.trim().toLowerCase();
    try {
      final response = await _supabase.rpc(
        'get_today_registered_patients',
        params: {
          'p_department': (cleanDept == null || cleanDept.isEmpty || cleanDept == 'all') ? null : cleanDept,
        },
      );
      if (response is List) {
        final patients = response
            .map((json) => PatientModel.fromJson(json as Map<String, dynamic>))
            .toList();
        cachePatients(patients);
        return patients;
      }
    } catch (e) {
      debugPrint('PatientRepository.fetchTodayRegisteredPatients RPC fallback: $e');
    }

    // Direct fallback
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day).toUtc().toIso8601String();
    var query = _supabase.from('patients').select().gte('created_at', todayStart);
    if (cleanDept != null && cleanDept.isNotEmpty && cleanDept != 'all') {
      query = query.eq('department', cleanDept);
    }
    final response = await query.order('created_at', ascending: false).limit(100);
    final patients = (response as List)
        .map((json) => PatientModel.fromJson(json as Map<String, dynamic>))
        .toList();
    cachePatients(patients);
    return patients;
  }

  /// Create a new patient in the database.
  Future<PatientModel> createPatient(PatientModel patient) async {
    final department = patient.department?.trim().toLowerCase();
    if (department != 'eye' && department != 'dental') {
      throw ArgumentError.value(
          patient.department, 'department', 'Must be eye or dental.');
    }

    final response = await _supabase.rpc(
      'create_patient',
      params: {
        'p_name': patient.name,
        'p_department': department,
        'p_dob': patient.dob?.toIso8601String().split('T').first,
        'p_address': patient.address,
        'p_mobile': patient.mobile,
        'p_reference': patient.reference,
        'p_visit_date': DateTime.now().toIso8601String().split('T').first,
      },
    );

    final map = response is Map<String, dynamic>
        ? response
        : Map<String, dynamic>.from(response as Map);
    final created = PatientModel.fromJson(map);
    cachePatient(created);
    return created;
  }

  /// Fetches the preview of the next sequential patient number for a given department.
  /// This operation is strictly read-only and does NOT allocate or reserve the number.
  Future<String> getNextPatientNumber(String department) async {
    final cleanDept = department.trim().toLowerCase();
    if (cleanDept != 'eye' && cleanDept != 'dental') {
      throw ArgumentError.value(
          department, 'department', 'Must be eye or dental.');
    }

    try {
      final response = await _supabase.rpc(
        'get_next_patient_number',
        params: {'p_department': cleanDept},
      );
      if (response != null && response.toString().trim().isNotEmpty) {
        return response.toString().trim();
      }
    } catch (e) {
      debugPrint('PatientRepository.getNextPatientNumber RPC error: $e');
    }

    // Direct fallback if RPC is unavailable
    final prefix = cleanDept == 'eye' ? 'E' : 'D';
    try {
      final rows = await _supabase
          .from('patients')
          .select('patient_number')
          .eq('department', cleanDept);

      int maxNum = 0;
      final numberPattern = RegExp(r'^[A-Za-z]*-?(\d{1,9})');
      for (final row in rows as List) {
        final pNum = row['patient_number']?.toString().trim() ?? '';
        final match = numberPattern.firstMatch(pNum);
        if (match != null) {
          final val = int.tryParse(match.group(1)!) ?? 0;
          if (val > maxNum) maxNum = val;
        }
      }
      final nextNum = maxNum + 1;
      return '$prefix-${nextNum < 1000 ? nextNum.toString().padLeft(3, '0') : nextNum.toString()}';
    } catch (e) {
      debugPrint('PatientRepository.getNextPatientNumber fallback error: $e');
      return '$prefix-001';
    }
  }

  /// Permanently deletes a patient record.
  /// Staff can delete only patients belonging to their assigned department.
  /// Admins can delete across all departments. Geofence restrictions are enforced.
  Future<bool> deletePatient(String id) async {
    final cleanId = id.trim();
    if (cleanId.isEmpty) {
      throw ArgumentError('Patient ID cannot be empty for deletion.');
    }

    try {
      final response = await _supabase.rpc(
        'delete_patient',
        params: {'p_patient_id': cleanId},
      );
      _patientCache.remove(cleanId);
      return response == true;
    } catch (e) {
      debugPrint(
          'PatientRepository.deletePatient RPC failed, falling back to direct DELETE: $e');
      await _supabase.from('patients').delete().eq('id', cleanId);
      _patientCache.remove(cleanId);
      return true;
    }
  }

  /// Fetch a single patient by ID from cache or Supabase.
  /// Eliminates redundant network requests when patient has already been loaded.
  Future<PatientModel> getPatient(String id) async {
    final cleanId = id.trim();
    if (cleanId.isEmpty) {
      throw ArgumentError('Patient ID cannot be empty');
    }

    // Fast-path: return from in-memory cache (0ms)
    final cached = _patientCache[cleanId];
    if (cached != null) {
      return cached;
    }

    final response = await _supabase
        .from('patients')
        .select()
        .eq('id', cleanId)
        .maybeSingle();

    if (response == null) {
      throw Exception(
        'Patient record not found (ID: $cleanId). It may have been removed or access is restricted.',
      );
    }
    final patient = PatientModel.fromJson(response);
    cachePatient(patient);
    return patient;
  }

  /// Update an existing patient in the database.
  /// Modifies only: name, mobile, department, dob, address, reference, updated_at.
  /// Patient number is strictly preserved.
  Future<PatientModel> updatePatient(PatientModel patient) async {
    final cleanId = patient.id.trim();
    if (cleanId.isEmpty) {
      throw ArgumentError('Patient ID cannot be empty for an update.');
    }

    final department = patient.department?.trim().toLowerCase();
    if (department != null && department.isNotEmpty) {
      if (department != 'eye' && department != 'dental') {
        throw ArgumentError.value(
            patient.department, 'department', 'Must be eye or dental.');
      }
    }

    final updateData = <String, dynamic>{
      'name': patient.name.trim(),
      'mobile': patient.mobile,
      'department': department,
      'dob': patient.dob?.toIso8601String().split('T').first,
      'address': patient.address,
      'reference': patient.reference,
      'whatsapp_opt_out': patient.whatsappOptOut,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    final response = await _supabase
        .from('patients')
        .update(updateData)
        .eq('id', cleanId)
        .select()
        .maybeSingle();

    if (response == null) {
      // Differentiate between patient record not found and RLS authorization failure
      final existing = await _supabase
          .from('patients')
          .select('id')
          .eq('id', cleanId)
          .maybeSingle();

      if (existing == null) {
        throw Exception(
          'Patient record not found (ID: $cleanId). It may have been deleted.',
        );
      } else {
        throw Exception(
          'Permission denied: You do not have authorization to update patient details. Only clinic administrators and authorized staff can edit patient records.',
        );
      }
    }

    final updated = PatientModel.fromJson(response);
    cachePatient(updated);
    return updated;
  }

  /// Toggle or set WhatsApp opt-out preference for a patient.
  Future<bool> setWhatsAppOptOut(String patientId, bool optOut) async {
    final cleanId = patientId.trim();
    if (cleanId.isEmpty) {
      throw ArgumentError('Patient ID cannot be empty');
    }

    await _supabase
        .from('patients')
        .update({
          'whatsapp_opt_out': optOut,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', cleanId);

    // Synchronize in-memory cache to prevent serving stale whatsapp_opt_out state
    // upon subsequent getPatient() calls after provider invalidation.
    final cached = _patientCache[cleanId];
    if (cached != null) {
      _patientCache[cleanId] = cached.copyWith(
        whatsappOptOut: optOut,
        updatedAt: DateTime.now(),
      );
    }
    return optOut;
  }
}

