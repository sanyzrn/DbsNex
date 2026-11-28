import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/security_tools/security_home.dart';
import 'package:nex_client/modules/security_tools/secret_screen.dart';

import '../../support/nex_harness.dart';
import '../../support/text_input.dart';

class SecurityFaultStore extends NexModuleStore {
  SecurityFaultStore(NexTestHarness h) : super(h.services, 'security_tools');
  bool badDraft = false, badWrite = false, badCleanup = false;
  @override
  Future<Map<String, Object?>?> get(String kind, String id) {
    if (kind == 'draft' && badDraft) throw StateError('draft unavailable');
    return super.get(kind, id);
  }

  @override
  Future<void> put(String kind, String id, Map<String, Object?> raw) {
    if (kind == 'draft' && raw['discarded'] == true && badCleanup) {
      throw StateError('cleanup unavailable');
    }
    if (kind == 'account' && badWrite) throw StateError('write unavailable');
    return super.put(kind, id, raw);
  }

  @override
  Future<void> delete(String kind, String id) {
    if (kind == 'draft' && badCleanup) throw StateError('cleanup unavailable');
    return super.delete(kind, id);
  }
}

Future<void> settleSecurity(WidgetTester t) async {
  await t.pumpAndSettle();
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 80)),
  );
  await t.pumpAndSettle();
}

Future<void> revealSecurity(WidgetTester t, Finder f) async {
  for (final delta in [-350.0, 350.0]) {
    for (var i = 0; i < 12 && f.evaluate().isEmpty; i++) {
      await t.drag(find.byType(Scrollable).first, Offset(0, delta));
      await t.pumpAndSettle();
    }
  }
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.ensureVisible(f);
  await t.pumpAndSettle();
}

