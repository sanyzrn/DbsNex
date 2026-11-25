// Measures what choosing a direction costs on a long bilingual document.
//
// 2.9.1 replaced the document's first-strong rule with a dominant-script
// count, and every block runs the same scan over its own words. The scan is
// linear and runs while the Markdown is parsed, not per frame, but the
// constant is worth knowing: a long note is re-parsed when it is opened, when
// a slice is added and when the sheet rebuilds.
//
// Run with:
//
//   flutter test benchmark/nex_direction_benchmark.dart
//
// It is a benchmark, not a test: it prints its numbers and asserts nothing
// about them, so a loaded CI machine cannot make it fail.
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/tokens/nex_text_direction.dart';

void main() {
  test('direction scan timing', () {
    final line =
        'پاراگراف فارسی با یک واژه English در میان آن و ادامهٔ نوشته. '
        'An English paragraph with one Persian word, ادامه, in it. '
        'A line of 1234 numbers and punctuation: (!!) 12:30. '
        'یک خط دیگر با «گیومه» و نیم‌فاصله‌ها و اعداد ۱۴۰۳.';
    final document = List.filled(1200, line).join('\n');
    const rounds = 40;

    // Warm up the JIT and the rune iteration.
    for (var i = 0; i < 5; i++) {
      nexDominantDirectionOf(document);
      nexDirectionOf(document);
    }

    final dominant = Stopwatch()..start();
    for (var i = 0; i < rounds; i++) {
      nexDominantDirectionOf(document);
    }
    dominant.stop();

    final first = Stopwatch()..start();
    for (var i = 0; i < rounds; i++) {
      nexDirectionOf(document);
    }
    first.stop();

    final chars = document.runes.length;
    final ms = dominant.elapsedMicroseconds / rounds / 1000;
    // ignore: avoid_print
    print(
      'document: ${chars ~/ 1000}k characters\n'
      'first-strong: '
      '${(first.elapsedMicroseconds / rounds / 1000).toStringAsFixed(3)} '
      'ms/scan\n'
      'dominant:     ${ms.toStringAsFixed(3)} ms/scan',
    );
  });
}
