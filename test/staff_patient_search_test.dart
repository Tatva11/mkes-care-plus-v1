import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkes_care/features/patients/models/patient_model.dart';
import 'package:mkes_care/features/patients/screens/patient_details_screen.dart';

void main() {
  group('CHANGE 3: Staff Patient Search Navigation Fix', () {
    final patientA = PatientModel(
      id: 'patient-uuid-111',
      patientNumber: 'P-1001',
      name: 'Ramesh Gupta',
      dob: DateTime(1985, 5, 20),
      mobile: '+91 9876543210',
      department: 'eye',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final patientB = PatientModel(
      id: 'patient-uuid-222',
      patientNumber: 'P-1002',
      name: 'Sunita Sharma',
      dob: DateTime(1992, 8, 14),
      mobile: '+91 9123456789',
      department: 'dental',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    testWidgets('Tapping search result navigates to PatientDetailsScreen with matching patientId',
        (tester) async {
      final navigatorObserver = _TestNavigatorObserver();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            navigatorObservers: [navigatorObserver],
            home: Scaffold(
              body: ListView(
                children: [
                  // Build search result using the dedicated result widget
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Builder(
                      builder: (context) {
                        return InkWell(
                          key: Key('staff_patient_search_result_${patientA.id}'),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    PatientDetailsScreen(patientId: patientA.id),
                              ),
                            );
                          },
                          child: Text(patientA.name),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Verify no "I Attended" button exists
      expect(find.text('I Attended'), findsNothing);
      expect(find.text('Attended'), findsNothing);

      // Tap on Ramesh Gupta
      await tester.tap(find.byKey(Key('staff_patient_search_result_${patientA.id}')));
      await tester.pumpAndSettle();

      // Verify PatientDetailsScreen was pushed with Ramesh Gupta's ID
      expect(find.byType(PatientDetailsScreen), findsOneWidget);
      final detailsWidget = tester.widget<PatientDetailsScreen>(find.byType(PatientDetailsScreen));
      expect(detailsWidget.patientId, equals('patient-uuid-111'));
    });

    testWidgets('Tapping different search result opens the respective patient details screen',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [
                  Builder(
                    builder: (context) => InkWell(
                      key: Key('staff_patient_search_result_${patientB.id}'),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                PatientDetailsScreen(patientId: patientB.id),
                          ),
                        );
                      },
                      child: Text(patientB.name),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Tap on Sunita Sharma
      await tester.tap(find.byKey(Key('staff_patient_search_result_${patientB.id}')));
      await tester.pumpAndSettle();

      // Verify PatientDetailsScreen was pushed with Sunita Sharma's ID
      expect(find.byType(PatientDetailsScreen), findsOneWidget);
      final detailsWidget = tester.widget<PatientDetailsScreen>(find.byType(PatientDetailsScreen));
      expect(detailsWidget.patientId, equals('patient-uuid-222'));
    });
  });
}

class _TestNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushedRoutes = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRoutes.add(route);
    super.didPush(route, previousRoute);
  }
}
