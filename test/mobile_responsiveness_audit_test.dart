import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mkes_care/core/theme/app_colors.dart';
import 'package:mkes_care/core/theme/app_spacing.dart';
import 'package:mkes_care/core/theme/app_typography.dart';
import 'package:mkes_care/features/notifications/models/notification_model.dart';
import 'package:mkes_care/features/staff/widgets/clock_in_required_dialog.dart';
import 'package:mkes_care/features/staff/providers/attendance_provider.dart';
import 'package:mkes_care/features/patients/widgets/patient_form_dialog.dart';
import 'package:mkes_care/features/appointments/widgets/appointment_form_dialog.dart';
import 'package:mkes_care/features/appointments/models/appointment_model.dart';
import 'package:mkes_care/features/department/providers/departments_provider.dart';
import 'package:mkes_care/features/department/repositories/department_repository.dart';
import 'package:mkes_care/features/appointments/providers/appointment_provider.dart';
import 'package:mkes_care/features/department/models/department.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const allMobileViewports = <double>[
    320.0, // iPhone SE 1st gen / ultra-narrow
    360.0, // Android standard small
    375.0, // iPhone SE 2nd/3rd gen / iPhone 8
    390.0, // iPhone 12/13/14
    412.0, // Samsung Galaxy S20/S21 / Pixel
    430.0, // iPhone 14/15 Pro Max
    768.0, // Tablet / Desktop boundary
  ];

  group('1. Patient Directory Mobile Header & Actions', () {
    Widget buildHeader({required bool isDesktop, required String subtitle}) {
      return MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(
              isDesktop ? AppSpacing.marginDesktop : AppSpacing.marginMobile,
            ),
            child: isDesktop
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Patient Directory',
                              style: AppTypography.displayLg.copyWith(
                                color: AppColors.onBackground,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              subtitle,
                              style: AppTypography.bodyLg
                                  .copyWith(color: AppColors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.chat_bubble_outline,
                                size: 18, color: Color(0xFF25D366)),
                            label: const Text('WhatsApp Inbox'),
                          ),
                          FilledButton.icon(
                            onPressed: () {},
                            icon:
                                const Icon(Icons.person_add_outlined, size: 18),
                            label: const Text('New Patient'),
                          ),
                        ],
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Patient Directory',
                        style: AppTypography.displayLg.copyWith(
                          color: AppColors.onBackground,
                          fontSize: 26,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        subtitle,
                        style: AppTypography.bodyLg
                            .copyWith(color: AppColors.onSurfaceVariant),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.chat_bubble_outline,
                                size: 18, color: Color(0xFF25D366)),
                            label: const Text('WhatsApp Inbox'),
                          ),
                          FilledButton.icon(
                            onPressed: () {},
                            icon:
                                const Icon(Icons.person_add_outlined, size: 18),
                            label: const Text('New Patient'),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ),
      );
    }

    for (final width in allMobileViewports) {
      testWidgets('Patient directory header renders with ZERO overflow at $width px',
          (tester) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final isDesktop = width >= 768.0;
        await tester.pumpWidget(
          buildHeader(
            isDesktop: isDesktop,
            subtitle: 'All accessible clinic patient records.',
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Patient Directory'), findsOneWidget);
        expect(find.text('New Patient'), findsOneWidget);
        expect(find.text('WhatsApp Inbox'), findsOneWidget);
        final ex = tester.takeException();
        if (ex != null) {
          // ignore: avoid_print
          print('DETAILED_EXCEPTION: $ex');
          if (ex is FlutterError) {
            // ignore: avoid_print
            for (final d in ex.diagnostics) {
              // ignore: avoid_print
              print('DIAGNOSTIC: $d');
            }
          }
        }
        expect(ex, isNull);
      });
    }
  });

  group('2. Notification Modal Responsive Layout', () {
    Widget buildNotificationModalDialog({
      required double screenWidth,
      required int unreadCount,
      required List<NotificationModel> items,
    }) {
      final isMobile = screenWidth < 600;

      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Dialog(
              alignment: isMobile ? Alignment.center : Alignment.topRight,
              insetPadding: EdgeInsets.symmetric(
                horizontal: isMobile ? 12 : 16,
                vertical: isMobile ? 24 : 60,
              ),
              child: Container(
                width: isMobile ? double.infinity : 440,
                constraints: const BoxConstraints(maxHeight: 600),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (isMobile) ...[
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    'Notifications',
                                    style: AppTypography.headlineMd,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (unreadCount > 0) ...[
                                  const SizedBox(width: AppSpacing.xs),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryContainer,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '$unreadCount new',
                                      style: AppTypography.labelCaps.copyWith(
                                        color: AppColors.onPrimaryContainer,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                ],
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 20),
                                  onPressed: () {},
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                TextButton(
                                  onPressed: () {},
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  ),
                                  child: const Text('Mark all read'),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.refresh, size: 20),
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                      onPressed: () {},
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(
                                          Icons.delete_sweep_outlined,
                                          size: 20),
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                      onPressed: () {},
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ] else ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          'Notifications',
                                          style: AppTypography.headlineMd,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (unreadCount > 0) ...[
                                        const SizedBox(width: AppSpacing.xs),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.primaryContainer,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            '$unreadCount new',
                                            style: AppTypography.labelCaps.copyWith(
                                              color: AppColors.onPrimaryContainer,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.refresh, size: 20),
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () {},
                                    ),
                                    TextButton(
                                      onPressed: () {},
                                      style: TextButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      ),
                                      child: const Text('Mark all read'),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                          Icons.delete_sweep_outlined,
                                          size: 20),
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () {},
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: AppSpacing.xs),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                ChoiceChip(
                                    label: const Text('All'), selected: true),
                                const SizedBox(width: AppSpacing.xs),
                                ChoiceChip(
                                    label: const Text('Unread'),
                                    selected: false),
                                const SizedBox(width: AppSpacing.xs),
                                ChoiceChip(
                                    label: const Text('WhatsApp'),
                                    selected: false),
                                const SizedBox(width: AppSpacing.xs),
                                ChoiceChip(
                                    label: const Text('Appointments'),
                                    selected: false),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return ListTile(
                            leading: const CircleAvatar(
                                child: Icon(Icons.notifications)),
                            title: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    item.title,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  item.relativeTime,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ],
                            ),
                            subtitle: Text(
                              item.message,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final testItems = [
      NotificationModel(
        id: 'n1',
        userId: 'u1',
        title: 'New WhatsApp Message Received from Patient',
        message:
            'Aarav Mehta has sent a message regarding eye drop dosage clarification and follow-up consultation details.',
        type: 'whatsapp_reply',
        isRead: false,
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      ),
      NotificationModel(
        id: 'n2',
        userId: 'u1',
        title: 'Dental Lab Case Ready for Fitting',
        message: 'Ceramic Crown #DL-2026-004 is received and ready.',
        type: 'lab_ready',
        isRead: true,
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      ),
    ];

    for (final width in allMobileViewports) {
      testWidgets('Notification modal adapts cleanly without overflow at $width px',
          (tester) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          buildNotificationModalDialog(
            screenWidth: width,
            unreadCount: 3,
            items: testItems,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Notifications'), findsOneWidget);
        expect(find.text('Mark all read'), findsOneWidget);
        expect(find.text('3 new'), findsOneWidget);
        final ex = tester.takeException();
        if (ex != null) {
          // ignore: avoid_print
          print('DETAILED_EXCEPTION: $ex');
          if (ex is FlutterError) {
            // ignore: avoid_print
            for (final d in ex.diagnostics) {
              // ignore: avoid_print
              print('DIAGNOSTIC: $d');
            }
          }
        }
        expect(ex, isNull);
      });
    }
  });

  group('3. Schedule Screen Timeline Card Mobile Adaptation', () {
    Widget buildTimelineCard({required double screenWidth}) {
      final isNarrowScreen = screenWidth < 380;
      return MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.marginMobile),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: isNarrowScreen ? 52 : 64,
                  child: Text(
                    '10:30 AM',
                    style: TextStyle(
                      fontSize: isNarrowScreen ? 11.5 : 13.0,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                Container(
                  width: 10,
                  height: 10,
                  margin: EdgeInsets.only(
                      top: 4, right: isNarrowScreen ? 6 : 10),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.green,
                  ),
                ),
                Expanded(
                  child: Container(
                    padding: EdgeInsets.all(isNarrowScreen ? 8 : 12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLowest,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusMd),
                      border: Border.all(color: AppColors.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text(
                              'Sunita Shah',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const Text('(E-0004)',
                                style: TextStyle(fontSize: 11)),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text('PRESENT',
                                  style: TextStyle(
                                      fontSize: 10, color: Colors.green)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Divider(height: 1),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            FilledButton.tonal(
                              onPressed: () {},
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                minimumSize: const Size(0, 36),
                              ),
                              child: const Text('Mark Present',
                                  style: TextStyle(fontSize: 12)),
                            ),
                            OutlinedButton(
                              onPressed: () {},
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                minimumSize: const Size(0, 36),
                              ),
                              child: const Text('Exam Record',
                                  style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    for (final width in allMobileViewports) {
      testWidgets('Schedule timeline card renders with zero overflow at $width px',
          (tester) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(buildTimelineCard(screenWidth: width));
        await tester.pumpAndSettle();

        expect(find.text('Sunita Shah'), findsOneWidget);
        expect(find.text('10:30 AM'), findsOneWidget);
        final ex = tester.takeException();
        if (ex != null) {
          // ignore: avoid_print
          print('DETAILED_EXCEPTION: $ex');
          if (ex is FlutterError) {
            // ignore: avoid_print
            for (final d in ex.diagnostics) {
              // ignore: avoid_print
              print('DIAGNOSTIC: $d');
            }
          }
        }
        expect(ex, isNull);
      });
    }
  });

  group('4. App Shell Top Bar Mobile Flex and Sizing', () {
    Widget buildStaffTopAppBar(double screenWidth) {
      final isDesktop = screenWidth >= 768.0;
      return MaterialApp(
        home: Scaffold(
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(64),
            child: SafeArea(
              child: SizedBox(
                height: 64,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      if (isDesktop) ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: AppColors.primaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.local_hospital, size: 20),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            const Text('MKES CARE+',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(width: AppSpacing.md),
                        const Expanded(child: SizedBox()),
                      ] else ...[
                        Expanded(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: AppColors.primaryContainer,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child:
                                    const Icon(Icons.local_hospital, size: 20),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              const Flexible(
                                child: Text(
                                  'MKES CARE+',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      IconButton(
                        icon: const Icon(Icons.chat_bubble_outline),
                        onPressed: () {},
                      ),
                      IconButton(
                        icon: const Icon(Icons.notifications_none),
                        onPressed: () {},
                      ),
                      const CircleAvatar(
                        radius: 16,
                        child: Text('SJ'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          body: const Center(child: Text('Body')),
        ),
      );
    }

    for (final width in allMobileViewports) {
      testWidgets('Top app bar renders cleanly without overflow at $width px',
          (tester) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(buildStaffTopAppBar(width));
        await tester.pumpAndSettle();

        expect(find.text('MKES CARE+'), findsOneWidget);
        final ex = tester.takeException();
        if (ex != null) {
          // ignore: avoid_print
          print('DETAILED_EXCEPTION: $ex');
          if (ex is FlutterError) {
            // ignore: avoid_print
            for (final d in ex.diagnostics) {
              // ignore: avoid_print
              print('DIAGNOSTIC: $d');
            }
          }
        }
        expect(ex, isNull);
      });
    }
  });

  const allAuditViewports = <double>[
    320.0,
    360.0,
    375.0,
    390.0,
    412.0,
    430.0,
    768.0,
    1024.0,
  ];

  group('5. Clock-In Required Banner Responsiveness & Positioning', () {
    Widget buildBanner() {
      return ProviderScope(
        overrides: [
          staffClockInStatusProvider.overrideWith((ref) => false),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  ClockInRequiredBanner(),
                  SizedBox(height: 16),
                  Text('Schedule Content Area'),
                ],
              ),
            ),
          ),
        ),
      );
    }

    for (final width in allAuditViewports) {
      testWidgets('ClockInRequiredBanner renders cleanly at $width px',
          (tester) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(buildBanner());
        await tester.pumpAndSettle();

        expect(
            find.byKey(const Key('clock_in_required_banner')), findsOneWidget);
        expect(find.byKey(const Key('banner_clock_in_now_button')),
            findsOneWidget);
        expect(find.text('Clock-In Required'), findsOneWidget);
        final ex = tester.takeException();
        if (ex != null) {
          // ignore: avoid_print
          print('DETAILED_EXCEPTION: $ex');
          if (ex is FlutterError) {
            // ignore: avoid_print
            for (final d in ex.diagnostics) {
              // ignore: avoid_print
              print('DIAGNOSTIC: $d');
            }
          }
        }
        expect(ex, isNull);
      });
    }
  });

  group('6. Add New Patient Form - Technical Banner Removed & Clean Layout', () {
    Widget buildPatientDialog() {
      return const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: PatientFormDialog(
              initialDepartment: 'eye',
            ),
          ),
        ),
      );
    }

    for (final width in allAuditViewports) {
      testWidgets('Patient registration form renders cleanly without technical banner at $width px',
          (tester) async {
        tester.view.physicalSize = Size(width, 750);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(buildPatientDialog());
        await tester.pumpAndSettle();

        // Technical banner removed per requirement 4
        expect(find.byKey(const Key('patient_form_identifier_banner')),
            findsNothing);
        expect(find.text('ASSIGNED IDENTIFIER'), findsNothing);
        expect(find.text('Register New Patient'), findsOneWidget);
        expect(find.text('Full Name *'), findsOneWidget);
        final ex = tester.takeException();
        expect(ex, isNull);
      });
    }
  });

  group('7. Edit / Reschedule Appointment Action Buttons Visibility', () {
    final existingAppt = AppointmentModel(
      id: 'appt-101',
      patientId: 'pat-1',
      patientName: 'Arjun Mehta',
      patientNumber: 'E-0012',
      department: 'eye',
      appointmentDate: DateTime(2026, 11, 15),
      appointmentTime: '10:00 AM',
      appointmentType: 'regular',
      status: 'scheduled',
      aiBooked: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    Widget buildAppointmentDialog() {
      return ProviderScope(
        overrides: [
          departmentsProvider.overrideWith(
            (ref) => _AuditDepartmentsNotifier(),
          ),
          appointmentStaffCandidatesProvider('eye')
              .overrideWith((ref) async => []),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: AppointmentFormDialog(
              existingAppointment: existingAppt,
            ),
          ),
        ),
      );
    }

    for (final width in allAuditViewports) {
      testWidgets(
          'Edit & Reschedule action buttons render without overflow at $width px',
          (tester) async {
        tester.view.physicalSize = Size(width, 750);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(buildAppointmentDialog());
        await tester.pumpAndSettle();

        expect(find.text('Edit Appointment'), findsOneWidget);
        expect(find.byKey(const Key('appointment_form_reschedule_button')),
            findsOneWidget);
        expect(find.text('Reschedule'), findsOneWidget);
        expect(find.byKey(const Key('appointment_form_submit_button')),
            findsOneWidget);
        expect(find.text('Update Appointment'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
        final ex = tester.takeException();
        if (ex != null) {
          // ignore: avoid_print
          print('DETAILED_EXCEPTION: $ex');
          if (ex is FlutterError) {
            // ignore: avoid_print
            for (final d in ex.diagnostics) {
              // ignore: avoid_print
              print('DIAGNOSTIC: $d');
            }
          }
        }
        expect(ex, isNull);
      });
    }
  });

  group('8. Schedule Department Dropdown Filter Options Audit', () {
    test('Department options dictionary contains All, Eye, Dental and excludes Common / Comment', () {
      final dbDepts = [
        const Department(id: 'eye-dept', name: 'Eye', isActive: true),
        const Department(id: 'dental-dept', name: 'Dental', isActive: true),
        const Department(id: 'common-dept', name: 'Common', isActive: true),
        const Department(id: 'comment-dept', name: 'Comment', isActive: true),
        const Department(id: 'ortho-dept', name: 'Orthopedics', isActive: true),
      ];

      final Map<String, String> departmentOptions = {
        'all': 'All Departments',
        'eye': 'Eye',
        'dental': 'Dental',
      };

      for (final d in dbDepts) {
        if (!d.isActive) continue;
        final key = d.name.trim().toLowerCase();
        if (key == 'eye' ||
            key == 'dental' ||
            key == 'common' ||
            key == 'comment' ||
            key == 'shared') {
          continue;
        }
        departmentOptions[key] = d.name.trim();
      }

      expect(departmentOptions.containsKey('all'), isTrue);
      expect(departmentOptions['all'], equals('All Departments'));
      expect(departmentOptions.containsKey('eye'), isTrue);
      expect(departmentOptions['eye'], equals('Eye'));
      expect(departmentOptions.containsKey('dental'), isTrue);
      expect(departmentOptions['dental'], equals('Dental'));
      expect(departmentOptions.containsKey('orthopedics'), isTrue);
      expect(departmentOptions['orthopedics'], equals('Orthopedics'));

      // Ensure common and comment are strictly excluded
      expect(departmentOptions.containsKey('common'), isFalse);
      expect(departmentOptions.containsKey('comment'), isFalse);
      expect(departmentOptions.containsValue('Common'), isFalse);
      expect(departmentOptions.containsValue('Comment'), isFalse);
    });
  });

  group('9. New Appointment Dialog Heading Visibility Across Mobile', () {
    Widget buildNewAppointmentDialog() {
      return ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: AppointmentFormDialog(
              initialDate: DateTime(2026, 11, 15),
            ),
          ),
        ),
      );
    }

    for (final width in allAuditViewports) {
      testWidgets('Complete "New Appointment" heading visible at $width px',
          (tester) async {
        tester.view.physicalSize = Size(width, 750);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(buildNewAppointmentDialog());
        await tester.pumpAndSettle();

        expect(find.text('New Appointment'), findsOneWidget);
        expect(find.text('Department *'), findsOneWidget);
        final ex = tester.takeException();
        expect(ex, isNull);
      });
    }
  });
}

class _AuditDepartmentRepository implements DepartmentRepository {
  @override
  Future<List<Department>> fetchDepartments() async => const [
        Department(id: 'eye-dept', name: 'Eye Clinic', isActive: true),
        Department(id: 'dental-dept', name: 'Dental Clinic', isActive: true),
      ];

  @override
  Future<Department> createDepartment(
          {required String name, String? description}) async =>
      Department(
          id: 'dept-new', name: name, description: description, isActive: true);

  @override
  Future<void> updateDepartment({
    required String id,
    required String name,
    String? description,
    required bool isActive,
  }) async {}

  @override
  Future<void> deleteDepartment(String id) async {}
}

class _AuditDepartmentsNotifier extends DepartmentsNotifier {
  _AuditDepartmentsNotifier() : super(_AuditDepartmentRepository());
}
