import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  /// Creates a new user via RPC function that handles both auth and profile creation
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
      // Use RPC function to create user with admin privileges
      await _supabase.rpc(
        'create_user_by_admin',
        params: {
          'p_email': email,
          'p_password': password,
          'p_full_name': fullName,
          'p_phone_number': phoneNumber,
          'p_department_id': departmentId,
          'p_designation': designation,
          'p_role': role,
          'p_salary': salary,
          'p_joining_date': joiningDate?.toIso8601String().split('T').first,
        },
      );
    } catch (e) {
      if (e.toString().contains('duplicate key') ||
          e.toString().contains('already registered')) {
        throw Exception('This email is already registered.');
      }
      if (e.toString().contains('Only active admins')) {
        throw Exception('You do not have permission to create users.');
      }
      debugPrint('Error creating user: $e');
      rethrow;
    }
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
