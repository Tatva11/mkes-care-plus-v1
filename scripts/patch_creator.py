with open('test/sprint11_today_dashboard_test.dart', 'r', encoding='utf-8') as f:
    text = f.read()

target = '''final err = tester.takeException();
      if (err is FlutterError) {
        print('FLUTTER ERROR DETAILS: ' + err.toStringDeep());
        for (final detail in err.diagnostics) {
          print('DIAGNOSTIC: ' + detail.toString());
        }
      }
      expect(err, isNull);'''

replacement = '''final err = tester.takeException();
      if (err is FlutterError) {
        for (final d in err.diagnostics) {
          print('DIAG: ' + d.name.toString() + ' -> ' + d.toDescription().toString());
          try {
            final val = d.value;
            if (val is RenderObject) {
              print('CREATOR: ' + val.debugCreator.toString());
            }
          } catch (_) {}
        }
      }
      expect(err, isNull);'''

text = text.replace(target, replacement)
with open('test/sprint11_today_dashboard_test.dart', 'w', encoding='utf-8') as f:
    f.write(text)

