import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';

/// A sheet lifts above the keyboard, once, so its fields can be reached —
/// whether or not the sheet's own content also pads for it.
void main() {
  Future<void> open(WidgetTester tester, {required bool padsItself}) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: nexLightTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => nexShowSheet<void>(
                context: context,
                swipeToClose: true,
                dismissible: false,
                builder: (context) => SingleChildScrollView(
                  padding: EdgeInsets.only(
                    bottom: padsItself
                        ? MediaQuery.viewInsetsOf(context).bottom
                        : 0,
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(height: 120),
                      TextField(key: ValueKey('field')),
                      SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  for (final pads in [false, true]) {
    testWidgets(
      'the sheet field stays above the keyboard (content pads itself: $pads)',
      (tester) async {
        await open(tester, padsItself: pads);
        final resting = tester.getBottomLeft(
          find.byKey(const ValueKey('field')),
        );
        expect(resting.dy, lessThan(800));

        tester.view.viewInsets = const FakeViewPadding(bottom: 400);
        await tester.pumpAndSettle();
        final lifted = tester.getBottomLeft(
          find.byKey(const ValueKey('field')),
        );
        // Above the top of a 400px keyboard, and lifted by about its height,
        // not twice it.
        expect(lifted.dy, lessThanOrEqualTo(400));
        expect(resting.dy - lifted.dy, closeTo(400, 1));
        addTearDown(tester.view.resetViewInsets);
      },
    );
  }
}
