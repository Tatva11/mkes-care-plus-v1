with open('test/sprint11_today_dashboard_test.dart', 'r', encoding='utf-8') as f:
    text = f.read()

# Replace the test to print which widget overflows
find_overflow_code = '''final err = tester.takeException();
      if (err is FlutterError) {
        print('FLUTTER ERROR DETAILS: ' + err.toStringDeep());
        for (final detail in err.diagnostics) {
          print('DIAGNOSTIC: ' + detail.toString());
        }
      }
      expect(err, isNull);'''

text = text.replace(
    '''final err = tester.takeException();
      if (err is FlutterError) {
        print('FLUTTER ERROR DETAILS: ' + err.toStringDeep());
      }
      expect(err, isNull);''',
    find_overflow_code
)

with open('test/sprint11_today_dashboard_test.dart', 'w', encoding='utf-8') as f:
    f.write(text)

