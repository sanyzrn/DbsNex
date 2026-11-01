import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/chat_history.dart';
import 'package:nex_client/platform/notification_text.dart';
import 'package:nex_client/widgets/ai_chat_sheet.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:nex_ui/widgets/nex_selection_highlight.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/nex_harness.dart';

void main() {
  testWidgets('beam runs once per expansion across rebuilds and remounts', (
    tester,
  ) async {
    var finished = 0;
    var pending = false;
    Future<void> show(int expansion, {bool mounted = true}) =>
        tester.pumpWidget(
          MaterialApp(
            home: mounted
                ? NexBorderBeam(
                    restsUnlit: true,
                    laps: 1,
                    playOnMount: pending,
                    token: expansion,
                    onFinished: () {
                      pending = false;
                      finished++;
                    },
                    child: const SizedBox(width: 200, height: 100),
                  )
                : const SizedBox(),
          ),
        );
    await show(0);
    await tester.pump(const Duration(seconds: 5));
    expect(finished, 0);
    pending = true;
    await show(1);
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(finished, 1);
    await show(1);
    await tester.pump(const Duration(seconds: 4));
    expect(finished, 1);
    await show(1, mounted: false);
    await show(1);
    await tester.pump(const Duration(seconds: 4));
    expect(finished, 1);
    pending = true;
    await show(2);
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(finished, 2);
  });
  testWidgets('beam fades smoothly in its final 320 milliseconds', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: NexBorderBeam(
          restsUnlit: true,
          laps: 1,
          child: SizedBox(width: 200, height: 100),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 3440));
    final dynamic beam = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .firstWhere((p) => p.painter.runtimeType.toString() == '_BeamPainter')
        .painter;
    expect(beam.opacity as double, closeTo(0.5, 0.02));
    await tester.pump(const Duration(milliseconds: 161));
    expect(
      tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .where((p) => p.painter.runtimeType.toString() == '_BeamPainter'),
      isEmpty,
    );
  });
  test('highlight levels mixed font runs without filling bidi gaps', () {
    final rects = nexLevelSelectionRects([
      const Rect.fromLTRB(0, 0, 40, 20),
      const Rect.fromLTRB(40, 4, 60, 17),
      const Rect.fromLTRB(90, 2, 120, 19),
      const Rect.fromLTRB(0, 30, 80, 50),
    ]);
    expect(rects.take(3).map((r) => r.top), everyElement(0));
    expect(rects.take(3).map((r) => r.bottom), everyElement(20));
    expect(rects.singleWhere((r) => r.left == 40).right, 60);
    expect(rects.singleWhere((r) => r.right == 120).left, 90);
    expect(rects.last, const Rect.fromLTRB(0, 30, 80, 50));
  });
  testWidgets('level highlights preserve multilingual selection and copy', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String;
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
    const text = 'متن فارسی با English و ۱۲۳\nSecond line\nخط آخر';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NexSelectionArea(
            levelHighlight: true,
            child: NexTextSurface(text),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final region = tester.state<SelectableRegionState>(
      find.byType(SelectableRegion),
    );
    region.selectAll(SelectionChangedCause.toolbar);
    await tester.pumpAndSettle();
    region.contextMenuButtonItems
        .singleWhere((b) => b.type == ContextMenuButtonType.copy)
        .onPressed!();
    await tester.pump();
    expect(copied, text);

    const markdown = 'متن فارسی با **English** و ۱۲۳\n\nSecond line\n\nخط آخر';
    await tester.pumpWidget(const SizedBox());
    copied = null;
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NexSelectionArea(
            key: ValueKey('markdown'),
            levelHighlight: true,
            child: NexMarkdown(markdown, selectable: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final formatted = tester.state<SelectableRegionState>(
      find.byType(SelectableRegion),
    );
    formatted.selectAll(SelectionChangedCause.toolbar);
    await tester.pumpAndSettle();
    formatted.contextMenuButtonItems
        .singleWhere((b) => b.type == ContextMenuButtonType.copy)
        .onPressed!();
    await tester.pump();
    expect(copied, text);
  });
  testWidgets(
    'assistant copies inline code alone and still copies the whole reply',
    (tester) async {
      final h = await NexTestHarness.create();
      final history = ChatHistory(await SharedPreferences.getInstance());
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied =
                (call.arguments as Map<Object?, Object?>)['text'] as String;
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
      const reply = '🔗 آدرس وب‌سایت `inference.dahl.global` است، حاج سعید.';
      try {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: AiChatSheet(
                preferences: h.preferences,
                services: h.services,
                history: history,
                resume: ChatThread(
                  id: 'inline-code',
                  updatedAt: DateTime.now(),
                  messages: const [
                    ChatMessage(role: ChatRole.assistant, content: reply),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final paragraph = tester.renderObject<RenderParagraph>(
          find
              .byWidgetPredicate(
                (w) =>
                    w is RichText &&
                    w.text.toPlainText().contains('inference.dahl.global'),
              )
              .first,
        );
        final start = paragraph.text.toPlainText().indexOf(
          'inference.dahl.global',
        );
        final box = paragraph
            .getBoxesForSelection(
              TextSelection(
                baseOffset: start,
                extentOffset: start + 'inference.dahl.global'.length,
              ),
            )
            .first;
        await tester.tapAt(paragraph.localToGlobal(box.toRect().center));
        await tester.pumpAndSettle();
        expect(copied, 'inference.dahl.global');
        expect(
          find.text(
            AppLocalizations.of(
              tester.element(find.byType(AiChatSheet)),
            ).copied,
          ),
          findsOneWidget,
        );
        await tester.tap(find.byIcon(Icons.copy_rounded).first);
        await tester.pumpAndSettle();
        expect(copied, reply);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        history.dispose();
        await h.dispose();
      }
    },
  );
  test('notification paragraphs follow their content and escape HTML', () {
    expect(
      nexAndroidNotificationText('🔔 ۱۲۳ یادآوری'),
      contains('\u200f🔔 ۱۲۳ یادآوری'),
    );
    final body = nexAndroidNotificationText('English <tag> & text\nمتن فارسی');
    expect(body, contains('text-align:start'));
    expect(
      body,
      contains('\u200eEnglish &lt;tag&gt; &amp; text<br>\u200fمتن فارسی'),
    );
    expect(nexAndroidNotificationText(''), '');
    final style = nexNotificationStyle('متن طولانی') as BigTextStyleInformation;
    expect(
      style.htmlFormatBigText &&
          style.htmlFormatContent &&
          style.htmlFormatTitle,
      isTrue,
    );
    expect(style.bigText, contains('\u200fمتن طولانی'));
    expect(nexNotificationStyle(null).htmlFormatTitle, isTrue);
  });
}
