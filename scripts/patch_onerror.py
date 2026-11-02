with open('test/sprint11_today_dashboard_test.dart', 'r', encoding='utf-8') as f:
    text = f.read()

target = '''    testWidgets('Renders complete dashboard and handles pull-to-refresh without overflow on 360x640', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);'''

replacement = '''    testWidgets('Renders complete dashboard and handles pull-to-refresh without overflow on 360x640', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        print('EXACT OVERFLOW ERROR: ' + details.exceptionAsString());
        print('INFORMATION COLLECTOR: ' + (details.informationCollector?.call().map((d) => d.toString()).join('\\n') ?? 'none'));
      };
      addTearDown(() => FlutterError.onError = originalOnError);'''

text = text.replace(target, replacement)
with open('test/sprint11_today_dashboard_test.dart', 'w', encoding='utf-8') as f:
    f.write(text)
print('Added FlutterError.onError logger!')

