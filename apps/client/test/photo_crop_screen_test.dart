import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/screens/photo_crop_screen.dart';

/// A real, decodable 100x100 solid-color PNG. crop_your_image parses the
/// image bytes for real (including scaling against the viewport), so
/// placeholder bytes like `[1, 2, 3]` throw inside the parser's isolate
/// before the widget ever reaches a testable state.
final _testPng = Uint8List.fromList(
  base64.decode(
    'iVBORw0KGgoAAAANSUhEUgAAAGQAAABkCAIAAAD/gAIDAAAAoUlEQVR42u3QMQ0AAAgDsGmafwHI'
    'wgIfT5MqaKblKApkyZIlS5YsBbJkyZIlS5YCWbJkyZIlS4EsWbJkyZKlQJYsWbJkyVIgS5YsWbJk'
    'KZAlS5YsWbIUyJIlS5YsWQpkyZIlS5YsBbJkyZIlS5YCWbJkyZIlS4EsWbJkyZKlQJYsWbJkyVIg'
    'S5YsWbJkKZAlS5YsWbIUyJIlS5YsWQpkyfq2ZknJZEUYbWQAAAAASUVORK5CYII=',
  ),
);

/// Pushes [PhotoCropScreen] behind a button so the test can capture whatever
/// value the route is popped with, the same way [TimelineScreenState.capturePhoto]
/// awaits it.
Future<Uint8List? Function()> _pushCropScreen(WidgetTester tester) async {
  Uint8List? result;
  var resultSet = false;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await Navigator.of(context).push<Uint8List>(
              MaterialPageRoute(
                builder: (_) => PhotoCropScreen(image: _testPng),
              ),
            );
            resultSet = true;
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () {
    expect(resultSet, isTrue, reason: 'the pushed route never popped');
    return result;
  };
}

void main() {
  testWidgets('discarding the photo pops null, not the original bytes', (
    tester,
  ) async {
    final getResult = await _pushCropScreen(tester);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(getResult(), isNull);
  });

  testWidgets('confirming the crop pops the cropped bytes', (tester) async {
    final getResult = await _pushCropScreen(tester);

    // The parser and cropper both run through compute(), which spawns a real
    // isolate — it never resolves inside flutter_test's fake-async pump, so
    // both waits need runAsync the way crop_your_image's own tests do.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 1)),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.check));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 1)),
    );
    await tester.pumpAndSettle();

    final result = getResult();
    expect(result, isNotNull);
    expect(result, isNot(equals(_testPng)));
  });
}
