import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/widgets/nex_text_field.dart';
import 'package:nex_client/widgets/note_editor_sheet.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final locale in ['en', 'fa']) {
    for (final reduced in [false, true]) {
      for (final save in [true, false]) {
        testWidgets(
          '$locale reduced=$reduced save=$save: text and selection survive resizing',
          (tester) async {
            // The note editor is the framework's own now, so a resize is
            // just a layout change: full screen and back must keep the
            // editor element, the text and the selection exactly as they
            // were — and no platform view is created anywhere in the sheet.
            SharedPreferences.setMockInitialValues({});
            final prefs = await NexPreferences.load();
            var creates = 0;
            final events = <String>[];
            debugDefaultTargetPlatformOverride = TargetPlatform.android;
            tester.view.physicalSize = const Size(390, 844);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            final messenger = TestDefaultBinaryMessengerBinding
                .instance
                .defaultBinaryMessenger;
            messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
              call,
            ) async {
              if (call.method == 'create') creates++;
              return null;
            });
            messenger.setMockMethodCallHandler(
              const MethodChannel('nex/os_capture'),
              (call) async {
                events.add(call.method);
                return null;
              },
            );
            addTearDown(() {
              messenger.setMockMethodCallHandler(
                SystemChannels.platform_views,
                null,
              );
              messenger.setMockMethodCallHandler(
                const MethodChannel('nex/os_capture'),
                null,
              );
            });
            try {
              String? saved;
              final l10n = lookupAppLocalizations(Locale(locale));
              await tester.pumpWidget(
                MaterialApp(
                  locale: Locale(locale),
                  theme: locale == 'fa' ? nexDarkTheme() : nexLightTheme(),
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      disableAnimations: reduced,
                      textScaler: const TextScaler.linear(1.6),
                    ),
                    child: child!,
                  ),
                  home: Builder(
                    builder: (context) => Scaffold(
                      body: TextButton(
                        onPressed: () async {
                          saved = await NoteEditorSheet.show(
                            context,
                            initial: 'Original متن\nSecond line',
                            preferences: prefs,
                          );
                        },
                        child: const Text('open'),
                      ),
                    ),
                  ),
                ),
              );
              await tester.tap(find.text('open'));
              await tester.pumpAndSettle();
              expect(creates, 0, reason: 'the editor is the framework\'s own');
              final field = find.byType(NexTextField);
              final state = tester.state(field);
              final controller = tester.widget<NexTextField>(field).controller;
              final editor = find.descendant(
                of: field,
                matching: find.byType(EditableText),
              );
              const edited =
                  '  متن ویرایش‌شده\nEnglish text stays visible.\nآخر متن  ';
              await tester.tap(editor);
              await tester.pump();
              await tester.enterText(editor, edited);
              controller.selection = const TextSelection(
                baseOffset: 3,
                extentOffset: 8,
              );
              await tester.pumpAndSettle();
              tester.view.viewInsets = const FakeViewPadding(bottom: 300);
              await tester.pumpAndSettle();
              for (var i = 0; i < 4; i++) {
                await tester.tap(find.byTooltip(l10n.editorFullScreen));
                await tester.pumpAndSettle();
                expect(tester.state(field), same(state));
                await tester.tap(find.byTooltip(l10n.editorSmaller));
                await tester.pumpAndSettle();
                expect(tester.state(field), same(state));
                expect(controller.text, edited);
                expect(
                  controller.selection,
                  const TextSelection(baseOffset: 3, extentOffset: 8),
                );
                expect(tester.getSize(field).height, greaterThan(40));
                expect(creates, 0);
              }
              if (save) {
                await tester.tap(find.byTooltip(l10n.save));
                await tester.pumpAndSettle();
                expect(saved, edited);
              } else {
                await tester.tap(find.byTooltip(l10n.cancel));
                await tester.pumpAndSettle();
                await tester.tap(find.text(l10n.discard));
                await tester.pumpAndSettle();
                expect(saved, isNull);
              }
              expect(
                events,
                contains('hideKeyboard'),
                reason: 'route teardown still hides through the host',
              );
              expect(tester.takeException(), isNull);
              await tester.pumpWidget(const SizedBox());
            } finally {
              debugDefaultTargetPlatformOverride = null;
              prefs.dispose();
            }
          },
        );
      }
    }
  }
}
