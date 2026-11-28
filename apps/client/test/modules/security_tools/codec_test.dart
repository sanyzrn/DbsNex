import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/security_tools/codec_math.dart';
import 'package:nex_client/modules/security_tools/codec_screen.dart';

import '../../support/nex_harness.dart';
import 'security_widget_test.dart' show settleSecurity, revealSecurity;
import '../../support/text_input.dart';

void main() {
  test('published base64 vectors and multilingual exact round trips', () {
    for (final entry in {
      '': '',
      'f': 'Zg==',
      'fo': 'Zm8=',
      'foo': 'Zm9v',
      'foob': 'Zm9vYg==',
      'fooba': 'Zm9vYmE=',
      'foobar': 'Zm9vYmFy',
    }.entries) {
      expect(
        TextConversion.run(entry.key, TextCodec.base64, decode: false),
        entry.value,
      );
      expect(
        TextConversion.run(entry.value, TextCodec.base64, decode: true),
        entry.key,
      );
    }
    for (final text in ['سلام 👋\nنکس', ' e\u0301 + / % & ? = ', '\u0000']) {
      for (final mode in TextCodec.values) {
        final encoded = TextConversion.run(text, mode, decode: false);
        expect(TextConversion.run(encoded, mode, decode: true), text);
      }
    }
  });
  test(
    'strict base64 rejects malformed padding, pad bits and nontext bytes',
    () {
      for (final value in [
        'Zg',
        'Zh==',
        'Zm9=',
        'Zg===',
        ' Zg==',
        'Zg==\n',
        '_w==',
        '/w==',
        '====',
      ]) {
        expect(
          () => TextConversion.run(value, TextCodec.base64, decode: true),
          throwsFormatException,
        );
      }
    },
  );
  test('hex never strips invalid characters or splits byte pairs', () {
    expect(TextConversion.run('66 6f\n6f', TextCodec.hex, decode: true), 'foo');
    expect(TextConversion.run('666F6f', TextCodec.hex, decode: true), 'foo');
    for (final value in [
      'f',
      '6 6',
      '66-6f',
      '66ZZ6f',
      'ff',
      'c0 af',
      ' 66',
      '66 ',
    ]) {
      expect(
        () => TextConversion.run(value, TextCodec.hex, decode: true),
        throwsFormatException,
      );
    }
  });
  test(
    'URL component semantics preserve plus and reject invalid UTF8 and percent',
    () {
      expect(
        TextConversion.run('a+b%20c', TextCodec.url, decode: true),
        'a+b c',
      );
      expect(
        TextConversion.run('a+b c', TextCodec.url, decode: false),
        'a%2Bb%20c',
      );
      for (final value in ['%', '%0', '%GG', '%FF', '%C0%AF']) {
        expect(
          () => TextConversion.run(value, TextCodec.url, decode: true),
          throwsFormatException,
        );
      }
    },
  );
  test('byte limits apply in both directions and Unicode is never silently replaced', () {
    for (final mode in TextCodec.values) {
      expect(
        () => TextConversion.run('a' * 8193, mode, decode: false),
        throwsFormatException,
      );
      expect(
        () => TextConversion.run('ش' * 4097, mode, decode: false),
        throwsFormatException,
      );
      expect(
        () => TextConversion.run(
          String.fromCharCode(0xd800),
          mode,
          decode: false,
        ),
        throwsFormatException,
      );
    }
    expect(
      utf8
          .encode(
            TextConversion.run('a' * 8192, TextCodec.base64, decode: false),
          )
          .length,
      10924,
    );
  });
  testWidgets(
    'conversion, reverse, stale clearing, malformed input and background privacy',
    (t) async {
      final h = await NexTestHarness.create(name: 'security_codec_');
      addTearDown(h.dispose);
      await t.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SecurityCodecScreen(),
        ),
      );
      await settleSecurity(t);
      final input = find.byKey(const ValueKey('security-codec-input'));
      final run = find.byKey(const ValueKey('security-codec-run'));
      await enterNexText(t, input, 'سلام');
      await revealSecurity(t, run);
      await t.tap(run);
      await t.pumpAndSettle();
      await revealSecurity(
        t,
        find.byKey(const ValueKey('security-codec-output')),
      );
      expect(find.text(base64Encode(utf8.encode('سلام'))), findsOneWidget);
      await revealSecurity(t, find.text('Use output and reverse'));
      await t.tap(find.text('Use output and reverse'));
      await t.pumpAndSettle();
      await revealSecurity(t, run);
      await t.tap(run);
      await t.pumpAndSettle();
      await revealSecurity(
        t,
        find.byKey(const ValueKey('security-codec-output')),
      );
      expect(
        find.byKey(const ValueKey('security-codec-output')),
        findsOneWidget,
      );
      await revealSecurity(t, input);
      await enterNexText(t, input, '!!!');
      await t.pump();
      expect(find.byKey(const ValueKey('security-codec-output')), findsNothing);
      await revealSecurity(t, run);
      await t.tap(run);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('security-codec-output')), findsNothing);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await t.pump();
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      await revealSecurity(t, input);
      expect(t.widget<NexTextField>(input).controller.text, isEmpty);
      expect(
        await NexModuleStore(h.services, 'security_tools').list('draft'),
        isEmpty,
      );
      expect(t.takeException(), isNull);
    },
  );
}
