import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

void main() {
  testWidgets('explicit lines choose their own direction and alignment', (
    tester,
  ) async {
    const english = '[Verse - softly]';
    const persian = 'این یک خط فارسی است';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 400, child: NexBodyText('$english\n$persian')),
        ),
      ),
    );

    final englishText = tester.widget<Text>(find.text(english));
    final persianText = tester.widget<Text>(find.text(persian));
    expect(englishText.textDirection, TextDirection.ltr);
    expect(englishText.textAlign, TextAlign.left);
    expect(persianText.textDirection, TextDirection.rtl);
    expect(persianText.textAlign, TextAlign.right);
    expect(tester.getRect(find.text(english)).left, 0);
    expect(tester.getRect(find.text(persian)).right, 400);
  });
}
