import 'package:flutter_test/flutter_test.dart';
import 'package:mkes_care/features/admin/models/user_profile.dart';

void main() {
  test('UserProfile deserialization smoke test', () {
    final user = UserProfile.fromJson({
      'id': 'test-id',
      'full_name': 'Dr. Sharma',
      'email': 'sharma@mkes.com',
      'role': 'staff',
      'is_active': true,
      'salary': 50000.0,
      'joining_date': '2024-01-15',
      'created_at': '2024-01-15T00:00:00Z',
    });

    expect(user.fullName, equals('Dr. Sharma'));
    expect(user.role, equals('staff'));
    expect(user.salary, equals(50000.0));
    expect(user.joiningDate, equals(DateTime(2024, 1, 15)));
  });
}
