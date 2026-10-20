import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/maintenance/models.dart';
import 'package:nex_client/modules/maintenance/service_history.dart';
import 'package:nex_client/modules/maintenance/units.dart';
import 'package:nex_client/modules/module_api.dart';

/// The service history, as text to hand over: dated, newest first, each
/// cost in its own currency and none of them added together.
void main() {
  Future<String> history(
    WidgetTester tester,
    MaintenanceAsset asset,
    List<ServiceEvent> events, {
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
            text = serviceHistoryText(context, asset, events);
            return const SizedBox();
          },
        ),
      ),
    );
    return text;
  }

  final car = MaintenanceAsset(
    id: 'a1',
    nickname: 'Family car',
    type: 'car',
    model: 'Hatchback 2018',
    meterKind: MeterKind.distance,
  );

  ServiceEvent event(
    String id,
    DateTime date,
    String task, {
    int? cost,
    String? currency,
    int? meter,
    String? provider,
    String? notes,
  }) => ServiceEvent(
    id: id,
    assetId: 'a1',
    date: date,
    task: task,
    cost: cost,
    currency: currency,
    meter: meter,
    meterUnit: meter == null ? null : DistanceUnit.km,
    meterScale: 1,
    provider: provider,
    notes: notes,
  );

  testWidgets('newest first, with reading, provider and cost as written', (
    tester,
  ) async {
    final text = await history(tester, car, [
      event(
        'e1',
        DateTime(2026, 1, 10),
        'Oil change',
        cost: 150000,
        currency: 'USD',
        meter: 40000,
        provider: 'Garage',
      ),
      event(
        'e2',
        DateTime(2026, 8, 3),
        'Brake pads',
        cost: 2000000,
        currency: 'IRR',
        notes: 'Front only',
      ),
    ]);
    final lines = text.split('\n');
    expect(lines.first, 'Family car');
    expect(lines[1], contains('Hatchback 2018'));
    expect(text.indexOf('Brake pads'), lessThan(text.indexOf('Oil change')));
    expect(text, contains('2026/08/03 · Brake pads · 20,000 IRR'));
    expect(text, contains('Oil change · Garage · 40,000 km · 1,500 USD'));
    expect(text, contains('  Front only'));
    // Two currencies stay two lines; no total is invented.
    expect(text.toLowerCase(), isNot(contains('total')));
  });

  testWidgets('no services says so instead of an empty list', (tester) async {
    final text = await history(tester, car, const []);
    expect(text, contains('Service history'));
    expect(text, contains('No services written down yet.'));
  });

  testWidgets('in Persian: Jalali date, Persian digits', (tester) async {
    final text = await history(tester, car, [
      event('e1', DateTime(2026, 10, 20), 'Oil', cost: 150000, currency: 'IRR'),
    ], locale: const Locale('fa'));
    expect(text, contains('۱۴۰۵/۰۷/۲۸'));
    // The model is the person's own words; the service line is the module's.
    final line = text.split('\n').firstWhere((l) => l.startsWith('- '));
    expect(line.contains(RegExp('[0-9]')), isFalse);
  });
}
