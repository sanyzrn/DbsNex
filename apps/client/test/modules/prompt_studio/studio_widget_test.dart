import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/prompt_studio/prompt_model.dart';
import 'package:nex_client/modules/prompt_studio/studio_editor.dart';
import 'package:nex_client/modules/prompt_studio/studio_home.dart';
import 'package:nex_client/modules/prompt_studio/studio_repository.dart';

import '../../support/nex_harness.dart';

class FaultStore extends NexModuleStore {
  FaultStore(NexTestHarness h) : super(h.services, 'prompt_studio');
  bool badDraft = false, badWrite = false;
  @override
  Future<Map<String, Object?>?> get(String kind, String id) {
    if (kind == 'draft' && badDraft) throw StateError('unread draft');
    return super.get(kind, id);
  }

  @override
  Future<void> put(String kind, String id, Map<String, Object?> body) {
    if (kind == 'entry' && badWrite) throw StateError('failed save');
    return super.put(kind, id, body);
  }
}

Future<void> settleStudio(WidgetTester t) async {
  await t.pumpAndSettle();
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 80)),
  );
  await t.pumpAndSettle();
}

Future<void> revealStudio(WidgetTester t, Finder target) async {
  for (final delta in [-350.0, 350.0]) {
    for (var i = 0; i < 12 && target.evaluate().isEmpty; i++) {
      await t.drag(find.byType(Scrollable).first, Offset(0, delta));
      await t.pumpAndSettle();
    }
  }
  await t.ensureVisible(target);
  await t.pumpAndSettle();
  await t.ensureVisible(target);
  await t.pumpAndSettle();
}

