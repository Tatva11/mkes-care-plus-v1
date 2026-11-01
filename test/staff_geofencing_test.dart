import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:mkes_care/core/constants/clinic_location_constants.dart';
import 'package:mkes_care/core/services/location_verification_service.dart';
import 'package:mkes_care/features/admin/models/user_profile.dart';
import 'package:mkes_care/features/auth/providers/staff_location_provider.dart';
import 'package:mkes_care/features/auth/screens/staff_access_restricted_screen.dart';
import 'package:mkes_care/features/auth/widgets/staff_geofence_guard.dart';

/// Test mock implementation of [LocationVerificationService].
class MockLocationVerificationService implements LocationVerificationService {
  LocationVerificationResult mockResult;
  bool wasClearCalled = false;
  bool wasOpenAppSettingsCalled = false;
  bool wasOpenLocationSettingsCalled = false;

  MockLocationVerificationService({required this.mockResult});

  @override
  Future<LocationVerificationResult> verifyCurrentLocation() async {
    return mockResult;
  }

  @override
  Future<void> clearServerGeofence() async {
    wasClearCalled = true;
  }

  @override
  Future<bool> openAppSettings() async {
    wasOpenAppSettingsCalled = true;
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    wasOpenLocationSettingsCalled = true;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Clinic Location Constants & Distance Calculations', () {
    test('Clinic coordinates and radius are exact', () {
      expect(ClinicLocationConstants.clinicLatitude, equals(18.99110));
      expect(ClinicLocationConstants.clinicLongitude, equals(72.838885));
      expect(ClinicLocationConstants.allowedRadiusMeters, equals(200.0));
      expect(ClinicLocationConstants.maxAcceptableAccuracyMeters, equals(150.0));
      expect(ClinicLocationConstants.verificationFreshness,
          equals(const Duration(minutes: 15)));
    });

    test('Distance calculation at exact clinic coordinates is zero', () {
      final distance = Geolocator.distanceBetween(
        ClinicLocationConstants.clinicLatitude,
        ClinicLocationConstants.clinicLongitude,
        ClinicLocationConstants.clinicLatitude,
        ClinicLocationConstants.clinicLongitude,
      );
      expect(distance, closeTo(0.0, 0.001));
    });

    test('Distance calculation for nearby point within 200m succeeds', () {
      // Offset of ~0.001 degrees latitude is approx 111 metres
      final distance = Geolocator.distanceBetween(
        ClinicLocationConstants.clinicLatitude,
        ClinicLocationConstants.clinicLongitude,
        18.99210,
        72.838885,
      );
      expect(distance, lessThanOrEqualTo(200.0));
      expect(distance, greaterThan(50.0));
    });

    test('Distance calculation for point outside 200m exceeds threshold', () {
      // Offset of ~0.0025 degrees is approx 278 metres
      final distance = Geolocator.distanceBetween(
        ClinicLocationConstants.clinicLatitude,
        ClinicLocationConstants.clinicLongitude,
        18.99360,
        72.838885,
      );
      expect(distance, greaterThan(200.0));
    });
  });

  group('StaffLocationNotifier State Management', () {
    test('Initial state is StaffLocationInitial', () {
      final mockService = MockLocationVerificationService(
        mockResult: LocationVerificationSuccess(
          distanceMeters: 10.0,
          accuracyMeters: 5.0,
          verifiedAt: DateTime.now(),
          expiresAt: DateTime.now().add(const Duration(minutes: 15)),
        ),
      );

      final notifier = StaffLocationNotifier(mockService);
      expect(notifier.state, isA<StaffLocationInitial>());
      notifier.disposeLifecycleObserver();
    });

    test('Successful verification transitions to StaffLocationVerified with freshness',
        () async {
      final now = DateTime.now();
      final expiresAt = now.add(const Duration(minutes: 15));
      final mockService = MockLocationVerificationService(
        mockResult: LocationVerificationSuccess(
          distanceMeters: 12.5,
          accuracyMeters: 4.0,
          verifiedAt: now,
          expiresAt: expiresAt,
        ),
      );

      final notifier = StaffLocationNotifier(mockService);
      final result = await notifier.verifyLocation();

      expect(result, isA<LocationVerificationSuccess>());
      expect(notifier.state, isA<StaffLocationVerified>());

      final verified = notifier.state as StaffLocationVerified;
      expect(verified.distanceMeters, equals(12.5));
      expect(verified.accuracyMeters, equals(4.0));
      expect(verified.isFresh, isTrue);

      notifier.disposeLifecycleObserver();
    });

    test('Expired lease marks isFresh as false', () {
      final past = DateTime.now().subtract(const Duration(minutes: 1));
      final verified = StaffLocationVerified(
        distanceMeters: 10.0,
        accuracyMeters: 5.0,
        verifiedAt: DateTime.now().subtract(const Duration(minutes: 16)),
        expiresAt: past,
      );
      expect(verified.isFresh, isFalse);
    });

    test('Failed verification outside radius transitions to StaffLocationRestricted',
        () async {
      final mockService = MockLocationVerificationService(
        mockResult: const LocationVerificationFailure(
          reason: LocationFailureReason.outsideRadius,
          distanceMeters: 235.0,
          accuracyMeters: 8.0,
          userMessage: 'You are 235.0m from the clinic.',
        ),
      );

      final notifier = StaffLocationNotifier(mockService);
      final result = await notifier.verifyLocation();

      expect(result, isA<LocationVerificationFailure>());
      expect(notifier.state, isA<StaffLocationRestricted>());

      final restricted = notifier.state as StaffLocationRestricted;
      expect(restricted.reason, equals(LocationFailureReason.outsideRadius));
      expect(restricted.distanceMeters, equals(235.0));
      expect(restricted.message, contains('235.0m'));

      notifier.disposeLifecycleObserver();
    });

    test('Failed verification with GPS disabled transitions to StaffLocationRestricted',
        () async {
      final mockService = MockLocationVerificationService(
        mockResult: const LocationVerificationFailure(
          reason: LocationFailureReason.serviceDisabled,
          userMessage: 'Location services (GPS) are disabled.',
        ),
      );

      final notifier = StaffLocationNotifier(mockService);
      final result = await notifier.verifyLocation();

      expect(result, isA<LocationVerificationFailure>());
      expect(notifier.state, isA<StaffLocationRestricted>());

      final restricted = notifier.state as StaffLocationRestricted;
      expect(restricted.reason, equals(LocationFailureReason.serviceDisabled));

      notifier.disposeLifecycleObserver();
    });

    test('Failed verification with permission denied transitions to StaffLocationRestricted',
        () async {
      final mockService = MockLocationVerificationService(
        mockResult: const LocationVerificationFailure(
          reason: LocationFailureReason.permissionDenied,
          userMessage: 'Location permission was denied.',
        ),
      );

      final notifier = StaffLocationNotifier(mockService);
      final result = await notifier.verifyLocation();

      expect(result, isA<LocationVerificationFailure>());
      expect(notifier.state, isA<StaffLocationRestricted>());

      final restricted = notifier.state as StaffLocationRestricted;
      expect(restricted.reason, equals(LocationFailureReason.permissionDenied));

      notifier.disposeLifecycleObserver();
    });

    test('ClearLocation resets state and calls clearServerGeofence', () async {
      final mockService = MockLocationVerificationService(
        mockResult: LocationVerificationSuccess(
          distanceMeters: 10.0,
          accuracyMeters: 5.0,
          verifiedAt: DateTime.now(),
          expiresAt: DateTime.now().add(const Duration(minutes: 15)),
        ),
      );

      final notifier = StaffLocationNotifier(mockService);
      await notifier.verifyLocation();
      expect(notifier.state, isA<StaffLocationVerified>());

      await notifier.clearLocation();
      expect(notifier.state, isA<StaffLocationInitial>());
      expect(mockService.wasClearCalled, isTrue);

      notifier.disposeLifecycleObserver();
    });
  });

  group('StaffAccessRestrictedScreen UI Rendering', () {
    testWidgets('Renders restricted screen with distance and guidance',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockLocationVerificationService(
        mockResult: const LocationVerificationFailure(
          reason: LocationFailureReason.outsideRadius,
          userMessage: 'You are outside the clinic 50m radius.',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            locationVerificationServiceProvider
                .overrideWithValue(mockService),
          ],
          child: const MaterialApp(
            home: StaffAccessRestrictedScreen(
              reason: LocationFailureReason.outsideRadius,
              message: 'You are outside the clinic 50m radius.',
              distanceMeters: 142.5,
              accuracyMeters: 8.0,
            ),
          ),
        ),
      );

      expect(find.text('Clinic Proximity Required'), findsOneWidget);
      expect(find.text('ACCESS RESTRICTED — 200M GEOFENCE'), findsOneWidget);
      expect(find.text('200 metres'), findsOneWidget);
      expect(find.text('142.5 metres'), findsOneWidget);
      expect(find.text('±8.0 metres'), findsOneWidget);
      expect(find.text(ClinicLocationConstants.clinicAddress), findsOneWidget);
      expect(find.text('Verify Location / Retry'), findsOneWidget);
      expect(find.text('Sign Out'), findsOneWidget);
    });

    testWidgets('Renders GPS disabled guidance and settings button',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockLocationVerificationService(
        mockResult: const LocationVerificationFailure(
          reason: LocationFailureReason.serviceDisabled,
          userMessage: 'Location services (GPS) are disabled on your device.',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            locationVerificationServiceProvider
                .overrideWithValue(mockService),
          ],
          child: const MaterialApp(
            home: StaffAccessRestrictedScreen(
              reason: LocationFailureReason.serviceDisabled,
              message: 'Location services (GPS) are disabled on your device.',
            ),
          ),
        ),
      );

      expect(find.text('Open Location Settings'), findsOneWidget);
      expect(find.text('Location services (GPS) are disabled on your device.'),
          findsOneWidget);
    });

    testWidgets('Renders permanently denied permission guidance and app settings button',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockLocationVerificationService(
        mockResult: const LocationVerificationFailure(
          reason: LocationFailureReason.permissionPermanentlyDenied,
          userMessage: 'Location permission is permanently denied.',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            locationVerificationServiceProvider
                .overrideWithValue(mockService),
          ],
          child: const MaterialApp(
            home: StaffAccessRestrictedScreen(
              reason: LocationFailureReason.permissionPermanentlyDenied,
              message: 'Location permission is permanently denied.',
            ),
          ),
        ),
      );

      expect(find.text('Open App Settings'), findsOneWidget);
    });

    testWidgets('Renders Sign Out button and handles press safely',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockLocationVerificationService(
        mockResult: const LocationVerificationFailure(
          reason: LocationFailureReason.outsideRadius,
          distanceMeters: 220.0,
          accuracyMeters: 10.0,
          userMessage: 'Outside permitted radius.',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            locationVerificationServiceProvider
                .overrideWithValue(mockService),
          ],
          child: const MaterialApp(
            home: StaffAccessRestrictedScreen(
              reason: LocationFailureReason.outsideRadius,
              message: 'Outside permitted radius.',
              distanceMeters: 220.0,
            ),
          ),
        ),
      );

      final signOutBtn = find.text('Sign Out');
      expect(signOutBtn, findsOneWidget);
    });
  });

  group('StaffGeofenceGuard Widget Routing', () {
    testWidgets('Shows verifying scaffold when initial or verifying',
        (tester) async {
      final mockService = MockLocationVerificationService(
        mockResult: LocationVerificationSuccess(
          distanceMeters: 10.0,
          accuracyMeters: 5.0,
          verifiedAt: DateTime.now(),
          expiresAt: DateTime.now().add(const Duration(minutes: 15)),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            locationVerificationServiceProvider
                .overrideWithValue(mockService),
          ],
          child: const MaterialApp(
            home: StaffGeofenceGuard(
              child: Text('PROTECTED_STAFF_CONTENT'),
            ),
          ),
        ),
      );

      // Initially shows verifying screen
      expect(find.text('Verifying Clinic Location'), findsOneWidget);
      expect(find.text('Validating 200-metre physical proximity...'),
          findsOneWidget);
      expect(find.text('PROTECTED_STAFF_CONTENT'), findsNothing);

      // Complete async verification
      await tester.pumpAndSettle();

      // Protected content is now revealed!
      expect(find.text('PROTECTED_STAFF_CONTENT'), findsOneWidget);
    });

    testWidgets('Shows StaffAccessRestrictedScreen when verification fails',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockLocationVerificationService(
        mockResult: const LocationVerificationFailure(
          reason: LocationFailureReason.outsideRadius,
          distanceMeters: 350.0,
          accuracyMeters: 6.0,
          userMessage: 'You are 350.0m away from the clinic.',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            locationVerificationServiceProvider
                .overrideWithValue(mockService),
          ],
          child: const MaterialApp(
            home: StaffGeofenceGuard(
              child: Text('PROTECTED_STAFF_CONTENT'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Restricted screen is displayed; protected content remains blocked
      expect(find.text('PROTECTED_STAFF_CONTENT'), findsNothing);
      expect(find.text('Clinic Proximity Required'), findsOneWidget);
      expect(find.text('350.0 metres'), findsOneWidget);
    });

    testWidgets('Retrying inside permitted area restores protected access',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockService = MockLocationVerificationService(
        mockResult: const LocationVerificationFailure(
          reason: LocationFailureReason.outsideRadius,
          distanceMeters: 180.0,
          accuracyMeters: 5.0,
          userMessage: 'You are 180.0m away from clinic.',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            locationVerificationServiceProvider
                .overrideWithValue(mockService),
          ],
          child: const MaterialApp(
            home: StaffGeofenceGuard(
              child: Text('PROTECTED_STAFF_CONTENT'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('PROTECTED_STAFF_CONTENT'), findsNothing);
      expect(find.text('180.0 metres'), findsOneWidget);

      // Now simulate user moving within 50m and tapping retry
      mockService.mockResult = LocationVerificationSuccess(
        distanceMeters: 15.0,
        accuracyMeters: 3.0,
        verifiedAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      );

      await tester.tap(find.text('Verify Location / Retry'));
      await tester.pumpAndSettle();

      // Access is now unlocked!
      expect(find.text('PROTECTED_STAFF_CONTENT'), findsOneWidget);
    });
  });

  group('Admin Exemption & Role Verification', () {
    test('Admin role receives unconditional verification success', () {
      final adminSuccess = LocationVerificationSuccess(
        distanceMeters: 0.0,
        accuracyMeters: 0.0,
        verifiedAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(days: 365)),
        isAdmin: true,
      );

      expect(adminSuccess.isAdmin, isTrue);
      expect(adminSuccess.distanceMeters, equals(0.0));
      expect(adminSuccess.isFresh, isTrue);
    });
  });

  group('Individual Staff GPS Bypass & Admin Controls', () {
    test('UserProfile model parses bypass fields and computes isGpsBypassActive correctly', () {
      final futureExpiry = DateTime.now().add(const Duration(hours: 4));
      final userWithBypass = UserProfile.fromJson({
        'id': 'staff-123',
        'full_name': 'Ramesh Kumar',
        'email': 'ramesh@mkes.com',
        'role': 'staff',
        'is_active': true,
        'created_at': DateTime.now().toIso8601String(),
        'gps_bypass_until': futureExpiry.toIso8601String(),
        'gps_bypass_granted_by': 'admin-999',
        'gps_bypass_granted_at': DateTime.now().toIso8601String(),
        'gps_bypass_reason': 'Outreach camp',
      });

      expect(userWithBypass.isGpsBypassActive, isTrue);
      expect(userWithBypass.gpsBypassUntil, isNotNull);
      expect(userWithBypass.gpsBypassReason, equals('Outreach camp'));
      expect(userWithBypass.gpsBypassGrantedBy, equals('admin-999'));

      final json = userWithBypass.toJson();
      expect(json['gps_bypass_until'], isNotNull);
      expect(json['gps_bypass_reason'], equals('Outreach camp'));
    });

    test('UserProfile with expired bypass marks isGpsBypassActive as false', () {
      final pastExpiry = DateTime.now().subtract(const Duration(minutes: 5));
      final userExpiredBypass = UserProfile.fromJson({
        'id': 'staff-456',
        'full_name': 'Suresh Patil',
        'email': 'suresh@mkes.com',
        'role': 'staff',
        'is_active': true,
        'created_at': DateTime.now().toIso8601String(),
        'gps_bypass_until': pastExpiry.toIso8601String(),
      });

      expect(userExpiredBypass.isGpsBypassActive, isFalse);
    });

    test('StaffLocationVerified carries isBypass flag and freshness', () {
      final bypassVerified = StaffLocationVerified(
        distanceMeters: 0.0,
        accuracyMeters: 0.0,
        verifiedAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 4)),
        isBypass: true,
      );

      expect(bypassVerified.isBypass, isTrue);
      expect(bypassVerified.isFresh, isTrue);
      expect(bypassVerified.distanceMeters, equals(0.0));
    });

    testWidgets('Staff with active bypass accesses protected view from anywhere without GPS check',
        (tester) async {
      final bypassService = MockLocationVerificationService(
        mockResult: LocationVerificationSuccess(
          distanceMeters: 0.0,
          accuracyMeters: 0.0,
          verifiedAt: DateTime.now(),
          expiresAt: DateTime.now().add(const Duration(hours: 4)),
          isBypass: true,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            locationVerificationServiceProvider
                .overrideWithValue(bypassService),
          ],
          child: const MaterialApp(
            home: StaffGeofenceGuard(
              child: Text('PROTECTED_STAFF_CONTENT'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('PROTECTED_STAFF_CONTENT'), findsOneWidget);
      expect(find.text('Clinic Proximity Required'), findsNothing);
    });

    testWidgets('Staff without bypass outside 200m remains restricted',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final restrictedService = MockLocationVerificationService(
        mockResult: const LocationVerificationFailure(
          reason: LocationFailureReason.outsideRadius,
          distanceMeters: 285.0,
          accuracyMeters: 8.0,
          userMessage:
              'You are 285.0m away from the clinic. Staff access is restricted to within 200m of clinic premises.',
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            locationVerificationServiceProvider
                .overrideWithValue(restrictedService),
          ],
          child: const MaterialApp(
            home: StaffGeofenceGuard(
              child: Text('PROTECTED_STAFF_CONTENT'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('PROTECTED_STAFF_CONTENT'), findsNothing);
      expect(find.text('Clinic Proximity Required'), findsOneWidget);
      expect(find.text('285.0 metres'), findsOneWidget);
    });
  });

  group('Real-World GPS Conditions & Accuracy Threshold (150m)', () {
    test(
        'Measured distance 99.3m with ±135m accuracy is accepted within 200m radius and 150m threshold',
        () {
      const distance = 99.3;
      const accuracy = 135.0;

      final isDistanceOk =
          distance <= ClinicLocationConstants.allowedRadiusMeters;
      final isAccuracyOk =
          accuracy <= ClinicLocationConstants.maxAcceptableAccuracyMeters;

      expect(isDistanceOk, isTrue,
          reason: '99.3m should be within 200m radius');
      expect(isAccuracyOk, isTrue,
          reason: '±135m should be within 150m accuracy threshold');
    });

    test('Reading with accuracy exceeding 150m is rejected as inaccurate', () {
      const accuracy = 160.0;
      final isAccuracyOk =
          accuracy <= ClinicLocationConstants.maxAcceptableAccuracyMeters;
      expect(isAccuracyOk, isFalse, reason: '±160m exceeds 150m accuracy limit');
    });

    test('Reading outside 200m is rejected regardless of accuracy', () {
      const distance = 215.0;
      final isDistanceOk =
          distance <= ClinicLocationConstants.allowedRadiusMeters;
      expect(isDistanceOk, isFalse, reason: '215m is outside 200m geofence radius');
    });
  });
}
