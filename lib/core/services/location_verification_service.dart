import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/clinic_location_constants.dart';
import '../providers/supabase_provider.dart';

/// Categorized failure reasons for location verification.
enum LocationFailureReason {
  serviceDisabled,
  permissionDenied,
  permissionPermanentlyDenied,
  inaccurateLocation,
  outsideRadius,
  timeoutOrUnavailable,
  unauthenticated,
  serverError,
}

/// Result of a staff location verification attempt.
sealed class LocationVerificationResult {
  const LocationVerificationResult();
}

class LocationVerificationSuccess extends LocationVerificationResult {
  final double distanceMeters;
  final double accuracyMeters;
  final DateTime verifiedAt;
  final DateTime expiresAt;
  final bool isAdmin;
  final bool isBypass;

  const LocationVerificationSuccess({
    required this.distanceMeters,
    required this.accuracyMeters,
    required this.verifiedAt,
    required this.expiresAt,
    this.isAdmin = false,
    this.isBypass = false,
  });

  /// Whether this verification result is still unexpired.
  bool get isFresh => DateTime.now().isBefore(expiresAt);
}

class LocationVerificationFailure extends LocationVerificationResult {
  final LocationFailureReason reason;
  final String userMessage;
  final double? distanceMeters;
  final double? accuracyMeters;

  const LocationVerificationFailure({
    required this.reason,
    required this.userMessage,
    this.distanceMeters,
    this.accuracyMeters,
  });
}

/// Riverpod provider for the [LocationVerificationService].
final locationVerificationServiceProvider =
    Provider<LocationVerificationService>((ref) {
  return LocationVerificationService(ref.watch(supabaseProvider));
});

/// Reusable service for verifying device physical location against the
/// MKES CARE+ clinic 200-metre geofence.
class LocationVerificationService {
  LocationVerificationService(this._supabase);

  final SupabaseClient _supabase;

