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
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final locale in ['en', 'fa']) {
    for (final reduced in [false, true]) {
      for (final save in [true, false]) {
        testWidgets(
          '$locale reduced=$reduced save=$save: native text and selection survive resizing',
          (tester) async {
            SharedPreferences.setMockInitialValues({});
            final prefs = await NexPreferences.load();
            var creates = 0;
            var id = -1;
            final events = <String>[];
            NexTextField.native = true;
            debugDefaultTargetPlatformOverride = TargetPlatform.android;
            tester.view.physicalSize = const Size(390, 844);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            messenger.setMockMethodCallHandler(
              const MethodChannel('nex/os_capture'),
              (call) async {
                events.add(call.method);
                return null;
              },
            );
            messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
              call,
            ) async {
              if (call.method == 'create') {
                creates++;
                final args = call.arguments as Map;
                id = args['id'] as int;
                final initial =
                    const StandardMessageCodec().decodeMessage(
                          ByteData.sublistView(args['params'] as Uint8List),
                        )
                        as Map;
                expect(initial['expands'], isTrue);
                messenger.setMockMethodCallHandler(
                  MethodChannel('nex/edit_text/$id'),
                  (call) async {
                    events.add(call.method);
                    if (call.method == 'update') {
                      expect((call.arguments as Map)['expands'], isTrue);
                    }
                    return null;
                  },
                );
                return id;
              }
              if (call.method == 'resize') {
                final args = call.arguments as Map;
                return {'width': args['width'], 'height': args['height']};
              }
              return null;
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
              expect(creates, 1);
              const edited =
                  '  متن ویرایش‌شده\nEnglish text stays visible.\nآخر متن  ';
              await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
                'nex/edit_text/$id',
                const StandardMethodCodec().encodeMethodCall(
                  const MethodCall('changed', {
                    'text': edited,
                    'start': 3,
                    'end': 8,
                  }),
                ),
                (_) {},
              );
              await tester.pumpAndSettle();
              final field = find.byType(NexTextField);
              final state = tester.state(field);
              final controller = tester.widget<NexTextField>(field).controller;
              tester.widget<NexTextField>(field).focusNode!.requestFocus();
              tester.view.viewInsets = const FakeViewPadding(bottom: 300);
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
                expect(creates, 1);
              }
              if (save) {
                await tester.tap(find.text(l10n.save));
                await tester.pumpAndSettle();
                expect(saved, edited);
              } else {
                await tester.tap(find.text(l10n.cancel));
                await tester.pumpAndSettle();
                await tester.tap(find.text(l10n.discard));
                await tester.pumpAndSettle();
                expect(saved, isNull);
              }
              expect(
                events.lastWhere((e) => e == 'focus' || e == 'hideKeyboard'),
                'hideKeyboard',
              );
              expect(tester.takeException(), isNull);
              await tester.pumpWidget(const SizedBox());
            } finally {
              debugDefaultTargetPlatformOverride = null;
              NexTextField.native = false;
              messenger.setMockMethodCallHandler(
                SystemChannels.platform_views,
                null,
              );
              messenger.setMockMethodCallHandler(
                const MethodChannel('nex/os_capture'),
                null,
              );
              if (id >= 0) {
                messenger.setMockMethodCallHandler(
                  MethodChannel('nex/edit_text/$id'),
                  null,
                );
              }
              prefs.dispose();
            }
          },
        );
      }
    }
  }
}
