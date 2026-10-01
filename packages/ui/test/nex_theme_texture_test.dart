import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

/// A theme's motif along the bottom of the screen: drawn under the content,
/// never over it, and not at all for a theme without one.
void main() {
  Finder painter() => find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is NexTexturePainter,
  );

  testWidgets('a theme without a motif draws nothing extra', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: NexTextureBackdrop(
          texture: NexThemeTexture.none,
          child: Text('notes'),
        ),
      ),
    );
    expect(painter(), findsNothing);
  });

  testWidgets('a motif sits under the content and takes no touches', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: NexTextureBackdrop(
          texture: NexThemeTexture.girih,
          child: Center(
            child: TextButton(
              onPressed: () => tapped = true,
              child: const Text('notes'),
            ),
          ),
        ),
      ),
    );
    expect(painter(), findsOneWidget);
    final stack = tester.widget<Stack>(
      find.ancestor(of: painter(), matching: find.byType(Stack)).first,
    );
    expect(
      stack.children.last,
      isNot(isA<IgnorePointer>()),
      reason: 'the content is drawn last, over the motif',
    );
    await tester.tap(find.text('notes'));
    expect(tapped, isTrue);
  });
}
