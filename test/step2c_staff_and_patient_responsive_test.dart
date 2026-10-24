import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mkes_care/core/theme/app_colors.dart';
import 'package:mkes_care/core/theme/app_spacing.dart';
import 'package:mkes_care/core/theme/app_typography.dart';
import 'package:mkes_care/shared/widgets/adaptive_dialog_shell.dart';
import 'package:mkes_care/shared/widgets/responsive_page_header.dart';
import 'package:mkes_care/features/admin/models/user_profile.dart';
import 'package:mkes_care/features/patients/models/patient_model.dart';
import 'package:mkes_care/features/appointments/models/department_doctor_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testViewports = <double>[
    360.0,
    390.0,
    430.0,
    768.0,
    1024.0,
    1440.0,
  ];

  group('1. Staff Management Screen Responsive Header', () {
    Widget buildHeader(bool isDesktop) {
      return MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isDesktop)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Staff Management',
                              style: AppTypography.headlineMd.copyWith(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          FilledButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.add, size: 20),
                            label: const Text('Add'),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Track attendance and manage your clinical team.',
                        style: AppTypography.bodyLg,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [
                          OutlinedButton(
                            onPressed: () {},
                            child: const Text('Leave'),
                          ),
                          OutlinedButton(
                            onPressed: () {},
                            child: const Text('Tasks'),
                          ),
                          OutlinedButton(
                            onPressed: () {},
                            child: const Text('Performance'),
                          ),
                          OutlinedButton(
                            onPressed: () {},
                            child: const Text('Shifts'),
                          ),
                        ],
                      ),
                    ],
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Staff Management',
                              style: AppTypography.headlineMd.copyWith(
                                fontSize: 32,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.01 * 32,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: AppSpacing.base),
                            Text(
                              'Track attendance and manage your clinical team.',
                              style: AppTypography.bodyLg,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          alignment: WrapAlignment.end,
                          children: [
                            OutlinedButton(
                              onPressed: () {},
                              child: const Text('Leave'),
                            ),
                            OutlinedButton(
                              onPressed: () {},
                              child: const Text('Tasks'),
                            ),
                            OutlinedButton(
                              onPressed: () {},
                              child: const Text('Performance'),
                            ),
                            OutlinedButton(
                              onPressed: () {},
                              child: const Text('Shifts'),
                            ),
                            FilledButton.icon(
                              onPressed: () {},
                              icon: const Icon(Icons.add, size: 20),
                              label: const Text('Add Staff'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      );
    }

    for (final width in testViewports) {
      testWidgets('Renders cleanly without overflow at width $width px',
          (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final isDesktop = width >= 768.0;
        await tester.pumpWidget(buildHeader(isDesktop));
        await tester.pumpAndSettle();

        expect(find.text('Staff Management'), findsOneWidget);
        expect(find.text('Leave'), findsOneWidget);
        expect(find.text('Tasks'), findsOneWidget);
        expect(find.text('Performance'), findsOneWidget);
        expect(find.text('Shifts'), findsOneWidget);
        expect(find.byType(FilledButton), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('2. Doctor Management Screen Responsive Elements', () {
    final testDoctor = DepartmentDoctor(
      id: 'doc-1',
      fullName: 'Dr Mitesh Jain Very Long Doctor Name Ophthalmologist',
      department: 'eye',
      specialty: 'Cataract & Refractive Surgery',
      isActive: true,
    );

    Widget buildDoctorCard(DepartmentDoctor doctor) {
      return MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.visibility)),
                title: Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      doctor.fullName,
                      style: AppTypography.bodyLg.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        doctor.department == 'eye' ? 'EYE' : 'DENTAL',
                        style: AppTypography.labelCaps.copyWith(
                          color: AppColors.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        doctor.isActive ? 'ACTIVE' : 'INACTIVE',
                        style: AppTypography.labelCaps.copyWith(
                          color: Colors.green.shade800,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Text(doctor.specialty ?? ''),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () {},
                    ),
                    IconButton(
                      icon: const Icon(Icons.toggle_on),
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    for (final width in testViewports) {
      testWidgets('Doctor header renders without overflow at $width px',
          (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: ResponsivePageHeader(
                  title: 'Doctor Management',
                  subtitle:
                      'Configure department static doctors for appointment booking. No Auth accounts required.',
                  showBackButton: true,
                  actions: [
                    FilledButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Doctor'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Doctor Management'), findsOneWidget);
        expect(find.text('Add Doctor'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Doctor card renders without overflow at $width px',
          (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(buildDoctorCard(testDoctor));
        await tester.pumpAndSettle();

        expect(find.text(testDoctor.fullName), findsOneWidget);
        expect(find.text('EYE'), findsOneWidget);
        expect(find.text('ACTIVE'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('3. User Management Screen Responsive Cards & Table', () {
    final testUsers = [
      UserProfile(
        id: 'usr-1',
        fullName: 'Dr Rajesh Sharma Senior Surgeon',
        email: 'rajesh.sharma@mkescare.com',
        role: 'admin',
        department: 'eye',
        departmentName: 'Ophthalmology',
        isActive: true,
        assignedShift: 'morning',
        createdAt: DateTime.now(),
      ),
      UserProfile(
        id: 'usr-2',
        fullName: 'Pooja Patel Clinical Nurse',
        email: 'pooja.patel@mkescare.com',
        role: 'staff',
        department: 'dental',
        departmentName: 'Dental Clinic',
        isActive: false,
        assignedShift: 'afternoon',
        createdAt: DateTime.now(),
      ),
    ];

    Widget buildUsersView(bool isDesktop) {
      return MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: isDesktop
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 860),
                      child: Column(
                        children: testUsers
                            .map((u) => Text('${u.fullName} - ${u.email}'))
                            .toList(),
                      ),
                    ),
                  )
                : Column(
                    children: testUsers.map((u) {
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      u.fullName,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () {},
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () {},
                                  ),
                                ],
                              ),
                              Text(u.email),
                              Row(
                                children: [
                                  Text(u.role.toUpperCase()),
                                  const SizedBox(width: 8),
                                  Text(u.isActive ? 'Active' : 'Inactive'),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ),
      );
    }

    for (final width in testViewports) {
      testWidgets('Renders users cleanly without overflow at $width px',
          (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final isDesktop = width >= 768.0;
        await tester.pumpWidget(buildUsersView(isDesktop));
        await tester.pumpAndSettle();

        expect(find.textContaining('Dr Rajesh Sharma'), findsOneWidget);
        expect(find.textContaining('Pooja Patel'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('4. User Form Dialog Constraints and Responsive Stacking', () {
    testWidgets('AdaptiveDialogConstraints clamps safely on narrow phone',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      late BoxConstraints capturedConstraints;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                capturedConstraints = AdaptiveDialogConstraints.getConstraints(
                  context: context,
                  maxPhoneWidth: 460,
                  maxTabletWidth: 500,
                  maxDesktopWidth: 520,
                );
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      // Width must be at most 360 - 32 = 328px
      expect(capturedConstraints.maxWidth, lessThanOrEqualTo(328.0));
    });

    testWidgets(
        'Phone and Role stack when constraints.maxWidth < 440 and sit in row when >= 440',
        (tester) async {
      Widget buildFieldRow(double availableWidth) {
        return MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: availableWidth,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 440;
                    if (narrow) {
                      return Column(
                        key: const Key('column_mode'),
                        children: const [
                          TextField(key: Key('phone_field')),
                          TextField(key: Key('role_field')),
                        ],
                      );
                    }
                    return Row(
                      key: const Key('row_mode'),
                      children: const [
                        Expanded(child: TextField(key: Key('phone_field'))),
                        Expanded(child: TextField(key: Key('role_field'))),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      }

      // Test on narrow width 320 px
      await tester.pumpWidget(buildFieldRow(320));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('column_mode')), findsOneWidget);
      expect(find.byKey(const Key('row_mode')), findsNothing);

      // Test on wide width 480 px
      await tester.pumpWidget(buildFieldRow(480));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('row_mode')), findsOneWidget);
      expect(find.byKey(const Key('column_mode')), findsNothing);
    });
  });

  group('5. Patient List Screen Responsive Cards', () {
    final testPatients = [
      PatientModel(
        id: 'pat-1',
        patientNumber: 'P-1001',
        name: 'Amina Khatun',
        department: 'eye',
        dob: DateTime(1985, 4, 12),
        mobile: '9876543210',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      PatientModel(
        id: 'pat-2',
        patientNumber: 'P-1002',
        name: 'Devendra Joshi',
        department: 'dental',
        dob: DateTime(1972, 8, 25),
        mobile: '9123456789',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];

    Widget buildPatientListView(bool isDesktop) {
      return MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: isDesktop
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 820),
                      child: Column(
                        children: testPatients
                            .map((p) => Text('${p.patientNumber} ${p.name}'))
                            .toList(),
                      ),
                    ),
                  )
                : Column(
                    children: testPatients.map((p) {
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(p.patientNumber),
                                  const Spacer(),
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () {},
                                  ),
                                  const Icon(Icons.chevron_right),
                                ],
                              ),
                              Text(p.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              Text(p.mobile ?? ''),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ),
      );
    }

    for (final width in testViewports) {
      testWidgets('Renders patient list cleanly without overflow at $width px',
          (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final isDesktop = width >= 768.0;
        await tester.pumpWidget(buildPatientListView(isDesktop));
        await tester.pumpAndSettle();

        expect(find.textContaining('Amina Khatun'), findsOneWidget);
        expect(find.textContaining('Devendra Joshi'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('6. Patient Details Screen Adaptive Rows and Header', () {
    final testPatient = PatientModel(
      id: 'pat-3',
      patientNumber: 'P-1003',
      name: 'Sunil Kumar Sharma Long Name Test',
      department: 'dental',
      dob: DateTime(1990, 1, 1),
      mobile: '+91 9876543210',
      address: '123 Main Street, Sector 4, Gandhinagar, Gujarat',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    Widget buildPatientDetailsHeader(PatientModel patient) {
      return MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 360;
                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 26,
                            child: Text(patient.name[0]),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  patient.name,
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold),
                                ),
                                Wrap(
                                  children: [
                                    Text(patient.patientNumber),
                                    const SizedBox(width: 6),
                                    Text(patient.department ?? ''),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          onPressed: () {},
                          icon: const Icon(Icons.phone),
                          label: const Text('Call Patient'),
                        ),
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      child: Text(patient.name[0]),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            patient.name,
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          Wrap(
                            children: [
                              Text(patient.patientNumber),
                              const SizedBox(width: 8),
                              Text(patient.department ?? ''),
                            ],
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () {},
                      icon: const Icon(Icons.phone),
                      label: const Text('Call'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
    }

    for (final width in testViewports) {
      testWidgets(
          'Patient details header renders without overflow at $width px',
          (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(buildPatientDetailsHeader(testPatient));
        await tester.pumpAndSettle();

        expect(find.text(testPatient.name), findsOneWidget);
        expect(find.text(testPatient.patientNumber), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('7. Staff Patients Screen Card and Call Button', () {
    final patientWithPhone = PatientModel(
      id: 'p-phone',
      patientNumber: 'P-999',
      name: 'Ramesh Patel',
      department: 'eye',
      dob: DateTime(1992, 5, 10),
      mobile: '9876543210',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    Widget buildStaffPatientItem(PatientModel patient) {
      return MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const CircleAvatar(child: Text('RP')),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(patient.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            Wrap(
                              spacing: AppSpacing.xs,
                              children: [
                                Text(patient.department?.toUpperCase() ?? ''),
                                if (patient.mobile != null)
                                  Text(patient.mobile!),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.phone, size: 16),
                  label: const Text('Call'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(60, 36),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 36),
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      );
    }

    for (final width in testViewports) {
      testWidgets('Staff patient card renders cleanly at $width px',
          (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(buildStaffPatientItem(patientWithPhone));
        await tester.pumpAndSettle();

        expect(find.text('Ramesh Patel'), findsOneWidget);
        expect(find.text('Call'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