  /// Verifies current physical location against the clinic coordinates.
  ///
  /// Flow:
  ///   1. Check authentication status.
  ///   2. Check server-side bypass or admin exemption status.
  ///   3. If geofenced, verify device location services (GPS) are enabled.
  ///   4. Check and request location permission.
  ///   5. Obtain high-accuracy current GPS position.
  ///   6. Compute geodesic distance (WGS-84) to clinic coordinates.
  ///   7. Validate accuracy <= 50m and distance <= 200m.
  ///   8. Call Supabase RPC [verify_staff_geofence] to register an active
  ///      15-minute lease in PostgreSQL.
  ///   9. Fail closed on any error.
  Future<LocationVerificationResult> verifyCurrentLocation() async {
    // 1. Ensure user is authenticated with Supabase
    final currentUser = _supabase.auth.currentUser;
    if (currentUser == null) {
      return const LocationVerificationFailure(
        reason: LocationFailureReason.unauthenticated,
        userMessage: 'You must be signed in to verify clinic location.',
      );
    }

    // 2. Server-side pre-check: check for Admin role or active GPS bypass
    try {
      final statusResp = await _supabase.rpc('check_staff_geofence_status');
      if (statusResp is Map) {
        final isAdmin = statusResp['is_admin'] as bool? ?? false;
        final hasBypass = statusResp['has_bypass'] as bool? ?? false;
        final bypassUntilStr = statusResp['bypass_until'] as String?;

        if (isAdmin) {
          return LocationVerificationSuccess(
            distanceMeters: 0.0,
            accuracyMeters: 0.0,
            verifiedAt: DateTime.now(),
            expiresAt: DateTime.now().add(const Duration(hours: 24)),
            isAdmin: true,
            isBypass: false,
          );
        }

        if (hasBypass && bypassUntilStr != null) {
          final bypassUntil = DateTime.tryParse(bypassUntilStr)?.toLocal();
          if (bypassUntil != null && DateTime.now().isBefore(bypassUntil)) {
            return LocationVerificationSuccess(
              distanceMeters: 0.0,
              accuracyMeters: 0.0,
              verifiedAt: DateTime.now(),
              expiresAt: bypassUntil,
              isAdmin: false,
              isBypass: true,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[GEOFENCE] check_staff_geofence_status error: $e');
      // If RPC is unavailable or network transient, gracefully proceed to GPS verification
    }

    // 3. Check if device location services (GPS) are turned on
    bool serviceEnabled;
    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
    } catch (e) {
      debugPrint('[GEOFENCE] Error checking location service: $e');
      serviceEnabled = false;
    }

    if (!serviceEnabled) {
      return const LocationVerificationFailure(
        reason: LocationFailureReason.serviceDisabled,
        userMessage:
            'Location services (GPS) are disabled on your device. Please turn on GPS to verify your presence at the clinic.',
      );
    }

    // 3. Check and request location permissions
    LocationPermission permission;
    try {
      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
    } catch (e) {
      debugPrint('[GEOFENCE] Error checking/requesting permission: $e');
      return LocationVerificationFailure(
        reason: LocationFailureReason.permissionDenied,
        userMessage:
            'Unable to request location permissions. Please verify app permissions in settings.',
      );
    }

    if (permission == LocationPermission.denied) {
      return const LocationVerificationFailure(
        reason: LocationFailureReason.permissionDenied,
        userMessage:
            'Location permission was denied. MKES CARE+ requires location access to verify staff presence at the clinic.',
      );
    }

    if (permission == LocationPermission.deniedForever) {
      return const LocationVerificationFailure(
        reason: LocationFailureReason.permissionPermanentlyDenied,
        userMessage:
            'Location permissions are permanently denied. Please enable Location in your device settings to access staff features.',
      );
    }

    // 4. Acquire fresh GPS position with refinement retry if initial accuracy is coarse
    Position position;
    try {
      position = await _acquireBestPosition();
    } on TimeoutException {
      return const LocationVerificationFailure(
        reason: LocationFailureReason.timeoutOrUnavailable,
        userMessage:
            'Location request timed out. Please ensure you have a clear GPS signal and try again.',
      );
    } catch (e) {
      debugPrint('[GEOFENCE] Error acquiring position: $e');
      return LocationVerificationFailure(
        reason: LocationFailureReason.timeoutOrUnavailable,
        userMessage:
            'Could not determine your current location. Please check your GPS connection and try again.',
      );
    }

    // 5. Calculate client-side distance in metres using WGS-84 geodesic formula
    final distanceMeters = Geolocator.distanceBetween(
      ClinicLocationConstants.clinicLatitude,
      ClinicLocationConstants.clinicLongitude,
      position.latitude,
      position.longitude,
    );

    // 6. Client-side accuracy validation against configurable threshold (default 150m)
    if (position.accuracy >
        ClinicLocationConstants.maxAcceptableAccuracyMeters) {
      return LocationVerificationFailure(
        reason: LocationFailureReason.inaccurateLocation,
        distanceMeters: distanceMeters,
        accuracyMeters: position.accuracy,
        userMessage:
            'GPS accuracy is insufficient (±${position.accuracy.toStringAsFixed(1)}m, required within ±${ClinicLocationConstants.maxAcceptableAccuracyMeters.toInt()}m). Please move closer to a window or step outside to acquire a stronger signal.',
      );
    }

    // 7. Client-side distance pre-check
    if (distanceMeters > ClinicLocationConstants.allowedRadiusMeters) {
      // Proactively clear any stale server-side session
      try {
        await _supabase.rpc('clear_staff_geofence');
      } catch (_) {}

      return LocationVerificationFailure(
        reason: LocationFailureReason.outsideRadius,
        distanceMeters: distanceMeters,
        accuracyMeters: position.accuracy,
        userMessage:
            'You are currently ${distanceMeters.toStringAsFixed(1)}m away from the clinic. Staff access is restricted to within ${ClinicLocationConstants.allowedRadiusMeters.toInt()}m of clinic premises.',
      );
    }

    // 8. Server-side authoritative verification and session lease generation
    try {
      final response = await _supabase.rpc(
        'verify_staff_geofence',
        params: {
          'p_lat': position.latitude,
          'p_lng': position.longitude,
          'p_accuracy': position.accuracy,
        },
      );

      if (response is Map) {
        final success = response['success'] as bool? ?? false;
        final isAdmin = response['is_admin'] as bool? ?? false;
        final isBypass = response['is_bypass'] as bool? ?? false;

        if (success) {
          final expiresAtStr = response['expires_at'] as String?;
          final expiresAt = expiresAtStr != null
              ? (DateTime.tryParse(expiresAtStr)?.toLocal() ??
                  DateTime.now().add(ClinicLocationConstants.verificationFreshness))
              : DateTime.now().add(ClinicLocationConstants.verificationFreshness);

          final serverDist =
              (response['distance_meters'] as num?)?.toDouble() ?? distanceMeters;
          final serverAcc =
              (response['accuracy_meters'] as num?)?.toDouble() ?? position.accuracy;

          return LocationVerificationSuccess(
            distanceMeters: serverDist,
            accuracyMeters: serverAcc,
            verifiedAt: DateTime.now(),
            expiresAt: expiresAt,
            isAdmin: isAdmin,
            isBypass: isBypass,
          );
        } else {
          final error = response['error'] as String? ?? 'server_error';
          final serverMessage = response['message'] as String? ??
              'Server rejected location verification.';
          final serverDist = (response['distance_meters'] as num?)?.toDouble();
          final serverAcc = (response['accuracy_meters'] as num?)?.toDouble();

          final reason = switch (error) {
            'outside_radius' => LocationFailureReason.outsideRadius,
            'inaccurate_location' => LocationFailureReason.inaccurateLocation,
            'unauthenticated' => LocationFailureReason.unauthenticated,
            _ => LocationFailureReason.serverError,
          };

          return LocationVerificationFailure(
            reason: reason,
            userMessage: serverMessage,
            distanceMeters: serverDist ?? distanceMeters,
            accuracyMeters: serverAcc ?? position.accuracy,
          );
        }
      }

      return const LocationVerificationFailure(
        reason: LocationFailureReason.serverError,
        userMessage:
            'Unexpected response from clinic verification server. Please try again.',
      );
    } catch (e) {
      debugPrint('[GEOFENCE] RPC verify_staff_geofence error: $e');
      return LocationVerificationFailure(
        reason: LocationFailureReason.serverError,
        userMessage:
            'Unable to connect to clinic verification server. Please check your internet connection and try again.',
      );
    }
  }

  /// Acquires a fresh high-accuracy GPS position. If the initial fix has coarse
  /// accuracy (> 50m), an immediate refinement sampling pass is performed to obtain
  /// a tighter satellite lock where possible.
  Future<Position> _acquireBestPosition() async {
    // 1. Initial high-accuracy reading
    Position bestPosition = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 8),
      ),
    );

    // If initial position already has tight accuracy (<= 50m), return immediately
    if (bestPosition.accuracy <= 50.0) {
      return bestPosition;
    }

    // 2. Refinement pass: modern GPS chipsets warm up over a few seconds
    debugPrint(
      '[GEOFENCE] Initial GPS fix accuracy ±${bestPosition.accuracy.toStringAsFixed(1)}m. '
      'Attempting high-accuracy satellite refinement...',
    );

    try {
      final refinedPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 5),
        ),
      );
      if (refinedPosition.accuracy < bestPosition.accuracy) {
        debugPrint(
          '[GEOFENCE] Refined GPS fix acquired: ±${refinedPosition.accuracy.toStringAsFixed(1)}m '
          '(improved from ±${bestPosition.accuracy.toStringAsFixed(1)}m)',
        );
        bestPosition = refinedPosition;
      }
    } catch (e) {
      debugPrint('[GEOFENCE] GPS refinement attempt completed, using best available fix: $e');
    }

    return bestPosition;
  }

  /// Invalidates and clears the server-side geofence session upon logout or relocation.
  Future<void> clearServerGeofence() async {
    try {
      await _supabase.rpc('clear_staff_geofence');
    } catch (e) {
      debugPrint('[GEOFENCE] Error clearing server geofence: $e');
    }
  }

  /// Opens the device settings page to allow the user to enable permissions or GPS.
  Future<bool> openAppSettings() async {
    try {
      return await Geolocator.openAppSettings();
    } catch (e) {
      debugPrint('[GEOFENCE] Error opening app settings: $e');
      return false;
    }
  }

  /// Opens the device location settings page.
  Future<bool> openLocationSettings() async {
    try {
      return await Geolocator.openLocationSettings();
    } catch (e) {
      debugPrint('[GEOFENCE] Error opening location settings: $e');
      return false;
    }
  }
}
