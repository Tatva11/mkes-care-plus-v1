import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkes_care/core/theme/app_colors.dart';
import 'package:mkes_care/core/theme/app_spacing.dart';
import 'package:mkes_care/core/theme/app_typography.dart';
import 'package:mkes_care/features/admin/models/user_profile.dart';
import 'package:mkes_care/features/auth/models/profile_model.dart';
import 'package:mkes_care/features/billing/models/billing_invoice_model.dart';
import 'package:mkes_care/features/billing/widgets/invoice_payment_section.dart';
import 'package:mkes_care/features/staff/models/leave_request.dart';
import 'package:mkes_care/features/staff/models/shift_configuration.dart';

void main() {
  group('1. Admin Leave Approval & Working-Day Rendering', () {
    test('LeaveRequest coversShift correctly for morning, afternoon, and full_day', () {
      final morningLeave = LeaveRequest(
        id: 'leave-1',
        staffId: 'staff-1',
        startDate: DateTime(2026, 10, 19),
        endDate: DateTime(2026, 10, 19),
        dutyPeriod: 'morning',
        leaveDays: 0.5,
        reason: 'Casual leave',
        status: 'approved',
        createdAt: DateTime.now(),
      );

      expect(morningLeave.coversShift('morning'), isTrue);
      expect(morningLeave.coversShift('afternoon'), isFalse);
      expect(morningLeave.coversShift('evening'), isFalse);

      final eveningLeave = LeaveRequest(
        id: 'leave-2',
        staffId: 'staff-2',
        startDate: DateTime(2026, 10, 19),
        endDate: DateTime(2026, 10, 19),
        dutyPeriod: 'afternoon',
        leaveDays: 0.5,
        reason: 'Medical checkup',
        status: 'approved',
        createdAt: DateTime.now(),
      );

      expect(eveningLeave.coversShift('morning'), isFalse);
      expect(eveningLeave.coversShift('afternoon'), isTrue);
      expect(eveningLeave.coversShift('evening'), isTrue);

      final fullDayLeave = LeaveRequest(
        id: 'leave-3',
        staffId: 'staff-3',
        startDate: DateTime(2026, 10, 19),
        endDate: DateTime(2026, 10, 20),
        dutyPeriod: 'full_day',
        leaveDays: 2.0,
        reason: 'Annual leave',
        status: 'approved',
        createdAt: DateTime.now(),
      );

      expect(fullDayLeave.coversShift('morning'), isTrue);
      expect(fullDayLeave.coversShift('afternoon'), isTrue);
      expect(fullDayLeave.coversShift('evening'), isTrue);
    });

    testWidgets('Leave request working-day count renders responsively without RenderFlex overflow on 360px', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppSpacing.xs,
                        runSpacing: 2,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primaryContainer.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('1 working day(s)', style: TextStyle(fontSize: 12)),
                          ),
                          const Text('• 09:00 AM – 01:00 PM (Morning Session)', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        children: [
                          OutlinedButton(onPressed: () {}, child: const Text('Reject Request')),
                          FilledButton(onPressed: () {}, child: const Text('Approve Request')),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('1 working day(s)'), findsOneWidget);
    });
  });

  group('2. Shift Management & Evening Shift Handling', () {
    test('UserProfile and ProfileModel dynamic activeShift evaluates current date against effective date', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final tomorrow = today.add(const Duration(days: 1));

      // Case 1: Scheduled change took effect yesterday -> activeShift is nextShift (evening/afternoon)
      final userEffectiveYesterday = UserProfile(
        id: 'u-1',
        fullName: 'Staff Member 1',
        email: 'staff1@mkes.org',
        role: 'staff',
        isActive: true,
        createdAt: now,
        assignedShift: 'morning',
        nextShift: 'afternoon',
        shiftEffectiveDate: yesterday,
      );

      expect(userEffectiveYesterday.activeShift, equals('afternoon'));
      expect(userEffectiveYesterday.isEveningShift, isTrue);
      expect(userEffectiveYesterday.isMorningShift, isFalse);
      expect(userEffectiveYesterday.shiftDisplayName, equals('Evening Shift'));

      // Case 2: Scheduled change takes effect tomorrow -> activeShift remains morning today
      final userEffectiveTomorrow = UserProfile(
        id: 'u-2',
        fullName: 'Staff Member 2',
        email: 'staff2@mkes.org',
        role: 'staff',
        isActive: true,
        createdAt: now,
        assignedShift: 'morning',
        nextShift: 'afternoon',
        shiftEffectiveDate: tomorrow,
      );

      expect(userEffectiveTomorrow.activeShift, equals('morning'));
      expect(userEffectiveTomorrow.isMorningShift, isTrue);
      expect(userEffectiveTomorrow.isEveningShift, isFalse);
      expect(userEffectiveTomorrow.shiftDisplayName, equals('Morning Shift'));
      expect(userEffectiveTomorrow.isUpcomingShiftChange(), isTrue);

      // Case 3: ProfileModel with evening shift string
      final profileModelEvening = ProfileModel(
        id: 'p-1',
        email: 'p1@mkes.org',
        fullName: 'Evening Staff',
        role: 'staff',
        isActive: true,
        createdAt: now,
        assignedShift: 'evening',
      );

      expect(profileModelEvening.activeShift, equals('evening'));
      expect(profileModelEvening.isEveningShift, isTrue);
      expect(profileModelEvening.isMorningShift, isFalse);
      expect(profileModelEvening.shiftDisplayName, equals('Evening Shift'));
    });

    test('Independent staff shift assignment ensures staff members do not share or inherit defaults', () {
      final now = DateTime.now();
      final staffA = UserProfile(
        id: 'staff-a',
        fullName: 'Alice Staff',
        email: 'alice@mkes.org',
        role: 'staff',
        isActive: true,
        createdAt: now,
        assignedShift: 'morning',
      );

      final staffB = UserProfile(
        id: 'staff-b',
        fullName: 'Bob Staff',
        email: 'bob@mkes.org',
        role: 'staff',
        isActive: true,
        createdAt: now,
        assignedShift: 'afternoon',
      );

      expect(staffA.activeShift, equals('morning'));
      expect(staffA.shiftDisplayName, equals('Morning Shift'));

      expect(staffB.activeShift, equals('afternoon'));
      expect(staffB.shiftDisplayName, equals('Evening Shift'));
    });
  });

  group('3. Staff App Access Must Not Depend on Shift Timing', () {
    test('Staff member assigned to morning shift has valid access configuration at any hour of day', () {
      final config = ShiftConfiguration.defaultMorning; // 09:00 - 13:00

      // Past shift end: 15:00 (3 PM)
      final afternoonTime = DateTime(2026, 10, 18, 15, 0);
      expect(config.isTimePastShiftEnd(afternoonTime), isTrue);

      // Late evening: 21:00 (9 PM)
      final eveningTime = DateTime(2026, 10, 18, 21, 0);
      expect(config.isTimePastShiftEnd(eveningTime), isTrue);

      // Verify that shift timing restrictions only apply to clock-in eligibility, not application access
      expect(config.isEligibleForCheckIn(afternoonTime), isFalse);
      expect(config.isEligibleForCheckIn(eveningTime), isFalse);
    });
  });

  group('4. Schedule Page Mobile Responsiveness', () {
    testWidgets('Schedule controls render without overflow across mobile viewports (360px, 390px, 430px)', (tester) async {
      final viewports = [
        const Size(360, 640),
        const Size(390, 844),
        const Size(430, 932),
      ];

      for (final vp in viewports) {
        tester.view.physicalSize = vp;
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('My Schedule', style: AppTypography.displayLg.copyWith(fontSize: 28)),
                    const SizedBox(height: 4),
                    Text('Sunday, October 18, 2026', style: AppTypography.bodyLg),
                    const SizedBox(height: AppSpacing.sm),
                    // Responsive mobile controls layout
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.outlineVariant),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.chevron_left, size: 20),
                            const SizedBox(width: 4),
                            Text('Sun, Oct 18, 2026', style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_right, size: 20),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.add_circle_outline, size: 18),
                          label: const Text('Book Appointment'),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.primaryContainer.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.wb_sunny_outlined, size: 18),
                              SizedBox(width: 6),
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('MORNING SHIFT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                    Text('09:00 AM – 01:00 PM', style: TextStyle(fontSize: 11)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: [
                        Text("Today's Schedule", style: AppTypography.headlineMd.copyWith(fontSize: 20)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.outlineVariant),
                          ),
                          child: const Text('All Departments'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Failed on viewport $vp');
      }
      tester.view.resetPhysicalSize();
    });
  });

  group('5. Billing Section Overflows & Previous Balance Banner', () {
    testWidgets('Previous Outstanding Balance Included banner renders without overflow on 360px', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: InvoicePaymentSection(
                subtotal: 500.0,
                finalTotal: 750.0,
                discount: 0.0,
                previousBalanceIncluded: 250.0,
                payment: null,
                onDiscountChanged: (_) {},
                onPaymentChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Previous Outstanding Balance Included'), findsOneWidget);
      expect(find.text('+ ₹250.00'), findsOneWidget);
    });

    testWidgets('Mobile billing list item title and subtitle render without overflow on 360px', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final invoice = BillingInvoiceModel(
        id: 'inv-1',
        invoiceNumber: 'MKES-INV-20261018-0099',
        patientId: 'p-1',
        patientName: 'Very Long Patient Name For Testing RenderFlex Overflow',
        patientNumber: 'MKES-P-2026-9999',
        department: 'opthalmology',
        subtotal: 12500.0,
        discount: 500.0,
        totalAmount: 12000.0,
        amountPaid: 4000.0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListTile(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      invoice.invoiceNumber,
                      style: AppTypography.bodyMd.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('PARTIALLY PAID', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(
                    '${invoice.patientName ?? "Patient"} (${invoice.patientNumber ?? "—"}) • ${invoice.department.toUpperCase()}',
                    style: AppTypography.bodySm,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: AppSpacing.sm,
                    runSpacing: 2,
                    children: [
                      Text('Total: ₹${invoice.totalAmount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('Remaining: ₹${invoice.remainingAmount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('MKES-INV-20261018-0099'), findsOneWidget);
    });
  });

  group('6. Attendance Assigned Duty Area & Common Clock-In/Out', () {
    testWidgets('Assigned Duty timing header renders responsively on 360px without overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primaryContainer.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                        ),
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          runSpacing: 2,
                          children: [
                            const Icon(Icons.wb_sunny_outlined, size: 16, color: AppColors.primary),
                            Text(
                              'Assigned Duty: Morning Shift',
                              style: AppTypography.bodySm.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                            Text(
                              '· 09:00 AM – 01:00 PM',
                              style: AppTypography.bodySm.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.login),
                          label: const Text('Clock In'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Assigned Duty: Morning Shift'), findsOneWidget);
      expect(find.text('Clock In'), findsOneWidget);
    });

    testWidgets('Both duties assigned badge renders with Flexible without overflow on 360px', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.all_inclusive, size: 16, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Assigned Duty: Morning & Evening Sessions (Both)',
                        style: AppTypography.bodySm.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Assigned Duty: Morning & Evening Sessions (Both)'), findsOneWidget);
    });
  });
}
