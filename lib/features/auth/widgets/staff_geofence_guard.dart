import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/clinic_location_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../providers/staff_location_provider.dart';
import '../screens/staff_access_restricted_screen.dart';

/// Guard widget that wraps staff views and ensures the user's device is physically
/// verified within the clinic's 200-metre geofence before presenting protected data.
class StaffGeofenceGuard extends ConsumerStatefulWidget {
  const StaffGeofenceGuard({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  ConsumerState<StaffGeofenceGuard> createState() => _StaffGeofenceGuardState();
}

class _StaffGeofenceGuardState extends ConsumerState<StaffGeofenceGuard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(staffLocationProvider);
      if (state is StaffLocationInitial) {
        ref.read(staffLocationProvider.notifier).verifyLocation();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final locationState = ref.watch(staffLocationProvider);

    return switch (locationState) {
      StaffLocationInitial() || StaffLocationVerifying() =>
        _buildVerifyingScaffold(),
      StaffLocationVerified() => widget.child,
      StaffLocationRestricted(
        reason: final reason,
        message: final message,
        distanceMeters: final dist,
        accuracyMeters: final acc,
      ) =>
        StaffAccessRestrictedScreen(
          reason: reason,
          message: message,
          distanceMeters: dist,
          accuracyMeters: acc,
        ),
    };
  }

  Widget _buildVerifyingScaffold() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/mkes_logo.png',
                width: 88,
                height: 88,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: AppSpacing.md),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Verifying Clinic Location',
                style: AppTypography.headlineMd.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Validating ${ClinicLocationConstants.allowedRadiusMeters.toInt()}-metre physical proximity...',
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
