import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/auth_provider.dart';
import '../screens/role_selection_screen.dart';
import '../../admin/screens/admin_dashboard_screen.dart';
import '../../staff_portal/screens/staff_dashboard_screen.dart';

/// Central authentication routing wrapper.
///
/// Flow:
///   App Start
///     → Listen to Supabase auth state
///     → No session → RoleSelectionScreen
///     → Session exists → fetch profile
///       → profile.role == 'admin' && is_active → AdminDashboardScreen
///       → profile.role == 'staff' && is_active → StaffDashboardScreen
///       → inactive / missing / wrong role → sign out + error message
class AuthWrapper extends ConsumerWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authStateAsync = ref.watch(authStateProvider);
    debugPrint(
      '[LOGOUT] AuthWrapper built; authState='
      '${authStateAsync.hasError ? 'error' : authStateAsync.isLoading ? 'loading' : 'data'}',
    );

    return authStateAsync.when(
      data: (authState) {
        final session = authState.session;
        debugPrint(
          '[LOGOUT] AuthWrapper auth state event=${authState.event}; '
          'sessionPresent=${session != null}',
        );

        if (session == null) {
          debugPrint('[LOGOUT] AuthWrapper showing RoleSelectionScreen');
          return const RoleSelectionScreen();
        }

        final roleAsync = ref.watch(currentUserRoleProvider);
        debugPrint(
          '[LOGOUT] AuthWrapper role state='
          '${roleAsync.hasError ? 'error' : roleAsync.isLoading ? 'loading' : 'data'}',
        );

        return roleAsync.when(
          data: (role) {
            switch (role) {
              case 'admin':
                return const AdminDashboardScreen();
              case 'staff':
                return const StaffDashboardScreen();
              case 'inactive':
                _signOutWithMessage(
                  context,
                  'Your account is currently inactive. Please contact an administrator.',
                );
                return _loadingScaffold();
              case null:
                _signOutWithMessage(
                  context,
                  'Your account is authenticated, but your clinic profile could not be found. '
                  'Please contact your administrator.',
                );
                return _loadingScaffold();
              default:
                _signOutWithMessage(
                  context,
                  'Your account has an unrecognised role. Please contact your administrator.',
                );
                return _loadingScaffold();
            }
          },
          loading: _loadingScaffold,
          error: (error, stackTrace) {
            debugPrint('AuthWrapper role resolution error: $error');
            _signOutWithMessage(
              context,
              'Failed to verify your account. Please sign in again.',
            );
            return _loadingScaffold();
          },
        );
      },
      loading: _loadingScaffold,
      error: (error, stackTrace) => const RoleSelectionScreen(),
    );
  }

  Widget _loadingScaffold() {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }

  void _signOutWithMessage(BuildContext context, String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 6),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Supabase.instance.client.auth.signOut();
    });
  }
}
