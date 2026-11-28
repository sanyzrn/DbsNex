import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/capture_sheet.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';
import 'support/text_input.dart';

/// 2.9.0, step 6: Paste lives in the primary button, and only when it can do
/// something. The field keeps its whole width; an empty box with a clipboard
/// offers Paste in Send's place; pressing it inserts and never saves; the
/// next frame with words in the box is Send again.
void main() {
  late NexTestHarness harness;
  late int reads;
  late int asks;
  late bool hasStrings;
  late String clipboard;
  Completer<String?>? pendingRead;

  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_capture_paste_');
    reads = 0;
    asks = 0;
    hasStrings = true;
    clipboard = '  new\nline  ';
    pendingRead = null;
  });

  tearDown(() => harness.dispose());

  Future<void> open(
    WidgetTester tester, {
    CaptureKind kind = CaptureKind.note,
    bool reducedMotion = false,
  }) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.hasStrings') {
          asks++;
          return {'value': hasStrings};
        }
        if (call.method == 'Clipboard.getData') {
          reads++;
          final pending = pendingRead;
          if (pending != null) return {'text': await pending.future};
          return {'text': clipboard};
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
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: nexLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: reducedMotion),
          child: child!,
        ),
        home: Scaffold(
          body: CaptureSheet(
            services: harness.services,
            preferences: harness.preferences,
            initialKind: kind,
            onCamera: () {},
            onGallery: () {},
            onFile: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final pasteIcon = find.byKey(const ValueKey('paste'));
  final sendIcon = find.byKey(const ValueKey('up'));
  final sendButton = find.byKey(const ValueKey('capture-send'));
  TextEditingController field(WidgetTester tester) => nexInputController(
    tester,
    find.descendant(of: find.byType(CaptureSheet), matching: nexInputs()),
  );

  testWidgets('an empty box offers Paste, and pasting saves nothing', (
    tester,
  ) async {
    await open(tester);
    expect(pasteIcon, findsOneWidget);
    expect(sendIcon, findsNothing);
    expect(
      reads,
      0,
      reason:
          'the words are read only when Paste is pressed or a link needs '
          'to know what they are',
    );

    await tester.tap(sendButton);
    await tester.pumpAndSettle();

    expect(field(tester).text, clipboard);
    expect(
      find.byType(CaptureSheet),
      findsOneWidget,
      reason: 'Paste inserts; it never closes the sheet',
    );
    // The words became the note they would have become by typing (ADR-002:
    // there is no Save). What Paste must not do is send: the sheet is still
    // open above.
    final notes = await harness.services.timeline(limit: 5);
    expect(notes.single.content, clipboard);
    expect(pasteIcon, findsNothing);
    expect(sendIcon, findsOneWidget);
    expect(reads, 1);
  });

  testWidgets('typing and clearing move the button, and clearing asks again', (
    tester,
  ) async {
    await open(tester);
    final fieldFinder = find.descendant(
      of: find.byType(CaptureSheet),
      matching: nexInputs(),
    );
    final before = asks;

    await enterNexText(tester, fieldFinder, 'typed');
    await tester.pumpAndSettle();
    expect(pasteIcon, findsNothing);
    expect(sendIcon, findsOneWidget);

    await enterNexText(tester, fieldFinder, '');
    await tester.pumpAndSettle();
    expect(pasteIcon, findsOneWidget);
    expect(
      asks,
      greaterThan(before),
      reason: 'an emptied box asks the clipboard again',
    );
  });

  testWidgets('an empty clipboard leaves Send in place', (tester) async {
    hasStrings = false;
    await open(tester);
    expect(pasteIcon, findsNothing);
    expect(sendIcon, findsOneWidget);
    expect(reads, 0);
  });

  testWidgets('a link box offers Paste only for an address', (tester) async {
    clipboard = 'definitely not a url';
    await open(tester, kind: CaptureKind.link);
    expect(pasteIcon, findsNothing);
    expect(reads, 1, reason: 'a link box asks what the words are');

    clipboard = 'https://example.com/a';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(pasteIcon, findsOneWidget);

    await tester.tap(sendButton);
    await tester.pumpAndSettle();
    expect(field(tester).text, 'https://example.com/a');
  });

  testWidgets('a checklist takes any words, not only an address', (
    tester,
  ) async {
    await open(tester, kind: CaptureKind.checklist);
    expect(pasteIcon, findsOneWidget);
    expect(reads, 0);
    await tester.tap(sendButton);
    await tester.pumpAndSettle();
    expect(field(tester).text, clipboard);
  });

  testWidgets('two quick taps insert once', (tester) async {
    pendingRead = Completer<String?>();
    await open(tester);
    await tester.tap(sendButton);
    await tester.pump();
    await tester.tap(sendButton);
    await tester.pump();
    pendingRead!.complete('once');
    await tester.pumpAndSettle();
    expect(field(tester).text, 'once');
  });

  testWidgets('a late clipboard answer cannot undo a newer one', (
    tester,
  ) async {
    var calls = 0;
    final first = Completer<Map<String, Object>?>();
    late bool held;
    held = true;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.hasStrings') {
          calls++;
          if (held) {
            held = false;
            return first.future;
          }
          return {'value': true};
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
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: nexLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CaptureSheet(
            services: harness.services,
            preferences: harness.preferences,
            onCamera: () {},
            onGallery: () {},
            onFile: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(pasteIcon, findsNothing);

    // A newer answer says there are words; the first one is still in flight.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(calls, greaterThan(1));
    expect(pasteIcon, findsOneWidget);

    // The old answer lands last, and must not take Paste away again.
    first.complete({'value': false});
    await tester.pumpAndSettle();
    expect(pasteIcon, findsOneWidget);
  });

  testWidgets('the button does not change size when Paste arrives', (
    tester,
  ) async {
    await open(tester, reducedMotion: true);
    final size = tester.getSize(sendButton);
    expect(size.width, 60);
    expect(size.height, 60);
    await tester.tap(sendButton);
    await tester.pump();
    expect(tester.getSize(sendButton), size);
    await tester.pumpAndSettle();
    expect(tester.getSize(sendButton), size);
  });
}
