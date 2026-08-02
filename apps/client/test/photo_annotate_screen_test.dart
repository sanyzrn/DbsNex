import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/screens/photo_annotate_screen.dart';

/// Same fixture as photo_crop_screen_test.dart: a real, decodable 100x100
/// PNG, since `img.decodeImage` (used to read the native size) rejects
/// placeholder bytes outright.
final _testPng = Uint8List.fromList(
  base64.decode(
    'iVBORw0KGgoAAAANSUhEUgAAAGQAAABkCAIAAAD/gAIDAAAAoUlEQVR42u3QMQ0AAAgDsGmafwHI'
    'wgIfT5MqaKblKApkyZIlS5YsBbJkyZIlS5YCWbJkyZIlS4EsWbJkyZKlQJYsWbJkyVIgS5YsWbJk'
    'KZAlS5YsWbIUyJIlS5YsWQpkyZIlS5YsBbJkyZIlS5YCWbJkyZIlS4EsWbJkyZKlQJYsWbJkyVIg'
    'S5YsWbJkKZAlS5YsWbIUyJIlS5YsWQpkyfq2ZknJZEUYbWQAAAAASUVORK5CYII=',
  ),
);

Future<Uint8List? Function()> _pushAnnotateScreen(WidgetTester tester) async {
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
                builder: (_) => PhotoAnnotateScreen(image: _testPng),
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

/// Taps inside the actual rendered photo, at an offset from its centre —
/// hardcoding absolute screen coordinates would depend on the test surface's
/// default size lining up with wherever `Center` + `AspectRatio` happens to
/// place the square canvas.
Future<void> _tapOnPhoto(WidgetTester tester, Offset fromCenter) async {
  final center = tester.getCenter(find.byType(CustomPaint).first);
  await tester.tapAt(center + fromCenter);
}

Future<void> _placeText(WidgetTester tester, Offset at, String text) async {
  await _tapOnPhoto(tester, at);
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('nothing drawn or typed means Done pops null', (tester) async {
    final getResult = await _pushAnnotateScreen(tester);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(getResult(), isNull);
  });

  testWidgets(
    'a freehand stroke is baked into the photo at its native resolution',
    (tester) async {
      final getResult = await _pushAnnotateScreen(tester);

      await tester.drag(
        find.byType(CustomPaint).first,
        const Offset(40, 40),
        touchSlopX: 0,
        touchSlopY: 0,
      );
      await tester.pump();

      await tester.tap(find.text('Done'));
      // `toImage` on the RepaintBoundary is itself async.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      await tester.pumpAndSettle();

      final result = getResult();
      expect(result, isNotNull);
      final decoded = img.decodeImage(result!)!;
      expect(decoded.width, 100);
      expect(decoded.height, 100);
    },
  );

  testWidgets('placed text can be dragged to reposition before Done', (
    tester,
  ) async {
    await _pushAnnotateScreen(tester);

    await tester.tap(find.text('Text'));
    await tester.pump();
    await _placeText(tester, Offset.zero, 'hello');

    expect(find.text('hello'), findsOneWidget);

    final before = tester.getTopLeft(find.text('hello'));
    await tester.drag(find.text('hello'), const Offset(15, 0));
    await tester.pump();
    final after = tester.getTopLeft(find.text('hello'));

    expect(after.dx, greaterThan(before.dx));
  });

  testWidgets('undo removes the last mark, clear removes all of them', (
    tester,
  ) async {
    await _pushAnnotateScreen(tester);

    await tester.tap(find.text('Text'));
    await tester.pump();
    await _placeText(tester, const Offset(-20, -20), 'first');
    await _placeText(tester, const Offset(20, 20), 'second');

    expect(find.text('first'), findsOneWidget);
    expect(find.text('second'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pumpAndSettle();
    expect(find.text('first'), findsOneWidget);
    expect(find.text('second'), findsNothing);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('first'), findsNothing);
  });
}
