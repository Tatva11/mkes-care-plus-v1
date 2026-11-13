import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/location_verification_service.dart';

/// State representation for staff geofence verification.
@immutable
sealed class StaffLocationState {
  const StaffLocationState();
}

class StaffLocationInitial extends StaffLocationState {
  const StaffLocationInitial();
}

class StaffLocationVerifying extends StaffLocationState {
  const StaffLocationVerifying();
}

class StaffLocationVerified extends StaffLocationState {
  final double distanceMeters;
  final double accuracyMeters;
  final DateTime verifiedAt;
  final DateTime expiresAt;
  final bool isAdmin;
  final bool isBypass;

  const StaffLocationVerified({
    required this.distanceMeters,
    required this.accuracyMeters,
    required this.verifiedAt,
    required this.expiresAt,
    this.isAdmin = false,
    this.isBypass = false,
  });

  /// Whether the current verification is still within the freshness window.
  bool get isFresh => DateTime.now().isBefore(expiresAt);
}

class StaffLocationRestricted extends StaffLocationState {
  final LocationFailureReason reason;
  final String message;
  final double? distanceMeters;
  final double? accuracyMeters;

  const StaffLocationRestricted({
    required this.reason,
    required this.message,
    this.distanceMeters,
    this.accuracyMeters,
  });
}

/// Provider managing the active staff geofencing state and verification lifecycle.
final staffLocationProvider =
    StateNotifierProvider<StaffLocationNotifier, StaffLocationState>((ref) {
  final service = ref.watch(locationVerificationServiceProvider);
  final notifier = StaffLocationNotifier(service);

  // Register app lifecycle listener to re-verify stale sessions on resume
  ref.onDispose(() {
    notifier.disposeLifecycleObserver();
  });

  return notifier;
});

class StaffLocationNotifier extends StateNotifier<StaffLocationState>
    with WidgetsBindingObserver {
  StaffLocationNotifier(this._service) : super(const StaffLocationInitial()) {
    WidgetsBinding.instance.addObserver(this);
  }

  final LocationVerificationService _service;
  bool _isVerifying = false;

  void disposeLifecycleObserver() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[GEOFENCE] App resumed from background. Checking freshness...');
      _checkFreshnessOnResume();
    }
  }

  /// Automatically re-verifies if current verification has expired upon app foregrounding.
  Future<void> _checkFreshnessOnResume() async {
    final current = state;
    if (current is StaffLocationVerified) {
      if (!current.isFresh) {
        debugPrint('[GEOFENCE] Previous verification is stale. Re-verifying...');
        await verifyLocation();
      } else {
        final remaining = current.expiresAt.difference(DateTime.now());
        debugPrint(
            '[GEOFENCE] Verification is fresh. Remaining lease: ${remaining.inMinutes}m ${remaining.inSeconds % 60}s.');
      }
    }
  }

  /// Triggers a fresh GPS reading and server-side RPC validation.
  Future<LocationVerificationResult> verifyLocation() async {
    if (_isVerifying) {
      return const LocationVerificationFailure(
        reason: LocationFailureReason.timeoutOrUnavailable,
        userMessage: 'Verification is already in progress.',
      );
    }

    _isVerifying = true;
    state = const StaffLocationVerifying();

    try {
      final result = await _service.verifyCurrentLocation();

      switch (result) {
        case LocationVerificationSuccess():
          state = StaffLocationVerified(
            distanceMeters: result.distanceMeters,
            accuracyMeters: result.accuracyMeters,
            verifiedAt: result.verifiedAt,
            expiresAt: result.expiresAt,
            isAdmin: result.isAdmin,
            isBypass: result.isBypass,
          );
          return result;

        case LocationVerificationFailure():
          state = StaffLocationRestricted(
            reason: result.reason,
            message: result.userMessage,
            distanceMeters: result.distanceMeters,
            accuracyMeters: result.accuracyMeters,
          );
          return result;
      }
    } catch (e) {
      debugPrint('[GEOFENCE] Unexpected verification error: $e');
      final failure = LocationVerificationFailure(
        reason: LocationFailureReason.timeoutOrUnavailable,
        userMessage:
            'An unexpected error occurred during location verification: $e',
      );
      state = StaffLocationRestricted(
        reason: failure.reason,
        message: failure.userMessage,
      );
      return failure;
    } finally {
      _isVerifying = false;
    }
  }

  /// Ensures verification is currently fresh before a critical staff operation
  /// (e.g. shift clock-in). Returns true if valid, false if blocked.
  Future<bool> ensureValidLocation() async {
    final current = state;
    if (current is StaffLocationVerified && current.isFresh) {
      return true;
    }

    final result = await verifyLocation();
    return result is LocationVerificationSuccess;
  }

  /// Resets the local location state to initial without making network calls.
  void resetState() {
    state = const StaffLocationInitial();
  }

  /// Clears active location state and informs the database to purge the session lease.
  Future<void> clearLocation() async {
    state = const StaffLocationInitial();
    try {
      await _service.clearServerGeofence();
    } catch (e) {
      debugPrint('[GEOFENCE] Non-fatal error during clearLocation: $e');
    }
  }

  /// Allows opening settings from UI.
  Future<bool> openAppSettings() => _service.openAppSettings();
  Future<bool> openLocationSettings() => _service.openLocationSettings();
}
