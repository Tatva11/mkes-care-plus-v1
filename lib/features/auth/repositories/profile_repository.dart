import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/supabase_provider.dart';
import '../models/profile_model.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(supabaseProvider));
});

class ProfileRepository {
  final SupabaseClient _supabase;

  ProfileRepository(this._supabase);

  /// Fetches the profile for the given user ID.
  /// Returns null if the profile does not exist.
  Future<ProfileModel?> fetchProfile(String userId) async {
    try {
        final response = await _supabase
          .from('profiles')
          .select('*, department:departments(name)')
          .eq('id', userId)
          .maybeSingle();

      if (response == null) return null;
      return ProfileModel.fromJson(response);
    } catch (e) {
      debugPrint('ProfileRepository.fetchProfile error: $e');
      rethrow;
    }
  }

  /// Updates the current user's own profile fields.
  Future<void> updateOwnProfile({
    required String userId,
    String? fullName,
    String? phoneNumber,
  }) async {
    final updates = <String, dynamic>{};
    if (fullName != null) updates['full_name'] = fullName;
    if (phoneNumber != null) updates['phone_number'] = phoneNumber;

    if (updates.isEmpty) return;

    await _supabase.from('profiles').update(updates).eq('id', userId);
  }
}
