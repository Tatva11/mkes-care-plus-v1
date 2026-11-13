import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/clinic_location_constants.dart';
import '../../../core/services/location_verification_service.dart';
import '../../../core/services/push_notification_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../providers/auth_provider.dart';
import '../providers/staff_location_provider.dart';
import '../repositories/auth_repository.dart';

/// Screen presented to staff members who are outside the clinic's 200-metre
/// geofence or whose location cannot be verified.
class StaffAccessRestrictedScreen extends ConsumerStatefulWidget {
  const StaffAccessRestrictedScreen({
    super.key,
    required this.reason,
    required this.message,
    this.distanceMeters,
    this.accuracyMeters,
    this.isVerifying = false,
  });

  final LocationFailureReason reason;
  final String message;
  final double? distanceMeters;
  final double? accuracyMeters;
  final bool isVerifying;

  @override
  ConsumerState<StaffAccessRestrictedScreen> createState() =>
      _StaffAccessRestrictedScreenState();
}

class _StaffAccessRestrictedScreenState
    extends ConsumerState<StaffAccessRestrictedScreen> {
  bool _isSigningOut = false;

  Future<void> _handleSignOut() async {
    if (_isSigningOut) return;

    setState(() {
      _isSigningOut = true;
    });

    try {
      // 1. Pop any modal dialogs or pushed child routes back to root
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true)
            .popUntil((route) => route.isFirst);
      }

      // 2. Best-effort server geofence cleanup (with short 2s timeout)
      try {
        await ref
            .read(locationVerificationServiceProvider)
            .clearServerGeofence()
            .timeout(const Duration(seconds: 2));
      } catch (e) {
        debugPrint('[SIGNOUT] Server geofence clear skipped/timed out: $e');
      }

      // 3. Best-effort push notification cleanup
      try {
        await ref
            .read(pushNotificationServiceProvider)
            .deactivateToken()
            .timeout(const Duration(seconds: 2));
      } catch (e) {
        debugPrint('[SIGNOUT] Push token deactivate skipped/timed out: $e');
      }

      // 4. Supabase signOut with local fallback to avoid infinite hanging
      try {
        await ref
            .read(authRepositoryProvider)
            .signOut()
            .timeout(const Duration(seconds: 4));
      } catch (e) {
        debugPrint(
            '[SIGNOUT] Remote signOut failed/timed out, forcing local signout: $e');
        await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
      }

      // 5. Invalidate auth and profile providers, reset location state
      ref.invalidate(currentUserRoleProvider);
      ref.invalidate(currentProfileProvider);
      ref.invalidate(currentUserProvider);
      ref.invalidate(authStateProvider);
      ref.read(staffLocationProvider.notifier).resetState();
    } catch (e) {
      debugPrint('[SIGNOUT] Error during restricted screen sign-out: $e');
      // Even on complete error, force local sign-out to release UI
      try {
        await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
        ref.read(staffLocationProvider.notifier).resetState();
      } catch (_) {}
    } finally {
      if (mounted) {
        setState(() {
          _isSigningOut = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 600;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isDesktop
                  ? AppSpacing.marginDesktop
                  : AppSpacing.marginMobile,
              vertical: AppSpacing.md,
            ),
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: AppSpacing.maxContentWidth),
              child: Card(
                elevation: 0,
                color: AppColors.surfaceContainerLowest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  side: const BorderSide(color: AppColors.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: AppSpacing.md),
                      _buildStatusBadge(),
                      const SizedBox(height: AppSpacing.md),
                      _buildProximityMetrics(),
                      const SizedBox(height: AppSpacing.md),
                      _buildGuidanceBox(),
                      const SizedBox(height: AppSpacing.lg),
                      _buildActionButtons(context),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.errorContainer.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Icon(
              Icons.location_off_rounded,
              color: AppColors.error,
              size: 38,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'MKES CARE+',
          style: AppTypography.labelCaps.copyWith(
            color: AppColors.primary,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Clinic Proximity Required',
          style: AppTypography.headlineMd.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildStatusBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.errorContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.lock_outline_rounded,
              size: 16,
              color: AppColors.onErrorContainer,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              'ACCESS RESTRICTED — ${ClinicLocationConstants.allowedRadiusMeters.toInt()}M GEOFENCE',
              style: AppTypography.labelCaps.copyWith(
                color: AppColors.onErrorContainer,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProximityMetrics() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        children: [
          _buildMetricRow(
            icon: Icons.adjust_rounded,
            iconColor: AppColors.primary,
            label: 'Permitted Radius',
            value:
                '${ClinicLocationConstants.allowedRadiusMeters.toInt()} metres',
            isHighlight: true,
          ),
          const Divider(height: 16, color: AppColors.outlineVariant),
          _buildMetricRow(
            icon: Icons.navigation_rounded,
            iconColor: widget.distanceMeters != null &&
                    widget.distanceMeters! <=
                        ClinicLocationConstants.allowedRadiusMeters
                ? Colors.green
                : AppColors.error,
            label: 'Measured Distance',
            value: widget.distanceMeters != null
                ? '${widget.distanceMeters!.toStringAsFixed(1)} metres'
                : 'Unavailable',
            isHighlight: false,
          ),
          if (widget.accuracyMeters != null) ...[
            const Divider(height: 16, color: AppColors.outlineVariant),
            _buildMetricRow(
              icon: Icons.gps_fixed_rounded,
              iconColor: AppColors.onSurfaceVariant,
              label: 'GPS Accuracy',
              value: '±${widget.accuracyMeters!.toStringAsFixed(1)} metres',
              isHighlight: false,
            ),
          ],
          const Divider(height: 16, color: AppColors.outlineVariant),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.business_rounded,
                size: 16,
                color: AppColors.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  ClinicLocationConstants.clinicAddress,
                  style: AppTypography.bodySm.copyWith(
                    fontSize: 12,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required bool isHighlight,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            label,
            style: AppTypography.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          value,
          style: AppTypography.labelCaps.copyWith(
            fontWeight: FontWeight.bold,
            color: isHighlight ? AppColors.primary : AppColors.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildGuidanceBox() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: AppColors.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              widget.message,
              style: AppTypography.bodySm.copyWith(
                color: AppColors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final notifier = ref.read(staffLocationProvider.notifier);

    final showSettings = widget.reason ==
            LocationFailureReason.permissionPermanentlyDenied ||
        widget.reason == LocationFailureReason.serviceDisabled;

    final isBusy = widget.isVerifying || _isSigningOut;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton(
          onPressed: isBusy ? null : () => notifier.verifyLocation(),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            elevation: 0,
          ),
          child: widget.isVerifying
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.refresh_rounded, size: 18),
                    SizedBox(width: AppSpacing.xs),
                    Text(
                      'Verify Location / Retry',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
        ),
        if (showSettings) ...[
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            onPressed: isBusy
                ? null
                : () {
                    if (widget.reason ==
                        LocationFailureReason.serviceDisabled) {
                      notifier.openLocationSettings();
                    } else {
                      notifier.openAppSettings();
                    }
                  },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              side: const BorderSide(color: AppColors.outline),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
            ),
            child: Text(
              widget.reason == LocationFailureReason.serviceDisabled
                  ? 'Open Location Settings'
                  : 'Open App Settings',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: isBusy ? null : _handleSignOut,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.onSurfaceVariant,
          ),
          child: _isSigningOut
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    SizedBox(width: AppSpacing.xs),
                    Text(
                      'Signing out...',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                )
              : const Text('Sign Out'),
        ),
      ],
    );
  }
}
