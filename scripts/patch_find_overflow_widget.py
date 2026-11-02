with open('test/sprint11_today_dashboard_test.dart', 'r', encoding='utf-8') as f:
    text = f.read()

target = '''final err = tester.takeException();
      for (final el in tester.allElements) {
        final ro = el.renderObject;
        if (ro is RenderFlex && ro.hasSize) {
          if (ro.size.width > 360) {
            print('OVERFLOWING WIDGET: ' + el.widget.runtimeType.toString() + ' width=' + ro.size.width.toString());
            Element? p = el;
            for (int i = 0; i < 5 && p != null; i++) {
              print('  PARENT: ' + p.widget.runtimeType.toString());
              p = p.findAncestorElementOfExactType();
            }
          }
        }
      }
      expect(err, isNull);'''

replacement = '''final err = tester.takeException();
      for (final el in tester.allElements) {
        final ro = el.renderObject;
        if (ro is RenderFlex && ro.hasSize && ro.size.width > 350) {
          final chain = <String>[];
          el.visitAncestorElements((anc) {
            chain.add(anc.widget.runtimeType.toString());
            return chain.length < 6;
          });
          print('FLEX > 350: ' + el.widget.runtimeType.toString() + ' w=' + ro.size.width.toString() + ' in ' + chain.join(' -> '));
        }
      }
      expect(err, isNull);'''

text = text.replace(target, replacement)
with open('test/sprint11_today_dashboard_test.dart', 'w', encoding='utf-8') as f:
    f.write(text)
