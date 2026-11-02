with open('test/sprint11_today_dashboard_test.dart', 'r', encoding='utf-8') as f:
    text = f.read()

text = text.replace(
'''      expect(tester.takeException(), isNull);
    });
}''',
'''      expect(tester.takeException(), isNull);
    });
  });
}'''
)

with open('test/sprint11_today_dashboard_test.dart', 'w', encoding='utf-8') as f:
    f.write(text)

print('Added missing group closing in sprint11_today_dashboard_test.dart!')

