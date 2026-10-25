import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mkes_care/core/theme/app_colors.dart';
import 'package:mkes_care/core/theme/app_spacing.dart';
import 'package:mkes_care/core/theme/app_typography.dart';
import 'package:mkes_care/shared/widgets/responsive_form_row.dart';
import 'package:mkes_care/shared/widgets/adaptive_dialog_shell.dart';
import 'package:mkes_care/features/billing/models/billing_invoice_model.dart';
import 'package:mkes_care/features/billing/models/billing_item_model.dart';
import 'package:mkes_care/features/billing/models/billing_service_model.dart';
import 'package:mkes_care/features/billing/providers/billing_provider.dart';
import 'package:mkes_care/features/billing/widgets/invoice_line_items_editor.dart';
import 'package:mkes_care/features/billing/widgets/invoice_payment_section.dart';
import 'package:mkes_care/features/billing/widgets/invoice_success_dialog.dart';
import 'package:mkes_care/features/billing/widgets/record_payment_dialog.dart';

class _FakeRecordPaymentNotifier extends StateNotifier<RecordPaymentState>
    implements RecordPaymentNotifier {
  _FakeRecordPaymentNotifier() : super(const RecordPaymentState());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

  group('1. Appointment Form Dialog Responsive Layout', () {
    Widget buildAppointmentDialogStructure({
      required double screenWidth,
      required double screenHeight,
    }) {
      return MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(screenWidth, screenHeight),
          ),
          child: Scaffold(
            body: Builder(
              builder: (context) {
                final dialogConstraints =
                    AdaptiveDialogConstraints.getConstraints(
                  context: context,
                  maxPhoneWidth: 420.0,
                  maxTabletWidth: 540.0,
                  maxDesktopWidth: 580.0,
                  minWidth: 280.0,
                  minHeight: 320.0,
                );

                return Center(
                  child: Dialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                    ),
                    insetPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 24),
                    child: ConstrainedBox(
                      constraints: dialogConstraints,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Responsive Header
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      const Icon(Icons.calendar_month,
                                          size: 20),
                                      const SizedBox(width: AppSpacing.sm),
                                      Flexible(
                                        child: Text(
                                          'New Appointment',
                                          style: AppTypography.headlineMd,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.close, size: 20),
                              ],
                            ),
                          ),
                          // Responsive Form Row for Department and Type
                          Flexible(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ResponsiveFormRow(
                                    breakpoint: 440,
                                    children: [
                                      DropdownButtonFormField<String>(
                                        initialValue: 'eye',
                                        isExpanded: true,
                                        decoration: const InputDecoration(
                                            labelText: 'Department *'),
                                        items: const [
                                          DropdownMenuItem(
                                              value: 'eye',
                                              child: Text('Eye Clinic')),
                                          DropdownMenuItem(
                                              value: 'dental',
                                              child: Text('Dental Clinic')),
                                        ],
                                        onChanged: (_) {},
                                      ),
                                      DropdownButtonFormField<String>(
                                        initialValue: 'regular',
                                        isExpanded: true,
                                        decoration: const InputDecoration(
                                            labelText: 'Type *'),
                                        items: const [
                                          DropdownMenuItem(
                                              value: 'regular',
                                              child: Text('Regular Visit')),
                                          DropdownMenuItem(
                                              value: 'walk_in',
                                              child: Text('Walk-in')),
                                        ],
                                        onChanged: (_) {},
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  // Responsive Form Row for Date & Time
                                  ResponsiveFormRow(
                                    breakpoint: 440,
                                    children: [
                                      InputDecorator(
                                        decoration: const InputDecoration(
                                            labelText: 'Date *'),
                                        child: const Text('18/10/2026'),
                                      ),
                                      InputDecorator(
                                        decoration: const InputDecoration(
                                            labelText: 'Time Slot *'),
                                        child: const Text('09:00 AM'),
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
              },
            ),
          ),
        ),
      );
    }

    for (final width in testViewports) {
      testWidgets('renders cleanly without overflow at $width px',
          (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          buildAppointmentDialogStructure(
            screenWidth: width,
            screenHeight: 800,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('New Appointment'), findsOneWidget);
        expect(find.text('Department *'), findsOneWidget);
        expect(find.text('Type *'), findsOneWidget);
        expect(find.text('Date *'), findsOneWidget);
        expect(find.text('Time Slot *'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('stacks fields vertically on 360 px narrow screen',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildAppointmentDialogStructure(
          screenWidth: 360,
          screenHeight: 800,
        ),
      );
      await tester.pumpAndSettle();

      final deptPos = tester.getTopLeft(find.text('Department *'));
      final typePos = tester.getTopLeft(find.text('Type *'));
      // Stacking check: Type should be below Department
      expect(typePos.dy, greaterThan(deptPos.dy));
    });

    testWidgets('places fields side by side on 1024 px desktop',
        (tester) async {
      tester.view.physicalSize = const Size(1024, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildAppointmentDialogStructure(
          screenWidth: 1024,
          screenHeight: 800,
        ),
      );
      await tester.pumpAndSettle();

      final deptPos = tester.getTopLeft(find.text('Department *'));
      final typePos = tester.getTopLeft(find.text('Type *'));
      // Side by side check: Type should be at the same vertical level as Department
      expect((typePos.dy - deptPos.dy).abs(), lessThan(4.0));
    });
  });

  group('2. Task Form Dialog Responsive Layout', () {
    Widget buildTaskDialog({
      required double screenWidth,
      required bool isEditing,
    }) {
      return MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: Size(screenWidth, 800)),
          child: Scaffold(
            body: Builder(
              builder: (context) {
                final dialogConstraints =
                    AdaptiveDialogConstraints.getConstraints(
                  context: context,
                  maxPhoneWidth: 420.0,
                  maxTabletWidth: 500.0,
                  maxDesktopWidth: 500.0,
                );

                return AlertDialog(
                  actionsOverflowButtonSpacing: AppSpacing.xs,
                  title: Row(
                    children: [
                      Icon(isEditing ? Icons.edit_note : Icons.add_task,
                          color: AppColors.primary),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          isEditing ? 'Edit Task' : 'Create & Assign Task',
                          style:
                              AppTypography.headlineMd.copyWith(fontSize: 20),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  content: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: dialogConstraints.maxWidth,
                      maxHeight: dialogConstraints.maxHeight,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextFormField(
                            initialValue: 'Test task',
                            decoration: const InputDecoration(
                                labelText: 'Task Title *'),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          if (isEditing)
                            if (dialogConstraints.maxWidth < 420)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  DropdownButtonFormField<String>(
                                    initialValue: 'medium',
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                        labelText: 'Priority'),
                                    items: const [
                                      DropdownMenuItem(
                                          value: 'medium',
                                          child: Text('Medium')),
                                    ],
                                    onChanged: (_) {},
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  DropdownButtonFormField<String>(
                                    initialValue: 'pending',
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                        labelText: 'Status'),
                                    items: const [
                                      DropdownMenuItem(
                                          value: 'pending',
                                          child: Text('Pending')),
                                    ],
                                    onChanged: (_) {},
                                  ),
                                ],
                              )
                            else
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      initialValue: 'medium',
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                          labelText: 'Priority'),
                                      items: const [
                                        DropdownMenuItem(
                                            value: 'medium',
                                            child: Text('Medium')),
                                      ],
                                      onChanged: (_) {},
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.md),
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      initialValue: 'pending',
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                          labelText: 'Status'),
                                      items: const [
                                        DropdownMenuItem(
                                            value: 'pending',
                                            child: Text('Pending')),
                                      ],
                                      onChanged: (_) {},
                                    ),
                                  ),
                                ],
                              )
                          else
                            DropdownButtonFormField<String>(
                              initialValue: 'medium',
                              isExpanded: true,
                              decoration:
                                  const InputDecoration(labelText: 'Priority'),
                              items: const [
                                DropdownMenuItem(
                                    value: 'medium', child: Text('Medium')),
                              ],
                              onChanged: (_) {},
                            ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(onPressed: () {}, child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () {},
                        child:
                            Text(isEditing ? 'Save Changes' : 'Assign Task')),
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
          'renders cleanly without overflow at $width px (editing: true)',
          (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          buildTaskDialog(screenWidth: width, isEditing: true),
        );
        await tester.pumpAndSettle();

        expect(find.text('Edit Task'), findsOneWidget);
        expect(find.text('Priority'), findsOneWidget);
        expect(find.text('Status'), findsOneWidget);
        expect(find.text('Save Changes'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('priority and status stack on 360 px phone when editing',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildTaskDialog(screenWidth: 360, isEditing: true),
      );
      await tester.pumpAndSettle();

      final priorityPos = tester.getTopLeft(find.text('Priority'));
      final statusPos = tester.getTopLeft(find.text('Status'));
      expect(statusPos.dy, greaterThan(priorityPos.dy));
    });
  });

  group('3. Invoice Line Items Editor Responsive Layout', () {
    const dummyServices = [
      BillingServiceModel(
        id: 'serv_1',
        name: 'Comprehensive Eye Examination',
        department: 'eye',
        price: 500.0,
      ),
      BillingServiceModel(
        id: 'serv_2',
        name: 'Tonometry & Glaucoma Check',
        department: 'eye',
        price: 350.0,
      ),
    ];

    final dummyItems = [
      const BillingItemModel(
        serviceId: 'serv_1',
        serviceName: 'Comprehensive Eye Examination',
        isCustom: false,
        quantity: 2,
        unitPrice: 500.0,
      ),
      const BillingItemModel(
        serviceName: 'Special Staining Procedure',
        isCustom: true,
        quantity: 1,
        unitPrice: 1200.0,
      ),
    ];

    Widget buildLineItemsEditor(double screenWidth) {
      return MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: Size(screenWidth, 800)),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ProviderScope(
                overrides: [
                  departmentBillingServicesProvider('eye').overrideWith(
                    (ref) => Future.value(dummyServices),
                  ),
                ],
                child: InvoiceLineItemsEditor(
                  department: 'eye',
                  items: dummyItems,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
    }

    for (final width in testViewports) {
      testWidgets('renders cleanly without overflow at $width px',
          (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(buildLineItemsEditor(width));
        await tester.pumpAndSettle();

        expect(find.text('Services & Line Items'), findsOneWidget);
        expect(find.text('Add Service'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('delete button has comfortable touch target >= 44 px',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildLineItemsEditor(360));
      await tester.pumpAndSettle();

      final deleteButtons =
          find.widgetWithIcon(IconButton, Icons.delete_outline);
      expect(deleteButtons, findsNWidgets(2));

      for (final btn in deleteButtons.evaluate()) {
        final box = btn.renderObject as RenderBox;
        expect(box.size.width, greaterThanOrEqualTo(44.0));
        expect(box.size.height, greaterThanOrEqualTo(44.0));
      }
    });
  });

  group('4. Create Invoice Screen Responsive Elements', () {
    Widget buildDepartmentSelector(double width) {
      return MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 800)),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 560;

                  final segmentedButton = SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'eye',
                        label: isNarrow
                            ? const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('Eye (Opthalmology)'),
                              )
                            : const Text('Eye Department (Opthalmology)'),
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                      ),
                      ButtonSegment(
                        value: 'dental',
                        label: isNarrow
                            ? const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('Dental'),
                              )
                            : const Text('Dental Department'),
                        icon: const Icon(Icons.medical_services_outlined,
                            size: 18),
                      ),
                    ],
                    selected: const {'eye'},
                    onSelectionChanged: (_) {},
                  );

                  if (isNarrow) {
                    return Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Department:',
                            style: AppTypography.bodyMd.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.onSurface,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          segmentedButton,
                        ],
                      ),
                    );
                  }

                  return Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        Text(
                          'Department:',
                          style: AppTypography.bodyMd.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.onSurface,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: segmentedButton),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
    }

    for (final width in testViewports) {
      testWidgets(
          'department selector renders cleanly without overflow at $width px',
          (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(buildDepartmentSelector(width));
        await tester.pumpAndSettle();

        expect(find.text('Department:'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('action buttons stack on mobile and sit in row on desktop',
        (tester) async {
      Widget buildActionButtons(double width) {
        return MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: Size(width, 800)),
            child: Scaffold(
              body: LayoutBuilder(
                builder: (context, actionConstraints) {
                  final isNarrow = actionConstraints.maxWidth < 480;

                  if (isNarrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.receipt_outlined, size: 18),
                          label: const Text('Create Invoice (₹1,500.00)'),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        OutlinedButton(
                          onPressed: () {},
                          child: const Text('Cancel'),
                        ),
                      ],
                    );
                  }

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () {},
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      FilledButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.receipt_outlined, size: 18),
                        label: const Text('Create Invoice (₹1,500.00)'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      }

      // Test mobile 360 px
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(buildActionButtons(360));
      await tester.pumpAndSettle();

      final createPos360 =
          tester.getTopLeft(find.text('Create Invoice (₹1,500.00)'));
      final cancelPos360 = tester.getTopLeft(find.text('Cancel'));
      expect(cancelPos360.dy, greaterThan(createPos360.dy));

      // Test desktop 1024 px
      tester.view.physicalSize = const Size(1024, 800);
      await tester.pumpWidget(buildActionButtons(1024));
      await tester.pumpAndSettle();

      final createPos1024 =
          tester.getTopLeft(find.text('Create Invoice (₹1,500.00)'));
      final cancelPos1024 = tester.getTopLeft(find.text('Cancel'));
      expect((cancelPos1024.dy - createPos1024.dy).abs(), lessThan(8.0));
      expect(createPos1024.dx, greaterThan(cancelPos1024.dx));

      tester.view.resetPhysicalSize();
    });
  });

  group('5. Invoice Payment Section Responsive Layout', () {
    Widget buildPaymentSection(double width) {
      return MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 800)),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: InvoicePaymentSection(
                subtotal: 2500.0,
                discount: 200.0,
                finalTotal: 2300.0,
                newCharges: 2500.0,
                previousBalanceIncluded: 0.0,
                onDiscountChanged: (_) {},
                payment: null,
                onPaymentChanged: (_) {},
              ),
            ),
          ),
        ),
      );
    }

    for (final width in testViewports) {
      testWidgets('renders cleanly without overflow at $width px',
          (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(buildPaymentSection(width));
        await tester.pumpAndSettle();

        expect(find.text('Financial Summary & Payment'), findsOneWidget);
        expect(find.text('Subtotal'), findsOneWidget);
        expect(find.text('Payable Total'), findsOneWidget);
        expect(find.text('Payment Mode'), findsOneWidget);
        expect(find.text('Cash'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('6. Invoice Success Dialog Responsive Layout', () {
    final sampleInvoice = BillingInvoiceModel(
      id: 'inv_123',
      invoiceNumber: 'MKES/EYE/2026/0014',
      patientId: 'pat_001',
      patientName: 'Shri Rameshwar Patel',
      department: 'eye',
      subtotal: 1500.0,
      discount: 100.0,
      totalAmount: 1400.0,
      amountPaid: 1400.0,
      paymentStatus: 'paid',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      items: const [
        BillingItemModel(
          serviceName: 'Comprehensive Eye Examination',
          quantity: 1,
          unitPrice: 1500.0,
        ),
      ],
    );

    for (final width in testViewports) {
      testWidgets('renders cleanly without overflow at $width px',
          (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(size: Size(width, 800)),
              child: Scaffold(
                body: InvoiceSuccessDialog(
                  invoice: sampleInvoice,
                  onCreateAnother: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Invoice Created'), findsOneWidget);
        expect(find.text('MKES/EYE/2026/0014'), findsOneWidget);
        expect(find.text('Shri Rameshwar Patel'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('7. Record Payment Dialog Responsive Layout', () {
    final sampleInvoiceDue = BillingInvoiceModel(
      id: 'inv_999',
      invoiceNumber: 'MKES/DEN/2026/0088',
      patientId: 'pat_002',
      patientName: 'Sunita Sharma',
      department: 'dental',
      subtotal: 3000.0,
      discount: 0.0,
      totalAmount: 3000.0,
      amountPaid: 1000.0,
      paymentStatus: 'partially_paid',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    for (final width in testViewports) {
      testWidgets('renders cleanly without overflow at $width px',
          (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(size: Size(width, 800)),
              child: Scaffold(
                body: ProviderScope(
                  overrides: [
                    recordPaymentNotifierProvider.overrideWith(
                      (ref) => _FakeRecordPaymentNotifier(),
                    ),
                  ],
                  child: RecordPaymentDialog(
                    invoice: sampleInvoiceDue,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('RECORD PAYMENT'), findsOneWidget);
        expect(find.text('MKES/DEN/2026/0088'), findsOneWidget);
        expect(find.text('Payment Mode *'), findsOneWidget);
        expect(find.text('Record Payment'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
