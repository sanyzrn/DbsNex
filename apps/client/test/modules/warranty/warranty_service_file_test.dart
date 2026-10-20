import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/warranty/warranty_detail.dart';
import 'package:nex_client/modules/warranty/warranty_models.dart';
import 'package:nex_client/modules/warranty/warranty_service_file.dart';

import '../../support/nex_harness.dart';

/// The service file: the purchase and its dated notes as text to hand over.
void main() {
  late NexTestHarness h;
  late NexModuleStore store;

  setUp(() async {
    h = await NexTestHarness.create(name: 'warranty_file_');
    store = NexModuleStore(h.services, 'warranty');
  });
  tearDown(() => h.dispose());

  Future<void> pump(WidgetTester tester, Widget home, {Locale? locale}) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: locale ?? const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );
    await tester.pumpAndSettle();
  }

  ModuleRecord purchase(Map<String, Object?> body) => ModuleRecord(
    module: 'warranty',
    kind: WarrantyModels.warranty,
    id: 'w1',
    body: body,
    updatedAt: DateTime.now(),
  );

  ModuleRecord claim(String id, String kind, String at, String note) =>
      ModuleRecord(
        module: 'warranty',
        kind: WarrantyModels.claim,
        id: id,
        body: {'warrantyId': 'w1', 'kind': kind, 'note': note, 'at': at},
        updatedAt: DateTime.now(),
      );

  testWidgets('lists what is written, in order, and nothing that is not', (
    tester,
  ) async {
    late String text;
    await pump(
      tester,
      Builder(
        builder: (context) {
          text = warrantyServiceFile(
            context,
            {
              'v': 1,
              'product': 'Kettle',
              'brand': 'Acme',
              'serial': 'SN-42',
              'merchant': 'Corner shop',
              'purchasedAt': '2026-10-13',
              'coverageEnd': '2028-10-13',
            },
            [
              claim('c2', 'service', '2027-03-02T10:00:00Z', 'Lid replaced'),
              claim('c1', 'claim', '2027-01-05T10:00:00Z', 'Stopped heating'),
            ],
          );
          return const SizedBox();
        },
      ),
    );
    final lines = text.split('\n');
    expect(lines.first, 'Kettle');
    expect(text, contains('Brand: Acme'));
    expect(text, contains('Serial / invoice: SN-42'));
    expect(text, contains('Merchant: Corner shop'));
    expect(text, contains('Purchased: 2026/10/13'));
    expect(text, contains('Coverage ends: 2028/10/13'));
    // Not written, not listed.
    expect(text, isNot(contains('Model')));
    expect(text, isNot(contains('Receipt')));
    // Oldest note first.
    expect(
      text.indexOf('Stopped heating'),
      lessThan(text.indexOf('Lid replaced')),
    );
    expect(text, contains('Claim: Stopped heating'));
    expect(text, contains('Service: Lid replaced'));
  });

  testWidgets('a purchase with no notes has no notes heading', (tester) async {
    late String text;
    await pump(
      tester,
      Builder(
        builder: (context) {
          text = warrantyServiceFile(context, {'v': 1, 'product': 'Lamp'}, []);
          return const SizedBox();
        },
      ),
    );
    expect(text, 'Lamp');
  });

  testWidgets('the detail sheet says when no invoice or serial is written', (
    tester,
  ) async {
    final body = {
      'v': 1,
      'product': 'Kettle',
      'purchasedAt': '2026-10-13',
      'coverageEnd': '2030-10-13',
    };
    await store.put('warranty', 'w1', body);
    await pump(
      tester,
      WarrantyDetailSheet(store: store, record: purchase(body)),
    );
    expect(find.byKey(const ValueKey('warranty-no-proof')), findsOneWidget);

    final withSerial = {...body, 'serial': 'SN-1'};
    await store.put('warranty', 'w1', withSerial);
    await pump(
      tester,
      WarrantyDetailSheet(store: store, record: purchase(withSerial)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('warranty-no-proof')), findsNothing);
  });
}
