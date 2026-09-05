import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/text_format_menu.dart';

/// The selection menu is where a phone already puts things done *to a
/// selection*, so that is where Nex puts bold and the rest.
///
/// The menu is built directly and its buttons invoked directly, rather than
/// driven through a real long-press. Two reasons, both about testing this file
/// and not Flutter: the selection overlay only exists after a gesture the test
/// would have to fake, and Android paginates a long toolbar behind an
/// overflow, so which buttons a tap can reach depends on the width of the test
/// surface. What belongs here is that the right items are offered for the
/// right selection, and that pressing one edits the field.
void main() {
  late TextEditingController controller;

  setUp(() => controller = TextEditingController());
  tearDown(() => controller.dispose());

  Future<void> pumpField(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextField(
              controller: controller,
              maxLines: null,
              contextMenuBuilder: nexFormatContextMenuBuilder(context),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Puts the selection on [start]..[end].
  Future<void> select(WidgetTester tester, int start, int end) async {
    final state = tester.state<EditableTextState>(find.byType(EditableText));
    state.userUpdateTextEditingValue(
      state.textEditingValue.copyWith(
        selection: TextSelection(baseOffset: start, extentOffset: end),
      ),
      SelectionChangedCause.tap,
    );
    await tester.pump();
  }

  /// The menu this field would show for whatever is selected right now.
  List<ContextMenuButtonItem> itemsOf(WidgetTester tester) {
    final context = tester.element(find.byType(TextField));
    final state = tester.state<EditableTextState>(find.byType(EditableText));
    final menu =
        nexFormatContextMenuBuilder(context)(context, state)
            as AdaptiveTextSelectionToolbar;
    return menu.buttonItems ?? const [];
  }

  Future<void> press(WidgetTester tester, String label) async {
    itemsOf(tester).firstWhere((item) => item.label == label).onPressed!();
    await tester.pumpAndSettle();
  }

  testWidgets('a selection is offered the formats, alongside Cut and Copy', (
    tester,
  ) async {
    await pumpField(tester);
    await tester.enterText(find.byType(TextField), 'one two three');
    await select(tester, 4, 7);

    final labels = itemsOf(tester).map((item) => item.label).toList();
    expect(labels, containsAll(<String>['Bold', 'Italic', 'Mono']));
    expect(labels, containsAll(<String>['Strikethrough', 'Quote', 'Link']));
    expect(labels, contains('Regular'));
    // Appended to the platform's own, never substituted for them. The
    // platform's items carry a type and no label — the toolbar localises them
    // at render time — so they are checked by type.
    expect(
      itemsOf(tester).map((item) => item.type),
      contains(ContextMenuButtonType.copy),
    );
  });

  testWidgets('what other apps put on the menu is left off it', (tester) async {
    // Android lets any installed app register an `ACTION_PROCESS_TEXT`
    // activity and have its name appear on every selection menu on the phone,
    // and Flutter forwards all of them. On a device with a few assistants
    // installed that was Ask Copilot, Ask ChatGPT, Translate, Read aloud, Ask
    // Grok, Ask Perplexity, Ask Kimi and Ask DeepSeek, stacked above Bold and
    // pushing Nex's own formatting onto a second page of the overflow.
    //
    // Faked at the channel Flutter asks over, so this is the real mechanism
    // and not a stand-in for it.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.processText, (call) async {
          if (call.method != 'ProcessText.queryTextActions') return null;
          return <String, String>{
            'com.other/AskChatGPT': 'Ask ChatGPT',
            'com.other/Translate': 'Translate',
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.processText, null),
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await pumpField(tester);
    await tester.enterText(find.byType(TextField), 'one two three');
    await select(tester, 4, 7);
    await tester.pumpAndSettle();

    // The precondition, asserted rather than assumed. Without it the case
    // below would pass on a host that never had those actions in the first
    // place, which is every host — and would go on passing after the filter
    // was taken back out.
    final state = tester.state<EditableTextState>(find.byType(EditableText));
    expect(
      state.contextMenuButtonItems.map((item) => item.label),
      containsAll(<String>['Ask ChatGPT', 'Translate']),
      reason: 'the field really is being offered them',
    );

    // And the menu Nex builds is not.
    final labels = itemsOf(tester).map((item) => item.label).toList();
    expect(labels, isNot(contains('Ask ChatGPT')));
    expect(labels, isNot(contains('Translate')));

    // Without taking Cut and Copy with them. A text field without those is a
    // broken text field, whatever else is on the menu.
    final types = itemsOf(tester).map((item) => item.type).toList();
    expect(types, contains(ContextMenuButtonType.copy));
    expect(types, contains(ContextMenuButtonType.cut));
    expect(labels, contains('Bold'));
  });

  testWidgets('a caret with nothing selected is offered none of them', (
    tester,
  ) async {
    // Offering "Bold" for a caret is offering to embolden nothing.
    await pumpField(tester);
    await tester.enterText(find.byType(TextField), 'one two three');
    await select(tester, 5, 5);

    expect(itemsOf(tester).map((item) => item.label), isNot(contains('Bold')));
  });

  testWidgets('pressing a format writes it into the field', (tester) async {
    await pumpField(tester);
    await tester.enterText(find.byType(TextField), 'one two three');
    await select(tester, 4, 7);
    await press(tester, 'Bold');

    expect(controller.text, 'one **two** three');
    // And the selection is still on the word, so the next press is an undo
    // rather than a second pair of asterisks.
    expect(controller.selection.textInside(controller.text), 'two');
  });

  testWidgets('pressing the same format again takes it back off', (
    tester,
  ) async {
    await pumpField(tester);
    await tester.enterText(find.byType(TextField), 'one two three');
    await select(tester, 4, 7);
    await press(tester, 'Bold');

    final where = controller.selection;
    await select(tester, where.start, where.end);
    await press(tester, 'Bold');

    expect(controller.text, 'one two three');
  });

  testWidgets('Quote marks the whole line, not half of it', (tester) async {
    await pumpField(tester);
    await tester.enterText(find.byType(TextField), 'one\ntwo\nthree');
    await select(tester, 5, 6);
    await press(tester, 'Quote');

    expect(controller.text, 'one\n> two\nthree');
  });

  testWidgets('Regular takes the formatting back off', (tester) async {
    await pumpField(tester);
    await tester.enterText(find.byType(TextField), 'a **b** and `c`');
    await select(tester, 0, 15);
    await press(tester, 'Regular');

    expect(controller.text, 'a b and c');
  });
}
