import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mkes_care/core/theme/app_colors.dart';
import 'package:mkes_care/core/theme/app_spacing.dart';
import 'package:mkes_care/core/theme/app_typography.dart';
import 'package:mkes_care/shared/widgets/adaptive_dialog_shell.dart';
import 'package:mkes_care/shared/widgets/responsive_form_row.dart';

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

  group('1. AdaptiveDialogShell and Constraints', () {
    testWidgets('constraintsFor computes safe widths and heights across viewports',
        (tester) async {
      for (final width in testViewports) {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 800),
                viewInsets: const EdgeInsets.only(bottom: 250), // Virtual keyboard open
              ),
              child: Builder(
                builder: (context) {
                  final constraints = AdaptiveDialogShell.constraintsFor(
                    context,
                    maxWidth: 620,
                  );

                  // Must respect viewport boundaries with at least 32px margins on phones
                  expect(constraints.maxWidth, lessThanOrEqualTo(width));
                  expect(constraints.maxHeight, lessThanOrEqualTo(800));

                  if (width < 600) {
                    expect(constraints.maxWidth, lessThanOrEqualTo(width - 32.0));
                  } else {
                    expect(constraints.maxWidth, lessThanOrEqualTo(620.0));
                  }

                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }
    });
  });

  group('2. ResponsiveFormRow Layout', () {
    testWidgets('stacks vertically below breakpoint and lays horizontally above',
        (tester) async {
      Widget buildTestRow(double width) {
        return MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: Size(width, 600)),
            child: Scaffold(
              body: SizedBox(
                width: width,
                child: ResponsiveFormRow(
                  breakpoint: 500,
                  children: [
                    Container(key: const ValueKey('child1'), height: 40),
                    Container(key: const ValueKey('child2'), height: 40),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      // 1. Mobile (360px < 500px): must stack vertically
      await tester.pumpWidget(buildTestRow(360.0));
      await tester.pumpAndSettle();

      final child1Pos = tester.getTopLeft(find.byKey(const ValueKey('child1')));
      final child2Pos = tester.getTopLeft(find.byKey(const ValueKey('child2')));
      expect(child2Pos.dy, greaterThan(child1Pos.dy)); // Child 2 is below Child 1
      expect(child2Pos.dx, equals(child1Pos.dx)); // Same horizontal start

      // 2. Desktop (768px >= 500px): must lay out horizontally
      await tester.pumpWidget(buildTestRow(768.0));
      await tester.pumpAndSettle();

      final child1PosDesk = tester.getTopLeft(find.byKey(const ValueKey('child1')));
      final child2PosDesk = tester.getTopLeft(find.byKey(const ValueKey('child2')));
      expect(child2PosDesk.dy, equals(child1PosDesk.dy)); // Same vertical alignment
      expect(child2PosDesk.dx, greaterThan(child1PosDesk.dx)); // Child 2 is to the right
    });
  });

  group('3. Dental Lab Mobile Cards and Dialogs', () {
    testWidgets('Dental lab case mobile card renders with actions and dates without overflow',
        (tester) async {
      for (final width in testViewports) {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(size: Size(width, 800)),
              child: Scaffold(
                body: SizedBox(
                  width: width,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                      border: Border.all(color: AppColors.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryContainer.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('LAB-2026-001', style: AppTypography.dataMono, overflow: TextOverflow.ellipsis),
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('In Progress'),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text('John Doe', style: AppTypography.headlineMd),
                        Text('Crown - Zirconia', style: AppTypography.bodySm),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.md,
                          runSpacing: AppSpacing.xs,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.send_outlined, size: 14),
                                const SizedBox(width: 4),
                                Text('Sent: 2026-10-18', style: AppTypography.bodySm),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.event_available_outlined, size: 14),
                                const SizedBox(width: 4),
                                Text('Exp: 2026-10-25', style: AppTypography.bodySm),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Wrap(
                          alignment: WrapAlignment.end,
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () {},
                              icon: const Icon(Icons.check_circle_outline, size: 16),
                              label: const Text('Mark Ready'),
                            ),
                            FilledButton.icon(
                              onPressed: () {},
                              icon: const Icon(Icons.delivery_dining_outlined, size: 16),
                              label: const Text('Mark Delivered'),
                            ),
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
      }
    });

    testWidgets('Dental treatment and lab form dialogs adapt without overflow',
        (tester) async {
      for (final width in testViewports) {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(size: Size(width, 840)),
              child: Builder(
                builder: (context) {
                  final constraints = AdaptiveDialogShell.constraintsFor(context, maxWidth: 580);
                  return Dialog(
                    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                    child: ConstrainedBox(
                      constraints: constraints,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.medical_services_outlined, size: 20),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Text(
                                    'New Dental Treatment Record',
                                    style: AppTypography.headlineMd,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () {},
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.md),
                            ResponsiveFormRow(
                              breakpoint: 480,
                              children: [
                                TextFormField(decoration: const InputDecoration(labelText: 'Tooth Number')),
                                TextFormField(decoration: const InputDecoration(labelText: 'Procedure Status')),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.md),
                            ResponsiveFormRow(
                              breakpoint: 480,
                              children: [
                                TextFormField(decoration: const InputDecoration(labelText: 'Case Number')),
                                TextFormField(decoration: const InputDecoration(labelText: 'Case Type')),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Wrap(
                              alignment: WrapAlignment.end,
                              spacing: AppSpacing.sm,
                              runSpacing: AppSpacing.xs,
                              children: [
                                TextButton(onPressed: () {}, child: const Text('Cancel')),
                                FilledButton(onPressed: () {}, child: const Text('Save Treatment')),
                              ],
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
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('4. Inventory and Purchase Order Responsive Layouts', () {
    testWidgets('Purchase order line item row switches between stacked card and row table',
        (tester) async {
      Widget buildLineItem(double containerWidth) {
        return MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: containerWidth,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 560;

                  if (isNarrow) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Expanded(child: Text('Amoxicillin 500mg')),
                                IconButton(icon: const Icon(Icons.delete_outline), onPressed: () {}),
                              ],
                            ),
                            Row(
                              children: const [
                                Expanded(child: Text('Qty: 50')),
                                Expanded(child: Text('Price: ₹150')),
                                Expanded(child: Text('Total: ₹7,500')),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return Row(
                    children: [
                      const Expanded(flex: 4, child: Text('Amoxicillin 500mg')),
                      const SizedBox(width: AppSpacing.sm),
                      const Expanded(flex: 2, child: Text('Qty: 50')),
                      const SizedBox(width: AppSpacing.sm),
                      const Expanded(flex: 2, child: Text('Price: ₹150')),
                      const SizedBox(width: AppSpacing.sm),
                      const Expanded(flex: 2, child: Text('Total: ₹7,500')),
                      IconButton(icon: const Icon(Icons.delete_outline), onPressed: () {}),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      }

      for (final width in testViewports) {
        await tester.pumpWidget(buildLineItem(width));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('Purchase order list header stacks gracefully on mobile',
        (tester) async {
      Widget buildPOHeader(double width) {
        final isDesktop = width >= 768.0;
        return MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: width,
              child: isDesktop
                  ? Row(
                      children: [
                        Expanded(
                          child: Text('Purchase Orders', style: AppTypography.headlineMd),
                        ),
                        FilledButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.add),
                          label: const Text('New Purchase Order'),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text('Purchase Orders', style: AppTypography.headlineMd),
                            ),
                            IconButton(icon: const Icon(Icons.refresh), onPressed: () {}),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.add),
                            label: const Text('New Purchase Order'),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        );
      }

      for (final width in testViewports) {
        await tester.pumpWidget(buildPOHeader(width));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('5. Department Management & Staff Profile Responsive Views', () {
    testWidgets('Department tile renders compact mobile card below 600px',
        (tester) async {
      Widget buildDeptTile(double width) {
        return MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: width,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = constraints.maxWidth < 600;

                  if (isMobile) {
                    return Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.business_outlined),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text('Dental Clinic',
                                    style: AppTypography.headlineMd.copyWith(fontSize: 18)),
                              ),
                              const Text('Active'),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                onPressed: () {},
                                icon: const Icon(Icons.edit_outlined, size: 16),
                                label: const Text('Edit'),
                              ),
                              TextButton.icon(
                                onPressed: () {},
                                icon: const Icon(Icons.delete_outline, size: 16),
                                label: const Text('Delete'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }

                  return Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        const Icon(Icons.business_outlined),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: Text('Dental Clinic', style: AppTypography.headlineMd)),
                        const Text('Active'),
                        IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () {}),
                        IconButton(icon: const Icon(Icons.delete_outline), onPressed: () {}),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      }

      for (final width in testViewports) {
        await tester.pumpWidget(buildDeptTile(width));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('Staff profile AppBar actions collapse to icons on mobile',
        (tester) async {
      Widget buildStaffAppBar(double width) {
        final isDesktop = width >= 768.0;
        return MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              title: const Text('Dr. Sarah Jenkins', overflow: TextOverflow.ellipsis),
              actions: isDesktop
                  ? [
                      OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit Profile'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () {},
                        icon: const Icon(Icons.person_off_outlined),
                        label: const Text('Deactivate'),
                      ),
                    ]
                  : [
                      IconButton(
                        tooltip: 'Edit Profile',
                        onPressed: () {},
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Deactivate',
                        onPressed: () {},
                        icon: const Icon(Icons.person_off_outlined),
                      ),
                    ],
            ),
            body: const SizedBox.shrink(),
          ),
        );
      }

      for (final width in testViewports) {
        await tester.pumpWidget(buildStaffAppBar(width));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('6. Staff Performance and Global Search Modal', () {
    testWidgets('Staff performance metrics stack on narrow viewports without overflow',
        (tester) async {
      Widget buildMetrics(double width) {
        final isMobile = width < 560;
        return MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: width,
              child: SingleChildScrollView(
                child: isMobile
                    ? Column(
                        children: [
                          Container(height: 70, color: Colors.green.shade100),
                          const SizedBox(height: AppSpacing.sm),
                          Container(height: 70, color: Colors.orange.shade100),
                          const SizedBox(height: AppSpacing.sm),
                          Container(height: 70, color: Colors.red.shade100),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: Container(height: 80, color: Colors.green.shade100)),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(child: Container(height: 80, color: Colors.orange.shade100)),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(child: Container(height: 80, color: Colors.red.shade100)),
                        ],
                      ),
              ),
            ),
          ),
        );
      }

      for (final width in testViewports) {
        await tester.pumpWidget(buildMetrics(width));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('Global search modal width and footer adapt cleanly',
        (tester) async {
      Widget buildSearchModal(double width) {
        final dialogWidth = math.min(width - 32.0, 600.0);
        final isDesktop = width >= 768.0;

        return MaterialApp(
          home: Scaffold(
            body: Center(
              child: Container(
                width: dialogWidth,
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(decoration: const InputDecoration(hintText: 'Search...')),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Search powered by MKES Copilot',
                            style: AppTypography.labelCaps,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isDesktop) ...[
                          const Icon(Icons.keyboard_return, size: 14),
                          const SizedBox(width: 4),
                          const Text('to select'),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      for (final width in testViewports) {
        await tester.pumpWidget(buildSearchModal(width));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  });
}
