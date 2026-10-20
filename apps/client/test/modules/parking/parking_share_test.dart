import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/parking/parking_share.dart';

/// «Where is the car», as text to send: only what was written, and a map
/// link only when both coordinates were typed and are real.
void main() {
  Future<String> share(
    WidgetTester tester,
    Map<String, Object?> body, {
    Locale locale = const Locale('en'),
  }) async {
    late String text;
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            text = parkingShareText(context, body);
            return const SizedBox();
          },
        ),
      ),
    );
    return text;
  }

  testWidgets('the written fields, in order, and a map link', (tester) async {
    final text = await share(tester, {
      'vehicle': 'Blue hatchback',
      'place': 'City Center mall',
      'floor': 'B2',
      'spot': 'C7',
      'landmark': 'Near the red lift',
      'lat': 35.6892,
      'lng': 51.389,
      'startedAt': '2026-10-20T10:00:00.000Z',
    });
    final lines = text.split('\n');
    expect(lines[0], 'Vehicle: Blue hatchback');
    expect(lines[1], 'Place: City Center mall');
    expect(text, contains('Floor: B2'));
    expect(text, contains('Section / spot: C7'));
    expect(text, contains('Landmark: Near the red lift'));
    expect(lines.last, 'https://www.google.com/maps?q=35.689200,51.389000');
  });

  testWidgets('nothing is invented for what was left empty', (tester) async {
    final text = await share(tester, {'vehicle': 'Car', 'place': 'Street'});
    expect(text, 'Vehicle: Car\nPlace: Street');
  });

  testWidgets('a coordinate outside the globe is no link at all', (
    tester,
  ) async {
    final text = await share(tester, {
      'place': 'Somewhere',
      'lat': 95,
      'lng': 51.0,
    });
    expect(text, isNot(contains('google')));
    final one = await share(tester, {'place': 'Somewhere', 'lat': 35.0});
    expect(one, isNot(contains('google')));
  });
}
