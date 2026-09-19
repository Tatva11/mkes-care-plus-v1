import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile_model.dart';
import '../repositories/auth_repository.dart';
import '../repositories/profile_repository.dart';

// ---------------------------------------------------------------------------
// Auth state stream — listens to Supabase auth state changes.
// ---------------------------------------------------------------------------
final authStateProvider = StreamProvider<AuthState>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);
  return authRepository.authStateChanges;
});

// ---------------------------------------------------------------------------
// Current Supabase user — null when unauthenticated.
// ---------------------------------------------------------------------------
final currentUserProvider = Provider<User?>((ref) {
  final authState = ref.watch(authStateProvider).value;
  return authState?.session?.user;
});

// ---------------------------------------------------------------------------
// Current profile — fetches from Supabase when user is authenticated.
// Returns null when loading/unauthenticated.
// Throws on network errors.
// ---------------------------------------------------------------------------
final currentProfileProvider = FutureProvider<ProfileModel?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;

  final profileRepo = ref.watch(profileRepositoryProvider);
  return profileRepo.fetchProfile(user.id);
});

// ---------------------------------------------------------------------------
// Convenience: role string derived from the profile.
// Returns:
//   - 'admin'    — authenticated active admin
//   - 'staff'    — authenticated active staff
//   - 'inactive' — authenticated but account is inactive
//   - null       — profile missing or error
// ---------------------------------------------------------------------------
final currentUserRoleProvider = FutureProvider<String?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;

  try {
    final response = await Supabase.instance.client
        .from('profiles')
        .select('role, is_active')
        .eq('id', user.id)
        .maybeSingle();

    if (response == null) {
      debugPrint('currentUserRoleProvider: no profile for user ${user.id}');
      return null;
    }

    final isActive = response['is_active'] as bool? ?? false;
    if (!isActive) return 'inactive';

    return response['role'] as String?;
  } catch (e) {
    debugPrint('currentUserRoleProvider error: $e');
    rethrow;
  }
});

// ---------------------------------------------------------------------------
// Auth actions notifier — exposes login with role enforcement, and logout.
// ---------------------------------------------------------------------------

/// The intended login context (which portal the user is trying to enter).
enum LoginContext { admin, staff }

/// Result of a login attempt.
sealed class LoginResult {}

class LoginSuccess extends LoginResult {
  final ProfileModel profile;
  LoginSuccess(this.profile);
}

class LoginFailure extends LoginResult {
  final String message;
  LoginFailure(this.message);
}

/// Performs a login and enforces role requirements.
///
/// [email] and [password] are the credentials.
/// [context] (LoginContext) enforces that the user's role matches the portal.
/// [ref] must be a [WidgetRef] from a ConsumerWidget/ConsumerStatefulWidget.
Future<LoginResult> performRoleEnforcedLogin({
  required String email,
  required String password,
  required LoginContext context,
  required WidgetRef ref,
}) async {
  final authRepo = ref.read(authRepositoryProvider);
  final profileRepo = ref.read(profileRepositoryProvider);

  try {
    // 1. Supabase authentication.
    final authResponse = await Supabase.instance.client.auth
        .signInWithPassword(email: email, password: password);

    if (authResponse.user == null) {
      return LoginFailure('Login failed. Please check your credentials.');
    }

    // 2. Profile lookup.
    final profile = await profileRepo.fetchProfile(authResponse.user!.id);

    if (profile == null) {
      // Profile missing — sign out to prevent stale session.
      await authRepo.signOut();
      return LoginFailure(
        'Your account is authenticated, but your clinic profile could not be found. '
        'Please contact your administrator.',
      );
    }

    // 3. Active account check.
    if (!profile.isActive) {
      await authRepo.signOut();
      return LoginFailure(
        'Your account is currently inactive. Please contact an administrator.',
      );
    }

    // 4. Role enforcement.
    final expectedRole = context == LoginContext.admin ? 'admin' : 'staff';
    if (profile.role != expectedRole) {
      await authRepo.signOut();

      if (context == LoginContext.admin) {
        return LoginFailure(
          'Access denied. This portal is for administrators only. '
          'Please use the Staff portal if you are a staff member.',
        );
      } else {
        return LoginFailure(
          'Access denied. This portal is for staff members only. '
          'Please use the Admin portal if you are an administrator.',
        );
      }
    }

    // 5. Success.
    return LoginSuccess(profile);
  } on AuthException catch (e) {
    // Ensure session is cleared on auth failure.
    try {
      await authRepo.signOut();
    } catch (_) {}

    // Log the raw GoTrue error for debugging (status code + exact message).
    // This is the exact error returned by Supabase Auth — not the friendly UI copy.
    debugPrint(
      'performRoleEnforcedLogin AuthException '
      '[status=${e.statusCode}]: "${e.message}"',
    );

    return LoginFailure(_friendlyAuthError(e.message));
  } catch (e) {
    // Ensure session is cleared on unexpected failure.
    try {
      await authRepo.signOut();
    } catch (_) {}

    debugPrint('performRoleEnforcedLogin unexpected error: $e');

    if (e.toString().toLowerCase().contains('network') ||
        e.toString().toLowerCase().contains('socket') ||
        e.toString().toLowerCase().contains('connection')) {
      return LoginFailure(
        'Unable to connect. Please check your internet connection and try again.',
      );
    }

    return LoginFailure('An unexpected error occurred. Please try again.');
  }
}

/// Converts technical Supabase auth errors to user-friendly messages.
String _friendlyAuthError(String message) {
  final lower = message.toLowerCase();
  if (lower.contains('invalid login credentials') ||
      lower.contains('invalid_credentials') ||
      lower.contains('wrong password') ||
      lower.contains('user not found')) {
    return 'Incorrect email or password. Please try again.';
  }
  if (lower.contains('email not confirmed')) {
    return 'Please verify your email address before logging in.';
  }
  if (lower.contains('too many requests') || lower.contains('rate limit')) {
    return 'Too many login attempts. Please wait a moment and try again.';
  }
  if (lower.contains('network') ||
      lower.contains('socket') ||
      lower.contains('connection')) {
    return 'Unable to connect. Please check your internet connection and try again.';
  }
  return 'Login failed. Please check your credentials and try again.';
}
