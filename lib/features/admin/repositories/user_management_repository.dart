import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';

import '../../../core/providers/supabase_provider.dart';
import '../models/user_profile.dart';

final userManagementRepositoryProvider =
    Provider<UserManagementRepository>((ref) {
  return UserManagementRepository(ref.watch(supabaseProvider));
});

class UserManagementRepository {
  final SupabaseClient _supabase;

  UserManagementRepository(this._supabase);

  Future<List<UserProfile>> fetchUsers() async {
    final response = await _supabase
        .from('profiles')
        .select('*, department:departments(name)')
        .order('created_at', ascending: false);

    return (response as List)
        .map((json) => UserProfile.fromJson(json))
        .toList();
  }

  /// Creates a new user via the [create-staff-user] Edge Function.
  ///
  /// The Edge Function calls the GoTrue Admin API to create the auth user
  /// (correct bcrypt hashing), then inserts the profiles row. The SQL RPC
  /// `create_user_by_admin` is no longer used for auth-user creation because
  /// it used pgcrypto.crypt() which GoTrue cannot verify.
  Future<void> createUser({
    required String fullName,
    required String email,
    required String password,
    String? phoneNumber,
    String? departmentId,
    String? designation,
    required String role,
    double? salary,
    DateTime? joiningDate,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'create-staff-user',
        body: {
          'p_email': email,
          'p_password': password,
          'p_full_name': fullName,
          if (phoneNumber != null) 'p_phone_number': phoneNumber,
          if (departmentId != null) 'p_department_id': departmentId,
          if (designation != null) 'p_designation': designation,
          'p_role': role,
          if (salary != null) 'p_salary': salary,
          if (joiningDate != null)
            'p_joining_date': joiningDate.toIso8601String().split('T').first,
        },
      );

      // functions.invoke throws FunctionsException on HTTP 4xx/5xx,
      // but decode any error message from the JSON body for clarity.
      final responseBody = response.data;
      if (responseBody is Map && responseBody.containsKey('error')) {
        final serverError =
            responseBody['error']?.toString() ?? 'Unknown error';
        debugPrint('create-staff-user Edge Function error: $serverError');
        _throwFriendlyError(serverError);
      }
    } on FunctionException catch (e) {
      debugPrint('FunctionException creating user: ${e.details}');
      // Try to decode the JSON error body the Edge Function returns
      String errorText = e.details?.toString() ?? e.toString();
      try {
        final decoded = jsonDecode(errorText);
        if (decoded is Map && decoded['error'] != null) {
          errorText = decoded['error'].toString();
        }
      } catch (_) {}
      _throwFriendlyError(errorText);
    } catch (e) {
      debugPrint('Error creating user: $e');
      _throwFriendlyError(_errorText(e));
    }
  }

  /// Maps raw server error strings to user-facing exceptions.
  void _throwFriendlyError(String errorText) {
    final lower = errorText.toLowerCase();
    if (lower.contains('duplicate') ||
        lower.contains('already registered') ||
        lower.contains('already been registered') ||
        lower.contains('user already registered') ||
        lower.contains('email_exists')) {
      throw Exception('This email is already registered.');
    }
    if (lower.contains('forbidden') ||
        lower.contains('only active admins') ||
        lower.contains('insufficient_privilege')) {
      throw Exception('You do not have permission to create users.');
    }
    if (lower.contains('department') &&
        (lower.contains('foreign key') || lower.contains('violates'))) {
      throw Exception(
          'The selected department is no longer valid. Please select it again.');
    }
    throw Exception(errorText);
  }

  String _errorText(Object error) {
    if (error is PostgrestException) {
      final parts = <String>[error.message];
      if (error.details is String && (error.details as String).isNotEmpty) {
        parts.add(error.details as String);
      }
      if (error.hint != null && error.hint!.isNotEmpty) {
        parts.add(error.hint!);
      }
      return parts.join(' ');
    }
    if (error is FunctionException) {
      return error.details?.toString() ?? error.toString();
    }
    return error.toString().replaceFirst('Exception: ', '');
  }

  Future<void> updateUser(String id, Map<String, dynamic> updates) async {
    await _supabase.from('profiles').update(updates).eq('id', id);
  }

  Future<void> toggleUserStatus(String id, bool isActive) async {
    await _supabase
        .from('profiles')
        .update({'is_active': isActive}).eq('id', id);
  }

  Future<void> deleteUser(String id) async {
    // Usually, you should delete from auth.users (which cascades to profiles),
    // but client-side delete requires an RPC or Edge Function.
    await _supabase.rpc('delete_user_by_admin', params: {'target_user_id': id});
  }
}
