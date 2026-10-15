import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:nex_core/nex_core.dart';

import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/note_detail_sheet.dart';

import 'support/nex_harness.dart';

/// A note's body is rendered where its writer formatted it and left exactly as
/// typed where they did not — the same predicate the card strips by, so the
/// two never disagree about what a note says.
void main() {
  late NexTestHarness harness;
  late NexServices services;
  late NexPreferences preferences;

  setUp(() async {
    harness = await NexTestHarness.create(
      name: 'nex_formatting_',
      onboarded: false,
    );
    services = harness.services;
    preferences = harness.preferences;
    preferences = await NexPreferences.load();
  });

  tearDown(() => harness.dispose());

  Future<void> openText(
    WidgetTester tester,
    String body, {
    String language = 'en',
  }) async {
    final note = (await services.captureText(body))!;
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: NoteDetailSheet(
            services: services,
            noteId: note.id,
            preferences: preferences,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a formatted note is rendered, markers and all gone', (
    tester,
  ) async {
    await openText(tester, 'the **urgent** one');

    expect(find.byType(NexMarkdown), findsOneWidget);
    expect(find.textContaining('**'), findsNothing);
  });

  for (final language in ['en', 'fa']) {
    testWidgets('bold preserves the writer\'s Enter ($language)', (
      tester,
    ) async {
      const source = 'سلام\nحالت چطوره؟';
      final formatted = NexTextFormatting.toggleInline(
        source,
        0,
        4,
        NexInlineFormat.bold,
      );
      expect(formatted.text, '**سلام**\nحالت چطوره؟');
      await openText(tester, formatted.text, language: language);
      final rich = find.byWidgetPredicate(
        (w) =>
            w is RichText && w.text.toPlainText().contains('سلام\nحالت چطوره؟'),
      );
      expect(rich, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(rich);
      final first = paragraph
          .getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 4),
          )
          .first;
      final second = paragraph
          .getBoxesForSelection(
            const TextSelection(baseOffset: 5, extentOffset: 9),
          )
          .first;
      expect(second.top, greaterThan(first.top));
    });
  }

  testWidgets('an ordinary sentence is shown exactly as typed', (tester) async {
    // The cost of getting this wrong is a character the writer put there being
    // eaten: `2 * 3 * 4` through a Markdown parser loses two operators.
    await openText(tester, '2 * 3 * 4');

    expect(find.byType(NexMarkdown), findsNothing);
    expect(find.byType(NexTextSurface), findsWidgets);
    expect(find.textContaining('2 * 3 * 4'), findsOneWidget);
  });

  testWidgets('a Persian list is rendered as a list', (tester) async {
    await openText(tester, '- مورد اول\n- مورد دوم');

    expect(find.byType(NexMarkdown), findsOneWidget);
    expect(find.textContaining('مورد اول'), findsWidgets);
  });

  for (final language in ['en', 'fa']) {
    for (final markdown in [false, true]) {
      testWidgets(
        '$language ${markdown ? 'formatted' : 'plain'} links open and have a two-action hold menu',
        (tester) async {
          const href = 'https://realmetaverse.ir/cipher/';
          final launches = <MethodCall>[];
          final copied = <String>[];
          const launcher = MethodChannel('plugins.flutter.io/url_launcher');
          final messenger = tester.binding.defaultBinaryMessenger;
          messenger.setMockMethodCallHandler(launcher, (call) async {
            launches.add(call);
            return true;
          });
          messenger.setMockMethodCallHandler(SystemChannels.platform, (
            call,
          ) async {
            if (call.method == 'Clipboard.setData') {
              copied.add((call.arguments as Map)['text'] as String);
            }
            return null;
          });
          addTearDown(() {
            messenger.setMockMethodCallHandler(launcher, null);
            messenger.setMockMethodCallHandler(SystemChannels.platform, null);
          });
          final label = markdown ? 'امکانات' : href;
          await openText(
            tester,
            'افزودن امکانات اکو\n\n${markdown ? '[$label]($href)' : href}',
            language: language,
          );
          final rich = find
              .byWidgetPredicate(
                (w) => w is RichText && w.text.toPlainText().contains(label),
              )
              .last;
          final paragraph = tester.renderObject<RenderParagraph>(rich);
          final index = paragraph.text.toPlainText().indexOf(label);
          final box = paragraph
              .getBoxesForSelection(
                TextSelection(baseOffset: index, extentOffset: index + 1),
              )
              .first;
          final at = paragraph.localToGlobal(box.toRect().center);
          await tester.tapAt(at);
          await tester.pumpAndSettle();
          expect(launches.single.method, 'launch');
          expect((launches.single.arguments as Map)['url'], href);
          expect((launches.single.arguments as Map)['useWebView'], isFalse);
          launches.clear();
          await tester.longPressAt(at);
          await tester.pumpAndSettle();
          expect(launches, isEmpty);
          expect(
            find.byWidgetPredicate((w) => w is PopupMenuItem),
            findsNWidgets(2),
          );
          final open = language == 'fa' ? 'باز کردن لینک' : 'Open link';
          final copy = language == 'fa' ? 'کپی لینک' : 'Copy link';
          expect(find.text(open), findsOneWidget);
          await tester.tap(find.text(copy));
          await tester.pumpAndSettle();
          expect(copied, [href]);
          expect(launches, isEmpty);
          await tester.longPressAt(at);
          await tester.pumpAndSettle();
          await tester.tap(find.text(open));
          await tester.pumpAndSettle();
          expect((launches.single.arguments as Map)['url'], href);
        },
      );
    }
  }

  group('a tapped code span is copied', () {
    /// Everything the platform channel was asked to put on the clipboard.
    List<String> watchClipboard(WidgetTester tester) {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
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
      return copied;
    }

    testWidgets('one touch takes the mono part', (tester) async {
      // A note that is only the span, so the tap can be aimed by finding its
      // text. Inside a sentence the renderer merges every inline run into one
      // rich text, and hitting the span would mean computing an offset into a
      // paragraph — which tests the arithmetic, not the wiring.
      final copied = watchClipboard(tester);
      await openText(tester, '`flutter test`');

      await tester.tap(find.text('flutter test', findRichText: true));
      await tester.pumpAndSettle();

      expect(copied, ['flutter test']);
    });

    testWidgets('a fenced block is left as a block', (tester) async {
      // It already scrolls sideways, and turning the whole of it into one tap
      // target would take that away.
      final copied = watchClipboard(tester);
      await openText(tester, '```\nfinal x = 1;\n```');

      await tester.tap(
        find.textContaining('final x = 1;', findRichText: true).first,
      );
      await tester.pumpAndSettle();

      expect(copied, isEmpty);
    });
  });
}
