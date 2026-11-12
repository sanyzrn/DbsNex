import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/widgets/choice_cards.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/nex_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const output = String.fromEnvironment('NEX_THEME_CAPTURE');
  if (output.isNotEmpty) {
    setUpAll(() async {
      for (final (family, asset) in [
        (nexLatinFont, 'Inter-subset.ttf'),
        (nexPersianFont, 'VazirmatnVariable.ttf'),
        ('Fraunces', 'FrauncesVariable.ttf'),
        ('MarkaziText', 'MarkaziTextVariable.ttf'),
      ]) {
        final loader = FontLoader(family)
          ..addFont(rootBundle.load('assets/fonts/$asset'));
        await loader.load();
      }
      final flutterRoot = Platform.environment['FLUTTER_ROOT']!;
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          File(
            '$flutterRoot/bin/cache/artifacts/material_fonts/'
            'MaterialIcons-Regular.otf',
          ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
      await icons.load();
    });
  }

  test(
    'old Dark becomes Night without rewriting saved themes or options',
    () async {
      SharedPreferences.setMockInitialValues({
        'appearance.theme': 'dark',
        'appearance.theme_preset': 'forest',
        'appearance.accent_seed': '#B61615',
        'appearance.liquid_glass_v2': true,
      });
      FlutterSecureStorage.setMockInitialValues({});
      final prefs = await NexPreferences.load();
      expect(prefs.appearanceMode, NexAppearanceMode.night);
      expect(prefs.themeMode, ThemeMode.dark);
      expect(prefs.themePreset, 'forest');
      expect(prefs.effectiveThemePreset, 'classic');
      expect(prefs.accentSeed, '#B61615');
      // A v2 choice does not silently switch the rebuilt material on: each
      // generation of Liquid Glass has been a fresh opt-in, and the 2.6.21
      // material is a different look, not a repair of the paused one.
      expect(prefs.liquidGlass, isFalse);
      expect(prefs.effectiveLiquidGlass, isFalse);
      final raw = await SharedPreferences.getInstance();
      expect(raw.getString('appearance.theme'), 'dark');
      expect(raw.getString('appearance.theme_preset'), 'forest');
      expect(raw.getBool('appearance.liquid_glass_v2'), isTrue);
    },
  );

  test('all four modes survive reload and settings backup/restore', () async {
    SharedPreferences.setMockInitialValues({
      'appearance.theme_preset': 'paper',
    });
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = await NexPreferences.load();
    for (final mode in NexAppearanceMode.values) {
      await prefs.setAppearanceMode(mode);
      expect((await NexPreferences.load()).appearanceMode, mode);
      final backup = prefs.backupSettings();
      await prefs.setAppearanceMode(
        mode == NexAppearanceMode.system
            ? NexAppearanceMode.light
            : NexAppearanceMode.system,
      );
      await prefs.restoreSettings(backup);
      expect(prefs.appearanceMode, mode);
      expect(prefs.themePreset, 'paper');
      expect(prefs.effectiveThemePreset, 'classic');
      PortablePreferences.validate({'appearance.theme': mode.wireName});
    }
  });

  test('legacy values and unknown modes have safe defaults', () {
    expect(NexAppearanceMode.fromWire('dark'), NexAppearanceMode.night);
    expect(NexAppearanceMode.fromWire('light'), NexAppearanceMode.light);
    expect(NexAppearanceMode.fromWire(null), NexAppearanceMode.system);
    expect(NexAppearanceMode.fromWire('future-mode'), NexAppearanceMode.system);
    PortablePreferences.validate({'appearance.theme': 'dark'});
    expect(
      () => PortablePreferences.validate({'appearance.theme': 'future-mode'}),
      throwsFormatException,
    );
  });

  testWidgets(
    'System follows the OS and Dark/Night repaint at equal brightness',
    (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final h = await NexTestHarness.create(
        preferences: {'appearance.theme_preset': 'paper'},
      );
      addTearDown(h.dispose);
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      MaterialApp app() => tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app().themeMode, ThemeMode.system);
      expect(
        app().darkTheme!.colorScheme.surface,
        NexSoftDarkColors.background,
      );
      expect(app().theme!.colorScheme, nexSoftLightTheme().colorScheme);
      await h.preferences.setAppearanceMode(NexAppearanceMode.night);
      await tester.pumpAndSettle();
      expect(app().themeMode, ThemeMode.dark);
      expect(app().darkTheme!.colorScheme, nexOledNightTheme().colorScheme);
      await h.preferences.setAppearanceMode(NexAppearanceMode.dark);
      await tester.pumpAndSettle();
      expect(app().themeMode, ThemeMode.dark);
      expect(
        app().darkTheme!.colorScheme.surface,
        NexSoftDarkColors.background,
      );
      await h.preferences.setAccentSeed('#B61615');
      await h.preferences.setLiquidGlass(true);
      await tester.pumpAndSettle();
      expect(
        app().darkTheme!.colorScheme.primary,
        isNot(NexSoftDarkColors.accentText),
      );
      // The switch is live again: the choice reaches both themes, and the
      // dock, the bar and every sheet follow it.
      expect(h.preferences.liquidGlass, isTrue);
      expect(h.preferences.effectiveLiquidGlass, isTrue);
      expect(app().darkTheme!.extension<NexVisualStyle>()!.liquidGlass, isTrue);
      expect(app().theme!.extension<NexVisualStyle>()!.liquidGlass, isTrue);
      await h.preferences.setAppearanceMode(NexAppearanceMode.system);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(Scaffold).first);
      expect(Theme.of(context).brightness, Brightness.light);
      expect(h.preferences.themePreset, 'paper');
      expect(tester.takeException(), isNull);
    },
  );

  // Actual app previews, not an HTML recreation. Saved only when explicitly
  // requested by a local verification invocation, never during ordinary CI.
  for (final lang in ['en', 'fa']) {
    for (final mode in [
      NexAppearanceMode.light,
      NexAppearanceMode.dark,
      NexAppearanceMode.night,
    ]) {
      testWidgets('$lang ${mode.name}: readable real app and settings', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final h = await NexTestHarness.create();
        addTearDown(h.dispose);
        await h.preferences.setLocale(lang);
        await h.preferences.setAppearanceMode(mode);
        await h.services.captureText(
          lang == 'fa'
              ? 'بررسی طرح جدید نکس و کارهای هفته'
              : 'Review the Nex design and this week’s plans',
        );
        final key = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(key: key, child: h.app()));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        Future<void> capture(String name) async {
          if (output.isEmpty) return;
          await tester.runAsync(() async {
            final image =
                await (key.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final dir = Directory(output)..createSync(recursive: true);
            await File('${dir.path}/${mode.name}_${lang}_$name.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await capture('home');
        await tester.tap(find.byIcon(Icons.settings_outlined));
        await tester.pumpAndSettle();
        final appearance = find.byKey(
          const ValueKey('settings-category-appearance'),
        );
        await tester.ensureVisible(appearance);
        await tester.pumpAndSettle();
        await tester.tap(appearance);
        await tester.pumpAndSettle();
        expect(find.byType(NexChoiceCards<NexAppearanceMode>), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture('settings');
        if (mode == NexAppearanceMode.dark) {
          await h.preferences.setAccentSeed('#B61615');
          await h.preferences.setLiquidGlass(true);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await capture('accent_paused_glass');
        }
      });
    }
  }
}
