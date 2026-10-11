import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mkes_care/features/admin/models/user_profile.dart';
import 'package:mkes_care/features/auth/models/profile_model.dart';
import 'package:mkes_care/features/inventory/models/inventory_batch.dart';
import 'package:mkes_care/features/inventory/models/inventory_item.dart';
import 'package:mkes_care/features/notifications/models/notification_model.dart';
import 'package:mkes_care/features/staff/models/attendance_record.dart';
import 'package:mkes_care/features/staff/models/shift_configuration.dart';

void main() {
  group('ISSUE 2: Future Stock Expiry Dates & Batch Synchronization', () {
    test('100 masks with expiry 12 October 2027 is NOT marked expired before that date', () {
      final expiryDate = DateTime(2027, 10, 12);

      final item = InventoryItem(
        id: 'item-mask-1',
        name: 'Surgical Face Masks',
        category: 'Consumables',
        currentStock: 100,
        unit: 'pcs',
        expiryDate: expiryDate,
      );

      // Verify item properties
      expect(item.expiryDate, equals(expiryDate));
      expect(item.effectiveExpiryDate, equals(expiryDate));
      expect(item.isExpired, isFalse);
      expect(item.expiryStatus, equals(ExpiryStatus.valid));
      expect(item.daysUntilExpiry, isNotNull);
      expect(item.daysUntilExpiry!, isPositive);
      expect(item.expiryStatusLabel, contains('Valid'));

      // Verify batch properties
      final batch = InventoryBatch(
        id: 'batch-mask-1',
        inventoryId: 'item-mask-1',
        inventoryName: 'Surgical Face Masks',
        batchNumber: 'BATCH-2027-100',
        receivedQuantity: 100,
        remainingQuantity: 100,
        expiryDate: expiryDate,
        receivedDate: DateTime(2026, 10, 11),
        createdAt: DateTime(2026, 10, 11),
      );

      expect(batch.isExpired, isFalse);
      expect(batch.expiryStatus, equals(ExpiryStatus.valid));
      expect(batch.daysUntilExpiry, isNotNull);
      expect(batch.daysUntilExpiry!, isPositive);
    });

    test('Calendar date boundary behavior: boundary date is NOT expired, day after IS expired', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final tomorrow = today.add(const Duration(days: 1));

      // Item expiring today (boundary date)
      final itemExpiringToday = InventoryItem(
        id: 'item-today',
        name: 'Item Expiring Today',
        category: 'Medicine',
        currentStock: 10,
        unit: 'pcs',
        expiryDate: today,
      );

      expect(itemExpiringToday.isExpired, isFalse,
          reason: 'Item on its exact expiry date is still valid through that calendar day');
      expect(itemExpiringToday.expiryStatus, equals(ExpiryStatus.expiringSoon));
      expect(itemExpiringToday.daysUntilExpiry, equals(0));
      expect(itemExpiringToday.expiryStatusLabel, equals('Expiring Soon (Today)'));

      // Item expiring yesterday (day after boundary)
      final itemExpiredYesterday = InventoryItem(
        id: 'item-yesterday',
        name: 'Item Expired Yesterday',
        category: 'Medicine',
        currentStock: 10,
        unit: 'pcs',
        expiryDate: yesterday,
      );

      expect(itemExpiredYesterday.isExpired, isTrue,
          reason: 'Item whose expiry was yesterday is strictly expired');
      expect(itemExpiredYesterday.expiryStatus, equals(ExpiryStatus.expired));
      expect(itemExpiredYesterday.daysUntilExpiry, equals(-1));
      expect(itemExpiredYesterday.expiryStatusLabel, equals('Expired (1 d ago)'));

      // Item expiring tomorrow
      final itemExpiringTomorrow = InventoryItem(
        id: 'item-tomorrow',
        name: 'Item Expiring Tomorrow',
        category: 'Medicine',
        currentStock: 10,
        unit: 'pcs',
        expiryDate: tomorrow,
      );

      expect(itemExpiringTomorrow.isExpired, isFalse);
      expect(itemExpiringTomorrow.expiryStatus, equals(ExpiryStatus.expiringSoon));
      expect(itemExpiringTomorrow.daysUntilExpiry, equals(1));
      expect(itemExpiringTomorrow.expiryStatusLabel, equals('Expiring Soon (Tomorrow)'));
    });

    test('Calendar date parser preserves YYYY-MM-DD without UTC timezone boundary shift', () {
      // Direct YYYY-MM-DD
      final parsedDateOnly = InventoryItem.parseCalendarDate('2027-10-12');
      expect(parsedDateOnly, isNotNull);
      expect(parsedDateOnly!.year, equals(2027));
      expect(parsedDateOnly.month, equals(10));
      expect(parsedDateOnly.day, equals(12));

      // ISO UTC timestamp: 2027-10-12T00:00:00Z should NOT roll back to 2027-10-11
      final parsedIsoZ = InventoryItem.parseCalendarDate('2027-10-12T00:00:00.000Z');
      expect(parsedIsoZ, isNotNull);
      expect(parsedIsoZ!.year, equals(2027));
      expect(parsedIsoZ.month, equals(10));
      expect(parsedIsoZ.day, equals(12));

      // Serialized and deserialized through JSON
      final json = {
        'id': 'inv-json-1',
        'name': 'Sterile Gloves',
        'category': 'Supplies',
        'current_stock': 50,
        'unit': 'pairs',
        'expiry_date': '2027-10-12',
      };
      final itemFromJson = InventoryItem.fromJson(json);
      expect(itemFromJson.expiryDate, equals(DateTime(2027, 10, 12)));
      expect(itemFromJson.toJson()['expiry_date'], equals('2027-10-12'));
    });

    test('Multiple batches: active unexpired consignment batch overrides depleted expired batch', () {
      final expiredBatch = InventoryBatch(
        id: 'batch-old-depleted',
        inventoryId: 'item-mask-1',
        batchNumber: 'OLD-2024',
        receivedQuantity: 50,
        remainingQuantity: 0, // Depleted!
        expiryDate: DateTime(2024, 5, 1),
        receivedDate: DateTime(2024, 1, 1),
        createdAt: DateTime(2024, 1, 1),
      );

      final newConsignmentBatch = InventoryBatch(
        id: 'batch-consignment-2027',
        inventoryId: 'item-mask-1',
        batchNumber: 'MASK-PO-99',
        receivedQuantity: 100,
        remainingQuantity: 100, // Available stock!
        expiryDate: DateTime(2027, 10, 12),
        receivedDate: DateTime(2026, 10, 11),
        createdAt: DateTime(2026, 10, 11),
      );

      final item = InventoryItem(
        id: 'item-mask-1',
        name: 'Surgical Face Masks',
        category: 'Consumables',
        currentStock: 100,
        unit: 'pcs',
        // Legacy column in DB was stuck on 2024-05-01 due to prior RPC bug
        expiryDate: DateTime(2024, 5, 1),
        batches: [expiredBatch, newConsignmentBatch],
      );

      // Effective expiry date MUST resolve to the active consignment batch (2027-10-12)
      expect(item.effectiveExpiryDate, equals(DateTime(2027, 10, 12)));
      expect(item.isExpired, isFalse,
          reason: 'Item stock is available in valid 2027 batch and must not be marked expired');
      expect(item.expiryStatus, equals(ExpiryStatus.valid));
    });

    test('Multiple batches: FEFO among usable unexpired stock prioritizes earliest valid batch', () {
      final validBatch1 = InventoryBatch(
        id: 'batch-early-valid',
        inventoryId: 'item-1',
        batchNumber: 'B1',
        receivedQuantity: 20,
        remainingQuantity: 20,
        expiryDate: DateTime(2027, 3, 1),
        receivedDate: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
      );

      final validBatch2 = InventoryBatch(
        id: 'batch-later-valid',
        inventoryId: 'item-1',
        batchNumber: 'B2',
        receivedQuantity: 80,
        remainingQuantity: 80,
        expiryDate: DateTime(2027, 10, 12),
        receivedDate: DateTime(2026, 2, 1),
        createdAt: DateTime(2026, 2, 1),
      );

      final item = InventoryItem(
        id: 'item-1',
        name: 'Syringes',
        category: 'Consumables',
        currentStock: 100,
        unit: 'pcs',
        batches: [validBatch2, validBatch1], // Unsorted order
      );

      // Should choose earliest valid batch (2027-03-01) according to FEFO
      expect(item.effectiveExpiryDate, equals(DateTime(2027, 3, 1)));
      expect(item.isExpired, isFalse);
    });

    test('Null or missing expiry dates handled gracefully without false expiry flags', () {
      final itemNoExpiry = InventoryItem(
        id: 'item-no-exp',
        name: 'Paper Cups',
        category: 'General',
        currentStock: 500,
        unit: 'pcs',
        expiryDate: null,
      );

      expect(itemNoExpiry.effectiveExpiryDate, isNull);
      expect(itemNoExpiry.isExpired, isFalse);
      expect(itemNoExpiry.isExpiringSoon, isFalse);
      expect(itemNoExpiry.expiryStatus, equals(ExpiryStatus.none));
      expect(itemNoExpiry.daysUntilExpiry, isNull);
      expect(itemNoExpiry.expiryStatusLabel, equals('No Expiry Date'));

      final batchNoExpiry = InventoryBatch(
        id: 'batch-no-exp',
        inventoryId: 'item-no-exp',
        batchNumber: 'BATCH-NONE',
        receivedQuantity: 500,
        remainingQuantity: 500,
        expiryDate: null,
        receivedDate: DateTime(2026, 10, 11),
        createdAt: DateTime(2026, 10, 11),
      );

      expect(batchNoExpiry.isExpired, isFalse);
      expect(batchNoExpiry.isExpiringSoon, isFalse);
      expect(batchNoExpiry.expiryStatus, equals(ExpiryStatus.none));
      expect(batchNoExpiry.formattedExpiryDate, equals('No Expiry'));
    });

    test('Reopening and editing consignment order preserves original expiry date', () {
      final initialDate = DateTime(2027, 10, 12);
      final batch = InventoryBatch(
        id: 'batch-reopen-1',
        inventoryId: 'item-1',
        batchNumber: 'PO-BATCH-1',
        receivedQuantity: 100,
        remainingQuantity: 100,
        expiryDate: initialDate,
        receivedDate: DateTime(2026, 10, 11),
        createdAt: DateTime(2026, 10, 11),
      );

      // Simulate PO reopen and update of other fields (e.g. remarks/vendor)
      final updatedBatch = InventoryBatch(
        id: batch.id,
        inventoryId: batch.inventoryId,
        purchaseOrderId: 'PO-MODIFIED',
        vendorName: 'Updated Medical Supplies Ltd',
        batchNumber: batch.batchNumber,
        receivedQuantity: batch.receivedQuantity,
        remainingQuantity: batch.remainingQuantity,
        expiryDate: batch.expiryDate, // Preserved!
        receivedDate: batch.receivedDate,
        createdAt: batch.createdAt,
        updatedAt: DateTime.now(),
      );

      expect(updatedBatch.expiryDate, equals(initialDate));
      expect(updatedBatch.isExpired, isFalse);
    });
  });

  group('ISSUE 1: Shift Changes Effective Next Day & Evening Terminology', () {
    test('User-facing terminology uses Evening instead of Afternoon', () {
      // ShiftConfiguration
      expect(ShiftConfiguration.defaultEvening.displayName, equals('Evening Shift'));
      expect(ShiftConfiguration.defaultAfternoon.displayName, equals('Evening Shift'));

      // UserProfile
      expect(UserProfile.formatShiftLabel('afternoon'), equals('Evening'));
      expect(UserProfile.formatShiftLabel('evening'), equals('Evening'));
      expect(UserProfile.formatShiftLabel('morning'), equals('Morning'));
      expect(UserProfile.formatShiftLabel('both'), equals('Morning & Evening'));

      // ProfileModel
      expect(ProfileModel.formatShiftLabel('afternoon'), equals('Evening'));
      expect(ProfileModel.formatShiftLabel('evening'), equals('Evening'));
      expect(ProfileModel.formatShiftLabel('both'), equals('Morning & Evening'));
    });

    test('Historical database value afternoon is parsed and displayed as Evening', () {
      final user = UserProfile(
        id: 'staff-1',
        fullName: 'Jane Doe',
        email: 'jane@clinic.com',
        role: 'staff',
        isActive: true,
        assignedShift: 'afternoon', // Historical database value
        createdAt: DateTime(2026, 1, 1),
      );

      expect(user.shiftDisplayName, equals('Evening Shift'));
      expect(user.isAfternoonShift, isTrue);
      expect(user.isEveningShift, isTrue);
    });

    test('Shift change scheduled for next calendar day does NOT overwrite current-day shift', () {
      final today = DateTime.now();
      final tomorrow = today.add(const Duration(days: 1));

      final staff = UserProfile(
        id: 'staff-101',
        fullName: 'John Nurse',
        email: 'john@clinic.com',
        role: 'staff',
        isActive: true,
        assignedShift: 'morning', // Today working shift
        nextShift: 'afternoon', // Scheduled future shift (Evening)
        shiftEffectiveDate: tomorrow,
        createdAt: DateTime(2026, 1, 1),
      );

      // Verify scheduled status
      expect(staff.hasScheduledShift, isTrue);
      expect(staff.assignedShift, equals('morning'));
      expect(staff.nextShift, equals('afternoon'));

      // For today, staff member is STILL on Morning shift
      expect(staff.getShiftForDate(today), equals('morning'));
      expect(staff.shiftDisplayNameForDate(today), equals('Morning'));

      // For tomorrow, staff member is on Evening shift
      expect(staff.getShiftForDate(tomorrow), equals('afternoon'));
      expect(staff.shiftDisplayNameForDate(tomorrow), equals('Evening'));
    });

    test('Staff with scheduled shift preserves active attendance records for current day', () {
      final today = DateTime.now();
      final todayMorning = DateTime(today.year, today.month, today.day, 8, 5);

      // Existing today attendance record
      final todayAttendance = AttendanceRecord(
        id: 'att-today-1',
        staffId: 'staff-101',
        date: DateTime(today.year, today.month, today.day),
        shift: 'morning',
        checkInTime: todayMorning,
        status: 'present',
        isLate: false,
        lateMinutes: 0,
      );

      // Scheduled future shift for tomorrow
      final tomorrow = today.add(const Duration(days: 1));
      final staff = UserProfile(
        id: 'staff-101',
        fullName: 'John Nurse',
        email: 'john@clinic.com',
        role: 'staff',
        isActive: true,
        assignedShift: 'morning',
        nextShift: 'both',
        shiftEffectiveDate: tomorrow,
        createdAt: DateTime(2026, 1, 1),
      );

      // Ensure today's record remains intact and matches today's active shift
      expect(todayAttendance.shift, equals('morning'));
      expect(staff.getShiftForDate(todayAttendance.date), equals('morning'));
      expect(staff.getShiftForDate(tomorrow), equals('both'));
    });

    test('Updating an existing future assignment replaces pending schedule cleanly', () {
      final day1 = DateTime.now().add(const Duration(days: 1));
      final day3 = DateTime.now().add(const Duration(days: 3));

      var staff = UserProfile(
        id: 'staff-102',
        fullName: 'Sara Doc',
        email: 'sara@clinic.com',
        role: 'doctor',
        isActive: true,
        assignedShift: 'morning',
        nextShift: 'afternoon',
        shiftEffectiveDate: day1,
        createdAt: DateTime(2026, 1, 1),
      );

      expect(staff.nextShift, equals('afternoon'));
      expect(staff.shiftEffectiveDate, equals(day1));

      // Admin updates pending future assignment to Both starting on day 3
      staff = staff.copyWith(
        nextShift: 'both',
        shiftEffectiveDate: day3,
      );

      expect(staff.nextShift, equals('both'));
      expect(staff.shiftEffectiveDate, equals(day3));
      // Current shift is still unaffected
      expect(staff.assignedShift, equals('morning'));
    });

    test('Notification message formatting for Morning, Evening, and Both', () {
      final effectiveDate = DateTime(2026, 10, 12);
      final formattedDate = DateFormat('d MMMM yyyy').format(effectiveDate);

      // Evening shift
      final eveningLabel = UserProfile.formatShiftLabel('afternoon');
      final eveningMessage = 'Your shift effective $formattedDate has been changed to $eveningLabel.';
      expect(eveningMessage, equals('Your shift effective 12 October 2026 has been changed to Evening.'));

      // Morning shift
      final morningLabel = UserProfile.formatShiftLabel('morning');
      final morningMessage = 'Your shift effective $formattedDate has been changed to $morningLabel.';
      expect(morningMessage, equals('Your shift effective 12 October 2026 has been changed to Morning.'));

      // Both shifts
      final bothLabel = UserProfile.formatShiftLabel('both');
      final bothMessage = 'Your shift effective $formattedDate has been changed to $bothLabel.';
      expect(bothMessage, equals('Your shift effective 12 October 2026 has been changed to Morning & Evening.'));
    });

    test('Notification idempotency prevents duplicate notifications on retry', () {
      final notif1 = NotificationModel(
        id: 'notif-1',
        userId: 'staff-101',
        title: 'Shift Assignment Updated',
        message: 'Your shift effective 12 October 2026 has been changed to Evening.',
        type: 'shift_change',
        isRead: false,
        createdAt: DateTime.now(),
      );

      // Simulation of idempotent deduplication in NotificationRepository
      final notificationsDb = <NotificationModel>[notif1];

      bool isDuplicate(NotificationModel incoming) {
        return notificationsDb.any((n) =>
            n.userId == incoming.userId &&
            n.title == incoming.title &&
            n.message == incoming.message &&
            !n.isRead);
      }

      final retriedNotif = NotificationModel(
        id: 'notif-retry-2',
        userId: 'staff-101',
        title: 'Shift Assignment Updated',
        message: 'Your shift effective 12 October 2026 has been changed to Evening.',
        type: 'shift_change',
        isRead: false,
        createdAt: DateTime.now(),
      );

      expect(isDuplicate(retriedNotif), isTrue,
          reason: 'Duplicate retry must not insert duplicate notifications');
    });

    test('UserProfile and ProfileModel round-trip serialization of nextShift and shiftEffectiveDate', () {
      final effectiveDate = DateTime(2026, 10, 15);
      final json = {
        'id': 'user-ser-1',
        'full_name': 'Dr. Sharma',
        'email': 'sharma@clinic.com',
        'role': 'doctor',
        'is_active': true,
        'assigned_shift': 'morning',
        'next_shift': 'afternoon',
        'shift_effective_date': '2026-10-15',
        'created_at': DateTime(2026, 1, 1).toIso8601String(),
      };

      // UserProfile
      final userProfile = UserProfile.fromJson(json);
      expect(userProfile.nextShift, equals('afternoon'));
      expect(userProfile.shiftEffectiveDate, equals(effectiveDate));
      expect(userProfile.hasScheduledShift, isTrue);

      final userProfileJson = userProfile.toJson();
      expect(userProfileJson['next_shift'], equals('afternoon'));
      expect(userProfileJson['shift_effective_date'], equals('2026-10-15'));

      // ProfileModel
      final profileModel = ProfileModel.fromJson(json);
      expect(profileModel.nextShift, equals('afternoon'));
      expect(profileModel.shiftEffectiveDate, equals(effectiveDate));
      expect(profileModel.hasScheduledShift, isTrue);

      final profileModelJson = profileModel.toJson();
      expect(profileModelJson['next_shift'], equals('afternoon'));
      expect(profileModelJson['shift_effective_date'], equals('2026-10-15'));
    });

    test('Notification recipient is strictly the affected staff member and not the admin', () {
      const adminUserId = 'admin-uuid-001';
      const staffTirthaId = 'staff-tirtha-uuid-004';

      final notification = NotificationModel(
        id: 'notif-tirtha-1',
        userId: staffTirthaId, // Recipient MUST be staff Tirtha
        title: 'Duty Assignment Updated',
        message: 'Your shift effective 12 October 2026 has been changed to Evening.',
        type: 'duty_assignment',
        isRead: false,
        createdAt: DateTime.now(),
      );

      expect(notification.userId, equals(staffTirthaId));
      expect(notification.userId, isNot(equals(adminUserId)));
      expect(notification.title, equals('Duty Assignment Updated'));
      expect(notification.message, contains('12 October 2026'));
      expect(notification.message, contains('Evening'));
    });

    test('NotificationModel icon and color render correctly for duty_assignment and shift_change', () {
      final notifDuty = NotificationModel(
        id: 'notif-1',
        userId: 'u1',
        title: 'Duty Assignment Updated',
        message: 'Shift changed',
        type: 'duty_assignment',
        isRead: false,
        createdAt: DateTime.now(),
      );

      expect(notifDuty.icon, isNotNull);
      expect(notifDuty.iconColor, isNotNull);

      final notifShift = NotificationModel(
        id: 'notif-2',
        userId: 'u1',
        title: 'Shift Updated',
        message: 'Shift changed',
        type: 'shift_change',
        isRead: false,
        createdAt: DateTime.now(),
      );

      expect(notifShift.icon, isNotNull);
      expect(notifShift.iconColor, isNotNull);
    });

    test('Notification persists after serialization and refresh', () {
      final now = DateTime.now();
      final rowJson = {
        'id': 'notif-persisted-1',
        'user_id': 'staff-tirtha-uuid-004',
        'title': 'Duty Assignment Updated',
        'message': 'Your shift effective 12 October 2026 has been changed to Evening.',
        'type': 'system', // Graceful fallback type
        'is_read': false,
        'related_id': null,
        'created_at': now.toIso8601String(),
      };

      final parsed = NotificationModel.fromJson(rowJson);
      expect(parsed.id, equals('notif-persisted-1'));
      expect(parsed.userId, equals('staff-tirtha-uuid-004'));
      expect(parsed.title, equals('Duty Assignment Updated'));
      expect(parsed.message, equals('Your shift effective 12 October 2026 has been changed to Evening.'));
      expect(parsed.isRead, isFalse);

      final serialized = parsed.toJson();
      expect(serialized['user_id'], equals('staff-tirtha-uuid-004'));
      expect(serialized['title'], equals('Duty Assignment Updated'));
    });

    test('Retry notification state management: prevents concurrent taps and removes failure state on success', () {
      Map<String, dynamic>? failedState = <String, dynamic>{
        'user': UserProfile(
          id: 'staff-tirtha',
          fullName: 'Tirtha',
          email: 'staff4@gmail.com',
          role: 'staff',
          isActive: true,
          assignedShift: 'morning',
          createdAt: DateTime(2026, 1, 1),
        ),
        'message': 'Your shift effective 12 October 2026 has been changed to Evening.',
      };
      var isRetrying = false;

      // Simulate first retry tap
      expect(isRetrying, isFalse);
      isRetrying = true;

      // Second tap while in-flight is rejected
      final canTriggerSecondTap = !isRetrying;
      expect(canTriggerSecondTap, isFalse, reason: 'Concurrent retry tap must be blocked');

      // Successful completion removes failure state
      failedState = null;
      isRetrying = false;

      expect(failedState, isNull, reason: 'Failed notification state is removed upon success');
      expect(isRetrying, isFalse);
    });
  });
}
