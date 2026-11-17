import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/security_tools/account_editor.dart';
import 'package:nex_client/modules/security_tools/codec_screen.dart';
import 'package:nex_client/modules/security_tools/account_model.dart';
import 'package:nex_client/modules/security_tools/account_repository.dart';
import 'package:nex_client/modules/security_tools/incident_screen.dart';
import 'package:nex_client/modules/security_tools/link_screen.dart';
import 'package:nex_client/modules/security_tools/secret_screen.dart';
import 'package:nex_client/modules/security_tools/security_home.dart';

import '../../support/nex_harness.dart';
import 'security_widget_test.dart' show settleSecurity, revealSecurity;

void main() {
  for (final fa in [true, false]) {
    for (final dark in [true, false]) {
      for (final compact in [true, false]) {
        for (final scene in [
          'home',
          'codec',
          'generator',
          'link',
          'account',
          'incident',
        ]) {
          testWidgets('$scene fa:$fa dark:$dark compact:$compact', (t) async {
            final h = await NexTestHarness.create(name: 'security_render_');
            addTearDown(h.dispose);
            t.view.physicalSize = compact
                ? const Size(320, 640)
                : const Size(390, 844);
            t.view.devicePixelRatio = 1;
            addTearDown(t.view.reset);
            final store = NexModuleStore(h.services, 'security_tools');
            final raw = <String, Object?>{
              'v': 1,
              'label': fa ? 'ایمیل شخصی' : 'Personal email',
              'checks': {
                'unique': 'done',
                'mfa': 'todo',
                'recovery': 'unknown',
                'sessions': 'unknown',
              },
            };
            await store.put('account', 'a', raw);
            await t.runAsync(() async {
              for (final p in [
                ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
                ('Inter', 'assets/fonts/Inter-subset.ttf'),
                ('Vazirmatn', 'assets/fonts/VazirmatnVariable.ttf'),
              ]) {
                await (FontLoader(p.$1)..addFont(rootBundle.load(p.$2))).load();
              }
            });
            final boundary = GlobalKey();
            final page = switch (scene) {
              'home' => SecurityHome(store: store),
              'codec' => const SecurityCodecScreen(),
              'generator' => SecurityGenerator(randomSource: () => Random(7)),
              'link' => const SecurityLinkScreen(),
              'account' => SecurityAccountEditor(
                repo: AccountRepository(store),
                account: SecurityAccount('a', raw),
              ),
              _ => const SecurityIncidentScreen(),
            };
            await t.pumpWidget(
              RepaintBoundary(
                key: boundary,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  locale: Locale(fa ? 'fa' : 'en'),
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  theme: dark
                      ? nexSoftDarkTheme(fontFamily: fa ? 'Vazirmatn' : 'Inter')
                      : nexSoftLightTheme(
                          fontFamily: fa ? 'Vazirmatn' : 'Inter',
                        ),
                  builder: (c, child) => MediaQuery(
                    data: MediaQuery.of(c).copyWith(
                      textScaler: TextScaler.linear(compact ? 2 : 1),
                      disableAnimations: compact,
                    ),
                    child: child!,
                  ),
                  home: page,
                ),
              ),
            );
            await settleSecurity(t);
            if (scene == 'codec') {
              final field = find.byKey(const ValueKey('security-codec-input'));
              await revealSecurity(t, field);
              await t.enterText(field, fa ? 'سلام 👋' : 'Hello 👋');
              final run = find.byKey(const ValueKey('security-codec-run'));
              await revealSecurity(t, run);
              await t.tap(run);
              await t.pumpAndSettle();
              await revealSecurity(
                t,
                find.byKey(const ValueKey('security-codec-output')),
              );
            }
            if (scene == 'generator') {
              final generate = find.byKey(const ValueKey('security-generate'));
              await revealSecurity(t, generate);
              await t.tap(generate);
              await t.pumpAndSettle();
              await revealSecurity(
                t,
                find.byKey(const ValueKey('security-copy')),
              );
              expect(
                find.byKey(const ValueKey('security-output')),
                findsNothing,
              );
            } else if (scene == 'link') {
              final field = find.byKey(const ValueKey('security-url'));
              await revealSecurity(t, field);
              await t.enterText(
                field,
                'https://accounts.example.org@review.example.test/login?next=%2Fhome',
              );
              final expected = find.byKey(const ValueKey('security-expected'));
              await revealSecurity(t, expected);
              await t.enterText(expected, 'example.org');
              final inspect = find.byKey(const ValueKey('security-inspect'));
              await revealSecurity(t, inspect);
              await t.tap(inspect);
              await t.pumpAndSettle();
              await revealSecurity(
                t,
                find.byKey(const ValueKey('security-host')),
              );
            }
            expect(t.takeException(), isNull);
            const out = String.fromEnvironment('NEX_CAPTURE');
            if (out.isNotEmpty && !compact && fa == dark) {
              await t.runAsync(() async {
                final image =
                    await (boundary.currentContext!.findRenderObject()!
                            as RenderRepaintBoundary)
                        .toImage();
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                Directory(out).createSync(recursive: true);
                await File(
                  '$out/security_${scene}_${fa ? 'fa_dark' : 'en_light'}.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
            if (scene == 'account') {
              await revealSecurity(
                t,
                find.byKey(const ValueKey('security-save')),
              );
            } else if (scene == 'generator') {
              await revealSecurity(
                t,
                find.text(fa ? 'عبارت عبور' : 'Passphrase'),
              );
              await t.tap(find.text(fa ? 'عبارت عبور' : 'Passphrase'));
              await t.pumpAndSettle();
              final generate = find.byKey(const ValueKey('security-generate'));
              await revealSecurity(t, generate);
              await t.tap(generate);
              await t.pumpAndSettle();
              await revealSecurity(
                t,
                find.byKey(const ValueKey('security-copy')),
              );
              expect(
                find.byKey(const ValueKey('security-output')),
                findsNothing,
              );
            } else if (scene == 'incident') {
              final choice = find.text(
                fa ? 'فقط لینک را باز کرده‌ام' : 'I only opened a link',
              );
              await revealSecurity(t, choice);
              await t.tap(choice);
              await t.pumpAndSettle();
              await revealSecurity(
                t,
                find.textContaining(
                  fa
                      ? 'دانلودها و درخواست‌ها را مرور کن'
                      : 'Review downloads and prompts',
                ),
              );
            }
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
            await t.pumpAndSettle();
          });
        }
      }
    }
  }
}
