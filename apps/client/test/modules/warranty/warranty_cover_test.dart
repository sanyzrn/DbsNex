import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/warranty/warranty_detail.dart';
import 'package:nex_client/modules/warranty/warranty_editor.dart';
import 'package:nex_client/modules/warranty/warranty_screen.dart';
import 'package:nex_client/modules/warranty/warranty_widgets.dart';

import '../../support/nex_harness.dart';
import 'warranty_widget_test.dart' show pumpWarranty, scrollWarrantyTo;

/// The warranty company, its support line and card, the registry and the
/// kind of cover: the things a service desk asks for, entered once and put
/// in front of the person on the purchase's page.
void main() {
  group('the cover fields', () {
    testWidgets('a purchase keeps the company, phone, card and registry', (
      tester,
    ) async {
      final h = await pumpWarranty(tester);
      // Tall enough that the purchase's own page is read in one screen, so
      // this test is about the fields and not about scrolling.
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('warranty-empty-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('warranty-field-product')),
        'Galaxy A55',
      );
      await tester.enterText(
        find.byKey(const ValueKey('warranty-field-purchase')),
        '2026/03/20',
      );
      // The kind of cover is asked before anything optional.
      await tester.tap(find.byKey(const ValueKey('warranty-cover-company')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('warranty-cover-hint')), findsOneWidget);
      await scrollWarrantyTo(
        tester,
        find.byKey(const ValueKey('warranty-term-18')),
      );
      await tester.tap(find.byKey(const ValueKey('warranty-term-18')));
      await tester.pumpAndSettle();
      // The shared calendar button and the common terms compute the end in
      // front of the person.
      expect(find.text('Ends 2027/09/20'), findsOneWidget);

      await scrollWarrantyTo(
        tester,
        find.byKey(const ValueKey('warranty-more-toggle')),
      );
      await tester.tap(find.byKey(const ValueKey('warranty-more-toggle')));
      await tester.pumpAndSettle();
      await scrollWarrantyTo(
        tester,
        find.byKey(const ValueKey('warranty-field-company')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('warranty-field-company')),
        'Hamrah Talaei',
      );
      await tester.enterText(
        find.byKey(const ValueKey('warranty-field-phone')),
        '021-91001234',
      );
      await tester.enterText(
        find.byKey(const ValueKey('warranty-field-card')),
        'C-7788',
      );
      await tester.tap(find.byKey(const ValueKey('warranty-registry-mine')));
      await tester.pumpAndSettle();
      await scrollWarrantyTo(
        tester,
        find.byKey(const ValueKey('warranty-save')),
      );
      await tester.tap(find.byKey(const ValueKey('warranty-save')));
      await tester.pumpAndSettle();

      final stored = (await NexModuleStore(
        h.services,
        'warranty',
      ).list('warranty')).single.body;
      expect(stored['v'], 2);
      expect(stored['company'], 'Hamrah Talaei');
      expect(stored['supportPhone'], '021-91001234');
      expect(stored['cardNumber'], 'C-7788');
      expect(stored['coverKind'], 'company');
      expect(stored['registryOwner'], 'mine');

      // The purchase's page puts the company and the line to call first.
      await tester.tap(find.text('Galaxy A55'));
      await tester.pumpAndSettle();
      expect(find.text('Hamrah Talaei'), findsOneWidget);
      expect(find.text('021-91001234'), findsOneWidget);
      expect(find.text('C-7788'), findsOneWidget);
      expect(find.text('In my name'), findsOneWidget);
      expect(find.text('Company warranty'), findsOneWidget);

      // Copying the number is what a person does before dialling.
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
        find.byKey(const ValueKey('warranty-copy-phone')),
      );
      await tester.tap(find.byKey(const ValueKey('warranty-copy-phone')));
      await tester.pumpAndSettle();
      expect(copied, '021-91001234');
      expect(find.text('Phone number copied.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a saved company and card survive an edit of another field', (
      tester,
    ) async {
      final h = await pumpWarranty(tester);
      final body = {
        'v': 2,
        'product': 'Kettle',
        'company': 'Boma service',
        'cardNumber': 'K-1',
        'purchasedAt': '2026-01-10',
        'coverageEnd': '2090-01-10',
      };
      await NexModuleStore(h.services, 'warranty').put('warranty', 'w1', body);
      await _pump(
        tester,
        WarrantyDetailPage(
          store: NexModuleStore(h.services, 'warranty'),
          record: ModuleRecord(
            module: 'warranty',
            kind: 'warranty',
            id: 'w1',
            body: body,
            updatedAt: DateTime.now(),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('warranty-detail-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('warranty-field-brand')),
        'Boma',
      );
      await scrollWarrantyTo(
        tester,
        find.byKey(const ValueKey('warranty-save')),
      );
      await tester.tap(find.byKey(const ValueKey('warranty-save')));
      await tester.pumpAndSettle();
      final stored = (await NexModuleStore(
        h.services,
        'warranty',
      ).list('warranty')).single.body;
      expect(stored['brand'], 'Boma');
      expect(stored['company'], 'Boma service');
      expect(stored['cardNumber'], 'K-1');
    });
  });

  group('what ends first is on top', () {
    testWidgets('the 30-day section is first and soonest first', (
      tester,
    ) async {
      final h = await pumpWarranty(tester);
      final now = DateTime.now();
      Future<void> put(String id, String product, int days) =>
          NexModuleStore(h.services, 'warranty').put('warranty', id, {
            'v': 1,
            'product': product,
            'purchasedAt': now
                .subtract(const Duration(days: 100))
                .toIso8601String(),
            'coverageEnd': now.add(Duration(days: days)).toIso8601String(),
          });
      await put('w-far', 'Far away', 400);
      await put('w-20', 'Twenty days', 20);
      await put('w-3', 'Three days', 3);
      await _pump(
        tester,
        WarrantyScreen(store: NexModuleStore(h.services, 'warranty')),
      );

      expect(
        find.byKey(const ValueKey('warranty-section-expiring')),
        findsOneWidget,
      );
      expect(find.text('Ending in the next 30 days'), findsOneWidget);
      expect(find.text('2 to deal with'), findsOneWidget);
      final rows = tester
          .widgetList<WarrantyRow>(find.byType(WarrantyRow))
          .map((row) => row.record.id)
          .toList();
      expect(rows.take(2), ['w-3', 'w-20']);
      expect(rows.last, 'w-far');
      // The heading sits above the covered section.
      final heading = tester.getTopLeft(
        find.text('Ending in the next 30 days'),
      );
      final covered = tester.getTopLeft(find.text('Covered'));
      expect(heading.dy, lessThan(covered.dy));
      expect(tester.takeException(), isNull);
    });
  });

  group('the purchase page', () {
    testWidgets('reads in Persian, dark, and says where the cover stands', (
      tester,
    ) async {
      final h = await NexTestHarness.create(name: 'warranty_detail_fa_');
      addTearDown(h.dispose);
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final body = {
        'v': 2,
        'product': 'گوشی گلکسی',
        'company': 'همراه طلایی',
        'supportPhone': '۰۲۱-۹۱۰۰۱۲۳۴',
        'coverKind': 'company',
        'registryOwner': 'mine',
        'purchasedAt': '2026-03-20',
        'coverageEnd': DateTime.now()
            .add(const Duration(days: 12))
            .toIso8601String(),
      };
      await NexModuleStore(h.services, 'warranty').put('warranty', 'w1', body);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fa'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: nexDarkTheme(),
          home: WarrantyDetailPage(
            store: NexModuleStore(h.services, 'warranty'),
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
      expect(find.text('۱۲ روز مانده'), findsOneWidget);
      expect(find.text('شرکت گارانتی'), findsOneWidget);
      expect(find.text('همراه طلایی'), findsOneWidget);
      expect(find.text('به نام من'), findsOneWidget);
      expect(
        Directionality.of(tester.state(find.byType(Scaffold)).context),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('an archived purchase says so and offers no reminder', (
      tester,
    ) async {
      final h = await NexTestHarness.create(name: 'warranty_detail_arch_');
      addTearDown(h.dispose);
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final body = {
        'v': 1,
        'product': 'Kettle',
        'purchasedAt': '2026-01-10',
        'coverageEnd': '2030-01-10',
        'archived': true,
      };
      await NexModuleStore(h.services, 'warranty').put('warranty', 'w1', body);
      await _pump(
        tester,
        WarrantyDetailPage(
          store: NexModuleStore(h.services, 'warranty'),
          record: ModuleRecord(
            module: 'warranty',
            kind: 'warranty',
            id: 'w1',
            body: body,
            updatedAt: DateTime.now(),
          ),
        ),
      );
      expect(find.text('Archived'), findsOneWidget);
      expect(find.text('Remove reminder'), findsNothing);
      expect(find.byKey(const ValueKey('warranty-reminders')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('small phone, twice the text', () {
    for (final persian in [true, false]) {
      testWidgets(
        'the list, the editor and the page hold up (${persian ? 'fa' : 'en'})',
        (tester) async {
          final h = await NexTestHarness.create(name: 'warranty_big_text_');
          addTearDown(h.dispose);
          tester.view.physicalSize = const Size(320, 480);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final now = DateTime.now();
          final body = {
            'v': 2,
            'product': persian ? 'گوشی سامسونگ' : 'Samsung phone',
            'brand': 'Samsung',
            'company': persian ? 'همراه طلایی' : 'Hamrah Talaei',
            'supportPhone': '021-91001234',
            'cardNumber': 'C-7788',
            'coverKind': 'company',
            'registryOwner': 'mine',
            'merchant': persian ? 'فروشگاه رضایی' : 'Rezaei store',
            'receiptRef': 'INV-1403-8821',
            'note': persian ? 'کارت در جعبه است.' : 'The card is in the box.',
            'purchasedAt': now
                .subtract(const Duration(days: 200))
                .toIso8601String(),
            'coverageEnd': now.add(const Duration(days: 9)).toIso8601String(),
            'durationMonths': 18,
          };
          await NexModuleStore(
            h.services,
            'warranty',
          ).put('warranty', 'w1', body);

          Widget app(Widget home) => MaterialApp(
            locale: Locale(persian ? 'fa' : 'en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2)),
              child: child ?? const SizedBox.shrink(),
            ),
            home: home,
          );

          await tester.pumpWidget(
            app(WarrantyScreen(store: NexModuleStore(h.services, 'warranty'))),
          );
          await tester.pumpAndSettle();
          expect(find.text(body['product']! as String), findsOneWidget);
          expect(tester.takeException(), isNull);

          await tester.pumpWidget(
            app(
              Scaffold(
                body: WarrantyEditorSheet(
                  store: NexModuleStore(h.services, 'warranty'),
                  existing: ModuleRecord(
                    module: 'warranty',
                    kind: 'warranty',
                    id: 'w1',
                    body: body,
                    updatedAt: now,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          await tester.pumpWidget(
            app(
              WarrantyDetailPage(
                store: NexModuleStore(h.services, 'warranty'),
                record: ModuleRecord(
                  module: 'warranty',
                  kind: 'warranty',
                  id: 'w1',
                  body: body,
                  updatedAt: now,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('warranty-status-headline')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  });
}

Future<void> _pump(WidgetTester tester, Widget home) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  );
  await tester.pumpAndSettle();
}
