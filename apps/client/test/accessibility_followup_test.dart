import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/widgets/nex_banner.dart';
import 'package:nex_client/widgets/note_context_menu.dart';
import 'package:nex_client/widgets/reminder_wheel.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

Widget host(Widget child, {bool large = false, bool fa = false}) => MaterialApp(
  locale: Locale(fa ? 'fa' : 'en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: nexDarkTheme(liquidGlass: true),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(large ? 2 : 1),
      highContrast: large,
      disableAnimations: large,
      accessibleNavigation: large,
    ),
    child: child!,
  ),
  home: Scaffold(body: child),
);

void main() {
  testWidgets(
    'permission banner retains a reachable action at 2x on a small phone',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(nexHideBanner);
      var opened = false;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => nexShowBanner(
                context,
                message: 'دسترسی دوربین را در تنظیمات برنامه فعال کنید.',
                actionLabel: 'تنظیمات',
                onAction: () => opened = true,
                haptics: false,
              ),
              child: const Text('show'),
            ),
          ),
          large: true,
          fa: true,
        ),
      );
      await tester.tap(find.text('show'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 8));
      expect(find.text('تنظیمات'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('تنظیمات'));
      await tester.pumpAndSettle();
      expect(opened, isTrue);
    },
  );

  testWidgets(
    'solar reminder fits a small phone at 2x with a scrollable confirm action',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime(2026, 9, 26, 12);
      final note = Note(
        id: 'n',
        type: NoteType.text,
        createdAt: now,
        updatedAt: now,
        deviceId: 'test',
        rev: 1,
        syncState: SyncState.pending,
      );
      await tester.pumpWidget(
        host(
          ReminderWheel(
            note: note,
            now: now,
            solarCalendar: true,
            onSubmit: (_, _) {},
            onClear: () {},
          ),
          large: true,
          fa: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(FilledButton));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('note actions work with secondary click and Shift+F10', (
    tester,
  ) async {
    var added = 0;
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      host(
        NoteContextMenu(
          onOpen: () {},
          onAddTag: () => added++,
          onDelete: () {},
          child: TextButton(
            focusNode: focus,
            onPressed: () {},
            child: const Text('note'),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('note')),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add tag'));
    await tester.pumpAndSettle();
    expect(added, 1);
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNWidgets(3));
    await tester.tap(find.text('Add tag'));
    await tester.pumpAndSettle();
    expect(added, 2);
  });
}