void main() {
  late NexTestHarness h;
  late SecurityFaultStore store;
  setUp(() async {
    h = await NexTestHarness.create(name: 'security_ui_');
    store = SecurityFaultStore(h);
  });
  tearDown(() => h.dispose());
  Widget app(Widget home) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );
  Future<void> home(WidgetTester t) async {
    await t.pumpWidget(app(SecurityHome(store: store)));
    await settleSecurity(t);
  }

  Future<void> save(WidgetTester t) async {
    final f = find.byKey(const ValueKey('security-save'));
    await revealSecurity(t, f);
    await t.tap(f);
    await settleSecurity(t);
  }

  Future<void> choose(WidgetTester t, String key, String value) async {
    final group = find.byKey(ValueKey('security-check-$key'));
    await revealSecurity(t, group);
    await t.tap(find.descendant(of: group, matching: find.text(value)));
    await t.pumpAndSettle();
  }

  testWidgets(
    'account draft preserves alias and explicit answers through Back',
    (t) async {
      await home(t);
      expect(find.text('0 actions confirmed'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('security-add')));
      await settleSecurity(t);
      await enterNexText(
        t,
        find.byKey(const ValueKey('security-label')),
        'Personal email',
      );
      await choose(t, 'mfa', 'Done');
      await t.binding.handlePopRoute();
      await settleSecurity(t);
      expect(await store.list('account'), isEmpty);
      await t.tap(find.byKey(const ValueKey('security-add')));
      await settleSecurity(t);
      expect(
        t
            .widget<NexTextField>(find.byKey(const ValueKey('security-label')))
            .controller
            .text,
        'Personal email',
      );
      await save(t);
      final raw = (await store.list('account')).single.body;
      expect((raw['checks'] as Map)['mfa'], 'done');
      expect((raw['checks'] as Map)['unique'], 'unknown');
      expect(find.text('1 action confirmed'), findsOneWidget);
    },
  );
  testWidgets('unread checkpoints block editing and Retry recovers them', (
    t,
  ) async {
    await store.put('draft', 'account:new', {
      'v': 1,
      'base': '{}',
      'fields': {'label': 'Recovered'},
    });
    store.badDraft = true;
    await home(t);
    await t.tap(find.byKey(const ValueKey('security-add')));
    await settleSecurity(t);
    expect(find.byKey(const ValueKey('security-label')), findsNothing);
    store.badDraft = false;
    await t.tap(find.text('Try again'));
    await settleSecurity(t);
    expect(
      t
          .widget<NexTextField>(find.byKey(const ValueKey('security-label')))
          .controller
          .text,
      'Recovered',
    );
  });
  testWidgets('a failed save retains answers; retry creates one checklist', (
    t,
  ) async {
    await home(t);
    await t.tap(find.byKey(const ValueKey('security-add')));
    await settleSecurity(t);
    await enterNexText(
      t,
      find.byKey(const ValueKey('security-label')),
      'Email',
    );
    await choose(t, 'unique', 'Done');
    store.badWrite = true;
    await save(t);
    expect(await store.list('account'), isEmpty);
    expect(
      find.text('Could not save. Your input is still here; try again.'),
      findsOneWidget,
    );
    store.badWrite = false;
    await save(t);
    expect((await store.list('account')).length, 1);
    expect(
      ((await store.list('account')).single.body['checks'] as Map)['unique'],
      'done',
    );
  });
  testWidgets('a conflicting edit can be kept as a new checklist', (t) async {
    final raw = <String, Object?>{
      'v': 1,
      'label': 'Email',
      'checks': <String, Object?>{},
    };
    await store.put('account', 'a', raw);
    await home(t);
    await revealSecurity(t, find.text('Email'));
    await t.tap(find.text('Email'));
    await settleSecurity(t);
    await choose(t, 'mfa', 'Done');
    await store.put('account', 'a', {...raw, 'label': 'Newer'});
    await save(t);
    expect(
      find.textContaining('This record changed elsewhere.'),
      findsOneWidget,
    );
    final copy = find.text('Save as a new checklist');
    await revealSecurity(t, copy);
    await t.tap(copy);
    await settleSecurity(t);
    expect((await store.list('account')).length, 2);
    expect((await store.get('account', 'a'))!['label'], 'Newer');
  });
  testWidgets(
    'confirmed deletion offers a raw Undo without touching other accounts',
    (t) async {
      final raw = <String, Object?>{
        'v': 1,
        'label': 'Email',
        'checks': {'mfa': 'done'},
        'future': true,
      };
      await store.put('account', 'a', raw);
      await home(t);
      await revealSecurity(t, find.byTooltip('More actions'));
      await t.tap(find.byTooltip('More actions'));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete checklist'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(TextButton, 'Delete checklist'));
      await settleSecurity(t);
      expect(await store.get('account', 'a'), isNull);
      await t.tap(find.text('Undo'));
      await settleSecurity(t);
      expect(await store.get('account', 'a'), raw);
    },
  );
  testWidgets(
    'generator hides output and clears it on focus loss or options change',
    (t) async {
      await t.pumpWidget(app(SecurityGenerator(randomSource: () => Random(7))));
      await settleSecurity(t);
      final generate = find.byKey(const ValueKey('security-generate'));
      await revealSecurity(t, generate);
      await t.tap(generate);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('security-output')), findsNothing);
      await revealSecurity(t, find.byKey(const ValueKey('security-reveal')));
      await t.tap(find.byKey(const ValueKey('security-reveal')));
      await t.pumpAndSettle();
      expect(
        t
            .widget<Text>(find.byKey(const ValueKey('security-output')))
            .data!
            .length,
        24,
      );
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await t.pump();
      expect(find.byKey(const ValueKey('security-output')), findsNothing);
      expect(find.byKey(const ValueKey('security-copy')), findsNothing);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      await revealSecurity(t, generate);
      await t.tap(generate);
      await t.pumpAndSettle();
      await revealSecurity(t, find.text('32 characters'));
      await t.tap(find.text('32 characters'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('security-copy')), findsNothing);
    },
  );
  testWidgets(
    'secure-source failure removes older output and never offers Copy',
    (t) async {
      var fail = false;
      await t.pumpWidget(
        app(
          SecurityGenerator(
            randomSource: () {
              if (fail) throw UnsupportedError('no secure entropy');
              return Random(2);
            },
          ),
        ),
      );
      await settleSecurity(t);
      final generate = find.byKey(const ValueKey('security-generate'));
      await revealSecurity(t, generate);
      await t.tap(generate);
      await t.pumpAndSettle();
      fail = true;
      await revealSecurity(t, generate);
      await t.tap(generate);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('security-copy')), findsNothing);
      expect(
        find.text(
          'Could not securely generate a secret. Nothing was produced; try again.',
        ),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'explicit Copy sends only the generated value and never creates records',
    (t) async {
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await home(t);
      await t.tap(find.text('Create a password'));
      await settleSecurity(t);
      final generate = find.byKey(const ValueKey('security-generate'));
      await revealSecurity(t, generate);
      await t.tap(generate);
      await t.pumpAndSettle();
      final copy = find.byKey(const ValueKey('security-copy'));
      await revealSecurity(t, copy);
      await t.tap(copy);
      await settleSecurity(t);
      expect(copied?.length, 24);
      await t.binding.handlePopRoute();
      await settleSecurity(t);
      expect(await store.list('account'), isEmpty);
      expect(await store.list('draft'), isEmpty);
    },
  );
  testWidgets(
    'link report shows the parsed host, clears stale results and never saves input',
    (t) async {
      await home(t);
      await t.tap(find.text('Before you open a link'));
      await settleSecurity(t);
      final field = find.byKey(const ValueKey('security-url'));
      await revealSecurity(t, field);
      await enterNexText(
        t,
        field,
        'https://name:unused@evil.test/path?token=fixture',
      );
      final inspect = find.byKey(const ValueKey('security-inspect'));
      await revealSecurity(t, inspect);
      await t.tap(inspect);
      await t.pumpAndSettle();
      await revealSecurity(t, find.byKey(const ValueKey('security-host')));
      expect(
        t
            .widget<SelectableText>(find.byKey(const ValueKey('security-host')))
            .data,
        'evil.test',
      );
      await revealSecurity(t, field);
      await enterNexText(t, field, 'https://example.org');
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('security-host')), findsNothing);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await t.pump();
      expect(t.widget<NexTextField>(field).controller.text, isEmpty);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      await t.binding.handlePopRoute();
      await settleSecurity(t);
      expect(await store.list('draft'), isEmpty);
      expect(await store.list('account'), isEmpty);
    },
  );
  testWidgets(
    'a restored stable save id prevents duplicates after checkpoint cleanup fails',
    (t) async {
      const id = '11111111-1111-4111-8111-111111111111';
      await store.put('draft', 'account:new', {
        'v': 1,
        'base': '{}',
        'fields': {'label': 'Recovered', 'recordId': id},
      });
      store.badCleanup = true;
      await home(t);
      await t.tap(find.byKey(const ValueKey('security-add')));
      await settleSecurity(t);
      await save(t);
      expect((await store.list('account')).single.id, id);
      await t.tap(find.byKey(const ValueKey('security-add')));
      await settleSecurity(t);
      expect(
        t
            .widget<NexTextField>(find.byKey(const ValueKey('security-label')))
            .controller
            .text,
        isEmpty,
      );
      expect((await store.list('account')).length, 1);
    },
  );
}
