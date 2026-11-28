import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/warranty/warranty_detail.dart';
import 'package:nex_client/modules/warranty/warranty_service_file.dart';

import 'warranty_widget_test.dart' show pumpWarranty, scrollWarrantyTo;
import '../../support/text_input.dart';

/// The purchase page as it is used at a service desk: the brand, model and
/// category the person typed are on it, the serial, the card number and the
/// invoice are one tap from the clipboard, a reminder names the purchase it
/// is about, and the claim sheet's complaint leaves when its answer arrives.
void main() {
  final body = <String, Object?>{
    'v': 2,
    'product': 'Galaxy A55',
    'category': 'Electronics',
    'brand': 'Samsung',
    'model': 'SM-A556E',
    'serial': '352099001761481',
    'cardNumber': 'C-7788',
    'receiptRef': 'INV-1403-8821',
    'company': 'Hamrah Talaei',
    'supportPhone': '021-91001234',
    'purchasedAt': '2026-03-20',
    'coverageEnd': '2090-09-20',
  };

  Future<void> pumpDetail(WidgetTester tester, NexModuleStore store) async {
    await store.put('warranty', 'w1', body);
    // Tall enough that the purchase's own page is read in one screen, so
    // these tests are about the rows and not about scrolling to them.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: WarrantyDetailPage(
          store: store,
          record: ModuleRecord(
            module: 'warranty',
            kind: 'warranty',
            id: 'w1',
            body: body,
            updatedAt: DateTime.now(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the brand, the model and the category are on the page', (
    tester,
  ) async {
    final h = await pumpWarranty(tester);
    await pumpDetail(tester, NexModuleStore(h.services, 'warranty'));
    expect(find.text('Samsung'), findsOneWidget);
    expect(find.text('SM-A556E'), findsOneWidget);
    expect(find.text('Electronics'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the serial, the card and the invoice are one tap from the '
      'clipboard', (tester) async {
    final h = await pumpWarranty(tester);
    await pumpDetail(tester, NexModuleStore(h.services, 'warranty'));
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await scrollWarrantyTo(
      tester,
      find.byKey(const ValueKey('warranty-copy-serial')),
    );
    await tester.tap(find.byKey(const ValueKey('warranty-copy-serial')));
    await tester.pumpAndSettle();
    expect(copied, '352099001761481');
    expect(find.text('Copied.'), findsOneWidget);

    copied = null;
    await scrollWarrantyTo(
      tester,
      find.byKey(const ValueKey('warranty-copy-card')),
    );
    await tester.tap(find.byKey(const ValueKey('warranty-copy-card')));
    await tester.pumpAndSettle();
    expect(copied, 'C-7788');

    copied = null;
    await scrollWarrantyTo(
      tester,
      find.byKey(const ValueKey('warranty-copy-receipt')),
    );
    await tester.tap(find.byKey(const ValueKey('warranty-copy-receipt')));
    await tester.pumpAndSettle();
    expect(copied, 'INV-1403-8821');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the reminder a purchase page sets names the purchase and '
      'opens on its end date', (tester) async {
    final h = await pumpWarranty(tester);
    await pumpDetail(tester, NexModuleStore(h.services, 'warranty'));
    final control = tester.widget<NexModuleReminderControl>(
      find.byKey(const ValueKey('warranty-reminders')),
    );
    expect(control.initial, isNotNull);
    // The picker opens on the coverage end, not on today.
    final initial = control.initial!;
    expect(initial.year, 2090);
    expect(initial.month, 9);
    expect(initial.day, 20);
    // The alert says what it is about — never "you have a reminder".
    expect(control.body, contains('Galaxy A55'));
    expect(control.body, isNot(contains('Open Nex')));
  });

  testWidgets('the claim sheet takes back its complaint once the person '
      'writes', (tester) async {
    final h = await pumpWarranty(tester);
    final store = NexModuleStore(h.services, 'warranty');
    await store.put('warranty', 'w1', {
      'v': 2,
      'product': 'Kettle',
      'purchasedAt': '2026-01-10',
      'coverageEnd': '2090-01-10',
    });
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: WarrantyDetailPage(
          store: store,
          record: ModuleRecord(
            module: 'warranty',
            kind: 'warranty',
            id: 'w1',
            body: {'product': 'Kettle'},
            updatedAt: DateTime.now(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await scrollWarrantyTo(
      tester,
      find.byKey(const ValueKey('warranty-add-claim')),
    );
    await tester.tap(find.byKey(const ValueKey('warranty-add-claim')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('warranty-claim-save')));
    await tester.pump();
    expect(find.text('Write what the note should say.'), findsOneWidget);

    await enterNexText(
      tester,
      find.byKey(const ValueKey('warranty-claim-field')),
      'Called the shop; part ordered.',
    );
    await tester.pump();
    expect(find.text('Write what the note should say.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a zero duration no record of this module ever wrote is not '
      'shown as a coverage of nothing', (tester) async {
    late String text;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            text = warrantyServiceFile(context, {
              'v': 2,
              'product': 'Kettle',
              'purchasedAt': '2026-01-10',
              'coverageEnd': '2090-01-10',
              'durationMonths': 0,
            }, const []);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(text, isNot(contains('Duration')));
  });
}
