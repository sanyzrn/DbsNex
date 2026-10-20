import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/ui_text_scaler.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/module_registry.dart';
import 'package:nex_client/modules/expenses/form_draft.dart';
import 'package:nex_client/modules/expenses/local_writes.dart';
import 'package:nex_client/modules/habits/record_bundle.dart';
import 'package:nex_client/modules/medicine/nex_text_field.dart';
import 'package:nex_client/widgets/nex_text_field.dart' as editor;
import 'package:nex_client/widgets/persian_date_picker.dart';
import 'package:nex_client/platform/reminders.dart';
import 'support/nex_harness.dart';

class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();
  @override
  double scale(double size) => size < 20 ? size * 3 : size * 2;
  @override
  double get textScaleFactor => 3;
}

void main() {
  test('system scaling above 1.9 and nonlinear sizes survive composition', () {
    const scaler = NexUiTextScaler(_NonlinearScaler(), 1.2);
    expect(scaler.scale(12), closeTo(43.2, .001));
    expect(scaler.scale(30), 72);
  });

  testWidgets('Enter uses tap, while touch long press still uses long press', (
    tester,
  ) async {
    var taps = 0, holds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NexTappable(
            onTap: () => taps++,
            onLongPress: () => holds++,
            shape: const StadiumBorder(),
            child: const Text('Action'),
          ),
        ),
      ),
    );
    final context = tester.element(find.text('Action'));
    Actions.invoke(context, const ActivateIntent());
    expect(taps, 1);
    expect(holds, 0);
    await tester.longPress(find.text('Action'));
    await tester.pumpAndSettle();
    expect(holds, 1);
  });

  testWidgets('legacy module fields use the actual shared editor', (
    tester,
  ) async {
    final text = TextEditingController(text: 'فارسی\nEnglish');
    addTearDown(text.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MedicineTextField(controller: text)),
      ),
    );
    expect(find.byType(editor.NexTextField), findsOneWidget);
  });

  testWidgets('module picker follows the inherited Jalali calendar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: NexModuleCalendar(
          solar: true,
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => nexPickModuleDate(
                  context,
                  initial: DateTime(2026, 10, 18),
                  first: DateTime(2020),
                  last: DateTime(2030),
                ),
                child: const Text('Pick'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pick'));
    await tester.pumpAndSettle();
    expect(find.byType(PersianDatePicker), findsOneWidget);
  });

  group('module persistence', () {
    late NexTestHarness h;
    late NexModuleStore store;
    setUp(() async {
      h = await NexTestHarness.create(name: 'nex_213_');
      store = NexModuleStore(h.services, 'expenses');
    });
    tearDown(() => h.dispose());

    test('draft and journal writes do not emit saved-data changes', () async {
      var records = 0, drafts = 0;
      final a = store.changes.listen((_) => records++);
      final b = store.draftChanges.listen((_) => drafts++);
      await store.put('draft', 'new', {'text': 'typing'});
      await store.put('operation', 'journal', {'v': 1});
      await store.delete('draft', 'new');
      await store.put('tx', 'saved', {'amount': 3});
      await Future<void>.delayed(Duration.zero);
      expect(records, 1);
      expect(drafts, 2);
      await a.cancel();
      await b.cancel();
    });

    test('rapid edits coalesce and close flushes the newest text', () async {
      final text = TextEditingController();
      final draft = FormDraft(store, 'tx:new', {}, {'note': text}, () => {});
      var writes = 0;
      final changes = store.draftChanges.listen((_) => writes++);
      draft.start();
      text.text = 'a';
      text.text = 'ab';
      text.text = 'abc';
      expect(await store.get('draft', 'tx:new'), isNull);
      expect(await draft.finish(), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(writes, 1);
      expect(
        ((await store.get('draft', 'tx:new'))!['fields'] as Map)['note'],
        'abc',
      );
      await draft.clear();
      await Future<void>.delayed(const Duration(milliseconds: 280));
      expect(await store.get('draft', 'tx:new'), isNull);
      await changes.cancel();
      text.dispose();
    });

    test(
      'unknown and malformed journals do not block healthy operations or replay partially',
      () async {
        await store.put('tx', 'healthy', {'value': 'current'});
        await store.put('operation', 'future', {'v': 99, 'before': []});
        await store.put('operation', 'malformed', {
          'v': 1,
          'before': [
            {
              'kind': 'tx',
              'id': 'healthy',
              'body': {'value': 'old'},
            },
            {'kind': 7, 'id': 'bad'},
          ],
        });
        await store.put('operation', 'missing-body', {
          'v': 1,
          'before': [
            {'kind': 'tx', 'id': 'healthy'},
          ],
        });
        await LocalWrites.recover(store);
        expect((await store.get('tx', 'healthy'))!['value'], 'current');
        expect(await store.list('operation'), isEmpty);
        final originals = await store.list('__recovery');
        expect(
          originals.map((r) => r.body['id']),
          containsAll(['future', 'malformed', 'missing-body']),
        );
        await LocalWrites.patch(store, 'tx', 'healthy', {'next': true});
        expect((await store.get('tx', 'healthy'))!['next'], isTrue);
      },
    );

    test('bundle recovery preserves unknown versions without replay', () async {
      await store.put('operation', 'unknown-bundle', {
        'v': 99,
        'records': [
          {
            'kind': 'tx',
            'id': 'x',
            'body': {'value': 'future'},
          },
        ],
      });
      await RecordBundle.recover(store);
      expect(await store.get('tx', 'x'), isNull);
      expect(
        (await store.list('__recovery')).single.body['id'],
        'unknown-bundle',
      );
    });

    test(
      'Soon rollout blocks reminder scheduling without changing installation choices',
      () async {
        await h.preferences.setModuleOn('medicine', true);
        final medicine = NexModuleStore(h.services, 'medicine');
        expect(
          await medicine.setReminder(
            'test',
            sourceKind: 'medicine',
            sourceId: 'm',
            at: DateTime.now().add(const Duration(days: 1)),
            title: 'Nex',
            body: 'Reminder',
          ),
          isFalse,
        );
        expect(await medicine.list('__reminder'), isEmpty);
        expect(h.preferences.isModuleOn('medicine'), isTrue);
        expect(nexModules.where((m) => m.available).map((m) => m.id).toSet(), {
          'cycle',
          'habits',
          'price_lens',
          'lent_borrowed',
        });
        expect(
          NexModuleAlarms.moduleId('a', 'b:c'),
          isNot(NexModuleAlarms.moduleId('a:b', 'c')),
        );
      },
    );
  });
}