void main() {
  late NexTestHarness h;
  late FaultStore store;
  setUp(() async {
    h = await NexTestHarness.create(name: 'prompt_ui_');
    store = FaultStore(h);
  });
  tearDown(() => h.dispose());
  Widget app(Widget home) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );
  Future<void> home(WidgetTester t) async {
    await t.pumpWidget(app(StudioHome(store: store)));
    await settleStudio(t);
  }

  Future<void> enter(WidgetTester t, String key, String text) async {
    final f = find.byKey(ValueKey('studio-$key'));
    await revealStudio(t, f);
    await t.enterText(f, text);
    await t.pumpAndSettle();
  }

  Future<void> save(WidgetTester t) async {
    final f = find.byKey(const ValueKey('studio-save'));
    await revealStudio(t, f);
    await t.tap(f);
    await settleStudio(t);
  }

  Map<String, Object?> body() => {
    'v': 1,
    'title': 'My prompt',
    'body': 'Hello {{name}} / {{name}}',
    'category': 'Work',
    'notes': '',
    'future': true,
  };

  testWidgets('starters are explicit drafts, never automatically saved data', (
    t,
  ) async {
    await home(t);
    expect(await store.list('entry'), isEmpty);
    final starter = find.text('A clear brief');
    await revealStudio(t, starter);
    await t.tap(starter);
    await settleStudio(t);
    expect(await store.list('entry'), isEmpty);
    await save(t);
    expect((await store.list('entry')).length, 1);
    expect(find.text('A clear brief'), findsWidgets);
  });
  testWidgets('back checkpoints and reopens unfinished editor input', (
    t,
  ) async {
    await home(t);
    await t.tap(find.byKey(const ValueKey('studio-add')));
    await settleStudio(t);
    await enter(t, 'title', 'Unfinished');
    await enter(t, 'body', 'Keep my words');
    await t.binding.handlePopRoute();
    await settleStudio(t);
    expect(await store.list('entry'), isEmpty);
    await t.tap(find.byKey(const ValueKey('studio-add')));
    await settleStudio(t);
    expect(
      t
          .widget<NexTextField>(find.byKey(const ValueKey('studio-title')))
          .controller
          .text,
      'Unfinished',
    );
    await save(t);
    expect((await store.list('entry')).single.body['body'], 'Keep my words');
  });
  testWidgets('failed save keeps input and retry creates exactly one record', (
    t,
  ) async {
    await home(t);
    await t.tap(find.byKey(const ValueKey('studio-add')));
    await settleStudio(t);
    await enter(t, 'title', 'Retry');
    await enter(t, 'body', '  Original text\n');
    store.badWrite = true;
    await save(t);
    expect(await store.list('entry'), isEmpty);
    expect(
      find.text('Could not save. Your input is still here; try again.'),
      findsOneWidget,
    );
    store.badWrite = false;
    await save(t);
    expect((await store.list('entry')).single.body['title'], 'Retry');
    expect(
      (await store.list('entry')).single.body['body'],
      '  Original text\n',
    );
  });
  testWidgets(
    'unread draft is not overwritten and Retry recovers its contents',
    (t) async {
      await store.put('draft', 'entry:prompt:new', {
        'v': 1,
        'base': '{}',
        'fields': {'title': 'Recovered', 'body': 'Saved draft'},
      });
      store.badDraft = true;
      await home(t);
      await t.tap(find.byKey(const ValueKey('studio-add')));
      await settleStudio(t);
      expect(find.byKey(const ValueKey('studio-body')), findsNothing);
      store.badDraft = false;
      await t.tap(find.text('Try again'));
      await settleStudio(t);
      expect(
        t
            .widget<NexTextField>(find.byKey(const ValueKey('studio-title')))
            .controller
            .text,
        'Recovered',
      );
    },
  );
  testWidgets(
    'successful copy uses literal values and clears the draft for the next visit',
    (t) async {
      final original = body();
      await store.put('entry', 'p', original);
      String? copied;
      var failCopy = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              if (failCopy) throw PlatformException(code: 'clipboard');
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await home(t);
      await t.tap(find.text('My prompt'));
      await settleStudio(t);
      expect(
        t
            .widget<FilledButton>(find.byKey(const ValueKey('studio-copy')))
            .onPressed,
        isNull,
      );
      await t.enterText(
        find.byKey(const ValueKey('fill-name')),
        r'$1 {{another}}',
      );
      await t.pumpAndSettle();
      final preview = t.widget<SelectableText>(
        find.byKey(const ValueKey('studio-preview')),
      );
      expect(preview.data, r'Hello $1 {{another}} / $1 {{another}}');
      await t.tap(find.byKey(const ValueKey('studio-copy')));
      await settleStudio(t);
      expect(copied, isNull);
      expect((await store.get('draft', 'fill:p'))?['fields'], {
        'name': r'$1 {{another}}',
      });
      failCopy = false;
      await t.tap(find.byKey(const ValueKey('studio-copy')));
      await settleStudio(t);
      expect(copied, preview.data);
      expect(await store.get('entry', 'p'), original);
      expect(await store.get('draft', 'fill:p'), isNull);
      final field = find.byKey(const ValueKey('fill-name'));
      final controller = t.widget<NexTextField>(field).controller;
      expect(controller.text, r'$1 {{another}}');
      controller.selection = const TextSelection.collapsed(offset: 1);
      await t.pump(const Duration(milliseconds: 300));
      await t.binding.handlePopRoute();
      await settleStudio(t);
      await t.tap(find.text('My prompt'));
      await settleStudio(t);
      expect(t.widget<NexTextField>(field).controller.text, isEmpty);
      expect(await store.get('draft', 'fill:p'), isNull);

      await t.enterText(field, 'Unfinished');
      await t.binding.handlePopRoute();
      await settleStudio(t);
      await t.tap(find.text('My prompt'));
      await settleStudio(t);
      expect(t.widget<NexTextField>(field).controller.text, 'Unfinished');
    },
  );
  testWidgets('block insertion replaces the editor selection as a snapshot', (
    t,
  ) async {
    await store.put('entry', 'block', {
      'v': 1,
      'title': 'Be precise',
      'body': 'EXACT',
      'block': true,
    });
    await t.pumpWidget(app(StudioEditor(repo: StudioRepository(store))));
    await settleStudio(t);
    await enter(t, 'body', 'a XX b');
    final field = t.widget<NexTextField>(
      find.byKey(const ValueKey('studio-body')),
    );
    field.controller.selection = const TextSelection(
      baseOffset: 2,
      extentOffset: 4,
    );
    await revealStudio(t, find.byKey(const ValueKey('studio-insert')));
    await t.tap(find.byKey(const ValueKey('studio-insert')));
    await settleStudio(t);
    await t.tap(find.text('Be precise'));
    await settleStudio(t);
    expect(field.controller.text, 'a EXACT b');
    await store.put('entry', 'block', {
      'v': 1,
      'title': 'Be precise',
      'body': 'CHANGED',
      'block': true,
    });
    expect(field.controller.text, 'a EXACT b');
  });
  testWidgets(
    'old versions load into editor only after explicit confirmation',
    (t) async {
      final raw = {
        ...body(),
        'history': [
          {
            'title': 'Version 1',
            'body': 'Earlier text',
            'category': '',
            'notes': '',
          },
        ],
      };
      await store.put('entry', 'p', raw);
      await t.pumpWidget(
        app(
          StudioEditor(
            repo: StudioRepository(store),
            entry: PromptEntry('p', raw),
          ),
        ),
      );
      await settleStudio(t);
      await revealStudio(t, find.text('Earlier versions'));
      await t.tap(find.text('Earlier versions'));
      await settleStudio(t);
      await t.tap(find.text('Version 1'));
      await settleStudio(t);
      expect((await store.get('entry', 'p'))!['body'], raw['body']);
      await t.tap(find.widgetWithText(FilledButton, 'Load into editor'));
      await settleStudio(t);
      expect(
        t
            .widget<NexTextField>(find.byKey(const ValueKey('studio-body')))
            .controller
            .text,
        'Earlier text',
      );
      expect((await store.get('entry', 'p'))!['body'], raw['body']);
      await save(t);
      final saved = (await store.get('entry', 'p'))!;
      expect(saved['body'], 'Earlier text');
      expect(saved['future'], true);
      expect((saved['history'] as List).first['body'], raw['body']);
    },
  );
  testWidgets(
    'conflicting edits can be saved as a copy without overwriting newer text',
    (t) async {
      final original = body();
      await store.put('entry', 'p', original);
      await home(t);
      await t.tap(find.text('My prompt'));
      await settleStudio(t);
      await t.tap(find.byTooltip('Edit'));
      await settleStudio(t);
      await enter(t, 'body', 'My unsaved work');
      await store.put('entry', 'p', {...original, 'body': 'Other writer'});
      await save(t);
      expect(
        find.textContaining('This item changed elsewhere.'),
        findsOneWidget,
      );
      final duplicate = find.widgetWithText(TextButton, 'Duplicate');
      await revealStudio(t, duplicate);
      await t.tap(duplicate);
      await settleStudio(t);
      final entries = await store.list('entry');
      expect(entries.length, 2);
      expect((await store.get('entry', 'p'))!['body'], 'Other writer');
      expect(entries.any((e) => e.body['body'] == 'My unsaved work'), isTrue);
    },
  );

  testWidgets('confirmed deletion offers Undo for the complete raw record', (
    t,
  ) async {
    final original = body();
    await store.put('entry', 'p', original);
    await home(t);
    await t.tap(find.byTooltip('More actions'));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, 'Delete'));
    await settleStudio(t);
    expect(await store.get('entry', 'p'), isNull);
    await t.tap(find.text('Undo'));
    await settleStudio(t);
    expect(await store.get('entry', 'p'), original);
  });
  testWidgets(
    'favorites include reusable blocks and the Blocks filter stays independent',
    (t) async {
      await store.put('entry', 'p', {...body(), 'favorite': true});
      await store.put('entry', 'b', {
        ...body(),
        'title': 'My block',
        'block': true,
        'favorite': true,
      });
      await home(t);
      expect(find.text('My block'), findsNothing);
      await t.tap(find.text('Favorites'));
      await settleStudio(t);
      expect(find.text('My block'), findsOneWidget);
      expect(find.text('My prompt'), findsOneWidget);
      await t.tap(find.text('Blocks'));
      await settleStudio(t);
      expect(find.text('My block'), findsOneWidget);
      expect(find.text('My prompt'), findsNothing);
    },
  );
}
