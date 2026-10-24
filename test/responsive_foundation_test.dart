import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mkes_care/core/utils/responsive_layout.dart';
import 'package:mkes_care/shared/widgets/adaptive_dialog_shell.dart';
import 'package:mkes_care/shared/widgets/mkes_primary_button.dart';
import 'package:mkes_care/shared/widgets/mkes_secondary_button.dart';
import 'package:mkes_care/shared/widgets/responsive_form_row.dart';
import 'package:mkes_care/shared/widgets/responsive_page_header.dart';

Widget _buildTestApp(Widget child,
    {Size? surfaceSize, EdgeInsets? viewInsets}) {
  final size = surfaceSize ?? const Size(800, 600);
  final insets = viewInsets ?? EdgeInsets.zero;
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: size,
        viewInsets: insets,
      ),
      child: Material(
        child: child,
      ),
    ),
  );
}

void main() {
  group('1. AppBreakpoints & ResponsiveLayout Utilities', () {
    testWidgets(
        'ResponsiveLayout correctly identifies viewports across all 6 target widths',
        (tester) async {
      final widths = <double, ({bool isPhone, bool isCompact, bool isDesktop})>{
        360.0: (isPhone: true, isCompact: true, isDesktop: false),
        390.0: (isPhone: true, isCompact: true, isDesktop: false),
        430.0: (isPhone: true, isCompact: true, isDesktop: false),
        768.0: (isPhone: false, isCompact: false, isDesktop: false),
        1024.0: (isPhone: false, isCompact: false, isDesktop: true),
        1440.0: (isPhone: false, isCompact: false, isDesktop: true),
      };

      for (final entry in widths.entries) {
        final width = entry.key;
        final expected = entry.value;

        await tester.pumpWidget(
          _buildTestApp(
            Builder(
              builder: (context) {
                expect(
                  ResponsiveLayout.isPhone(context),
                  expected.isPhone,
                  reason: 'Failed isPhone for width $width',
                );
                expect(
                  ResponsiveLayout.isCompact(context),
                  expected.isCompact,
                  reason: 'Failed isCompact for width $width',
                );
                expect(
                  ResponsiveLayout.isDesktop(context),
                  expected.isDesktop,
                  reason: 'Failed isDesktop for width $width',
                );
                return const Text('ok');
              },
            ),
            surfaceSize: Size(width, 800),
          ),
        );
      }
    });

    test('ResponsiveLayout width-based methods work without BuildContext', () {
      expect(ResponsiveLayout.isPhoneWidth(360), isTrue);
      expect(ResponsiveLayout.isPhoneWidth(599), isTrue);
      expect(ResponsiveLayout.isPhoneWidth(600), isFalse);

      expect(ResponsiveLayout.isCompactWidth(767), isTrue);
      expect(ResponsiveLayout.isCompactWidth(768), isFalse);

      expect(ResponsiveLayout.isTabletWidth(768), isTrue);
      expect(ResponsiveLayout.isTabletWidth(1023), isTrue);
      expect(ResponsiveLayout.isTabletWidth(1024), isFalse);

      expect(ResponsiveLayout.isDesktopWidth(1024), isTrue);
      expect(ResponsiveLayout.isDesktopWidth(1440), isTrue);

      expect(ResponsiveLayout.shouldStack(480), isTrue);
      expect(ResponsiveLayout.shouldStack(500), isFalse);
    });

    testWidgets('ResponsiveLayout.value selects correct value per tier',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          Builder(
            builder: (context) {
              final tier = ResponsiveLayout.value<String>(
                context: context,
                phone: 'mobile_tier',
                tablet: 'tablet_tier',
                desktop: 'desktop_tier',
              );
              return Text(tier);
            },
          ),
          surfaceSize: const Size(360, 600),
        ),
      );
      expect(find.text('mobile_tier'), findsOneWidget);

      await tester.pumpWidget(
        _buildTestApp(
          Builder(
            builder: (context) {
              final tier = ResponsiveLayout.value<String>(
                context: context,
                phone: 'mobile_tier',
                tablet: 'tablet_tier',
                desktop: 'desktop_tier',
              );
              return Text(tier);
            },
          ),
          surfaceSize: const Size(800, 600),
        ),
      );
      expect(find.text('tablet_tier'), findsOneWidget);

      await tester.pumpWidget(
        _buildTestApp(
          Builder(
            builder: (context) {
              final tier = ResponsiveLayout.value<String>(
                context: context,
                phone: 'mobile_tier',
                tablet: 'tablet_tier',
                desktop: 'desktop_tier',
              );
              return Text(tier);
            },
          ),
          surfaceSize: const Size(1200, 600),
        ),
      );
      expect(find.text('desktop_tier'), findsOneWidget);
    });
  });

  group('2. MkesPrimaryButton & MkesSecondaryButton', () {
    testWidgets('MkesPrimaryButton defaults to full width and fires callback',
        (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        _buildTestApp(
          Center(
            child: SizedBox(
              width: 300,
              child: MkesPrimaryButton(
                label: 'Save Patient',
                icon: Icons.check,
                onPressed: () => tapped = true,
              ),
            ),
          ),
          surfaceSize: const Size(400, 600),
        ),
      );

      expect(find.text('Save Patient'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);

      final buttonFinder = find.byType(FilledButton);
      final size = tester.getSize(buttonFinder);
      expect(size.width, equals(300));
      expect(
          size.height, greaterThanOrEqualTo(48.0)); // Touch target verification

      await tester.tap(buttonFinder);
      expect(tapped, isTrue);
    });

    testWidgets(
        'MkesPrimaryButton inside an unconstrained Row with isFullWidth=false does not crash',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          const Row(
            children: [
              MkesPrimaryButton(
                label: 'Action 1',
                isFullWidth: false,
              ),
              MkesPrimaryButton(
                label: 'Action 2',
                isFullWidth: false,
              ),
            ],
          ),
          surfaceSize: const Size(360, 600),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Action 1'), findsOneWidget);
      expect(find.text('Action 2'), findsOneWidget);
    });

    testWidgets(
        'MkesSecondaryButton inside an unconstrained Row with isFullWidth=false renders cleanly',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          const Row(
            children: [
              MkesSecondaryButton(
                label: 'Cancel',
                isFullWidth: false,
              ),
            ],
          ),
          surfaceSize: const Size(360, 600),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Cancel'), findsOneWidget);
      final size = tester.getSize(find.byType(OutlinedButton));
      expect(size.height, greaterThanOrEqualTo(48.0));
    });

    testWidgets(
        'Buttons with isLoading=true show progress indicator and disable tap',
        (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        _buildTestApp(
          MkesPrimaryButton(
            label: 'Submitting',
            isLoading: true,
            onPressed: () => tapped = true,
          ),
          surfaceSize: const Size(400, 600),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Submitting'), findsNothing);

      await tester.tap(find.byType(FilledButton));
      expect(tapped, isFalse);
    });
  });

  group('3. AdaptiveDialogConstraints & AdaptiveDialogShell', () {
    testWidgets(
        'AdaptiveDialogConstraints clamps dialog to available width on 360px phone',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          Builder(
            builder: (context) {
              final constraints = AdaptiveDialogConstraints.getConstraints(
                context: context,
              );
              // On a 360px phone, max available width with 16px margins on both sides is 328px
              expect(constraints.maxWidth, lessThanOrEqualTo(328.0));
              return const SizedBox.shrink();
            },
          ),
          surfaceSize: const Size(360, 740),
        ),
      );
    });

    testWidgets(
        'AdaptiveDialogConstraints handles virtual keyboard insets safely',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          Builder(
            builder: (context) {
              final constraints = AdaptiveDialogConstraints.getConstraints(
                context: context,
              );
              // Screen height 800 - keyboard 300 - padding 48 = 452
              expect(constraints.maxHeight, lessThanOrEqualTo(460.0));
              return const SizedBox.shrink();
            },
          ),
          surfaceSize: const Size(390, 800),
          viewInsets: const EdgeInsets.only(bottom: 300),
        ),
      );
    });

    testWidgets(
        'AdaptiveDialogShell renders title, content, close button and actions',
        (tester) async {
      bool closed = false;
      bool submitted = false;

      await tester.pumpWidget(
        _buildTestApp(
          AdaptiveDialogShell(
            title: 'Schedule Appointment',
            subtitle: 'Enter patient and doctor details',
            icon: Icons.calendar_today,
            onClose: () => closed = true,
            content: const Column(
              children: [
                Text('Dialog Content Line 1'),
                Text('Dialog Content Line 2'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => submitted = true,
                child: const Text('Confirm'),
              ),
            ],
          ),
          surfaceSize: const Size(360, 740),
        ),
      );

      expect(find.text('Schedule Appointment'), findsOneWidget);
      expect(find.text('Enter patient and doctor details'), findsOneWidget);
      expect(find.text('Dialog Content Line 1'), findsOneWidget);
      expect(find.text('Confirm'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      expect(closed, isTrue);

      await tester.tap(find.text('Confirm'));
      expect(submitted, isTrue);
    });
  });

  group('4. ResponsiveFormRow', () {
    testWidgets('Stacks vertically into a Column when width < 500px',
        (tester) async {
      final ctrl1 = TextEditingController(text: 'John');
      final ctrl2 = TextEditingController(text: 'Doe');

      await tester.pumpWidget(
        _buildTestApp(
          Center(
            child: SizedBox(
              width: 360,
              child: ResponsiveFormRow(
                children: [
                  TextField(key: const Key('field1'), controller: ctrl1),
                  TextField(key: const Key('field2'), controller: ctrl2),
                ],
              ),
            ),
          ),
          surfaceSize: const Size(360, 600),
        ),
      );

      final pos1 = tester.getTopLeft(find.byKey(const Key('field1')));
      final pos2 = tester.getTopLeft(find.byKey(const Key('field2')));

      // In stacked mode, field2 is strictly below field1
      expect(pos2.dy, greaterThan(pos1.dy));
      expect(pos2.dx, equals(pos1.dx));
      expect(ctrl1.text, equals('John'));
      expect(ctrl2.text, equals('Doe'));
    });

    testWidgets(
        'Lays out horizontally side-by-side in a Row when width >= 500px',
        (tester) async {
      final ctrl1 = TextEditingController(text: 'Eye');
      final ctrl2 = TextEditingController(text: 'Regular');

      await tester.pumpWidget(
        _buildTestApp(
          Center(
            child: SizedBox(
              width: 700,
              child: ResponsiveFormRow(
                children: [
                  TextField(key: const Key('field1'), controller: ctrl1),
                  TextField(key: const Key('field2'), controller: ctrl2),
                ],
              ),
            ),
          ),
          surfaceSize: const Size(768, 600),
        ),
      );

      final pos1 = tester.getTopLeft(find.byKey(const Key('field1')));
      final pos2 = tester.getTopLeft(find.byKey(const Key('field2')));

      // In row mode, field2 is horizontally to the right of field1 at approximately the same vertical position
      expect(pos2.dx, greaterThan(pos1.dx));
      expect(pos2.dy, equals(pos1.dy));
    });
  });

  group('5. ResponsivePageHeader', () {
    testWidgets(
        'Wraps actions below title on narrow mobile screens (360px) without overflow',
        (tester) async {
      bool refreshed = false;
      bool added = false;

      await tester.pumpWidget(
        _buildTestApp(
          SizedBox(
            width: 360,
            child: ResponsivePageHeader(
              title: 'Operational Tasks Management',
              subtitle: 'Daily clinical task roster and shift carry-forwards',
              showBackButton: true,
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => refreshed = true,
                ),
                FilledButton(
                  onPressed: () => added = true,
                  child: const Text('Add Task'),
                ),
              ],
            ),
          ),
          surfaceSize: const Size(360, 600),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Operational Tasks Management'), findsOneWidget);
      expect(find.text('Add Task'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.refresh));
      expect(refreshed, isTrue);

      await tester.tap(find.text('Add Task'));
      expect(added, isTrue);

      final titlePos =
          tester.getTopLeft(find.text('Operational Tasks Management'));
      final buttonPos = tester.getTopLeft(find.text('Add Task'));

      // On narrow screen, actions are placed beneath the title row
      expect(buttonPos.dy, greaterThan(titlePos.dy));
    });

    testWidgets('Places actions side-by-side on desktop viewports (1024px)',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          const SizedBox(
            width: 1024,
            child: ResponsivePageHeader(
              title: 'Purchase Orders',
              subtitle: 'Manage supplier orders',
              actions: [
                FilledButton(
                  onPressed: null,
                  child: Text('New Order'),
                ),
              ],
            ),
          ),
          surfaceSize: const Size(1024, 768),
        ),
      );

      final titlePos = tester.getTopLeft(find.text('Purchase Orders'));
      final buttonPos = tester.getTopLeft(find.text('New Order'));

      // On wide desktop screen, action button is placed to the right
      expect(buttonPos.dx, greaterThan(titlePos.dx + 200));
    });
  });
}
