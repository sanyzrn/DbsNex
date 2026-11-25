// Measures the two costs the 2.9.1 attention-engine change removed from the
// brief's path: compiling the same regular expressions for every call, and
// folding the same constant phrases for every line.
//
// Run with:
//
//   dart run benchmark/attention_benchmark.dart
//
// Both halves are microbenchmarks of the exact operations, not of the app:
// they answer "how much of a brief's time was this", which is what the change
// was for. The `before` variant is the code as it stood in 2.9.0; the `after`
// variant is what `attention.dart` does now.
import 'package:nex_core/ai/attention.dart';

/// Phrases of the shape the violation check folds, taken from its lists.
const _needles = [
  'nothing overdue',
  'no overdue',
  'overdue: none',
  'nothing is overdue',
  'چیزی عقب نیفتاده',
  'هیچ موردی عقب نیفتاده',
  'nothing is due',
  'nothing due',
  'nothing is waiting',
  'all caught up',
  'everything is done',
  'done',
  'completed',
  'finished',
  'missed',
  'overdue',
  'passed',
  'already',
  'reminded',
  'forgot',
  'not ',
  "n't",
  'no ',
  'never',
  'yet',
  'هنوز',
  'نشده',
  'نکرد',
  'نه ',
  'بدون',
];

final _cachedFolds = <String, String>{};

bool anyInBefore(String text) =>
    _needles.any((needle) => text.contains(nexAttentionFold(needle)));

bool anyInAfter(String text) => _needles.any(
  (needle) => text.contains(
    _cachedFolds.putIfAbsent(needle, () => nexAttentionFold(needle)),
  ),
);

List<String> tokensBefore(String text) {
  final tokens = <String>{};
  for (final match in RegExp(
    r'[\p{L}\p{N}]+',
    unicode: true,
  ).allMatches(text)) {
    final token = nexAttentionStem(match.group(0)!);
    if (token.length >= 3) tokens.add(token);
  }
  return [...tokens];
}

final _wordPattern = RegExp(r'[\p{L}\p{N}]+', unicode: true);

List<String> tokensAfter(String text) {
  final tokens = <String>{};
  for (final match in _wordPattern.allMatches(text)) {
    final token = nexAttentionStem(match.group(0)!);
    if (token.length >= 3) tokens.add(token);
  }
  return [...tokens];
}

int micros(void Function() run, {int rounds = 200}) {
  // Warm up: the first call pays for lazy initialization and the JIT.
  for (var i = 0; i < 20; i++) {
    run();
  }
  final clock = Stopwatch()..start();
  for (var i = 0; i < rounds; i++) {
    run();
  }
  clock.stop();
  return clock.elapsedMicroseconds;
}

void main() {
  final titles = [
    for (var i = 0; i < 400; i++)
      'Call the dentist about the invoice for the trip to Tabriz $i',
  ];
  final lines = [
    for (var i = 0; i < 40; i++)
      'The $i invoice was missed, but the dentist said nothing was overdue',
    for (var i = 0; i < 40; i++)
      'فاکتور $i پرداخت نشده و یادآوری dentist فراموش شد، ولی چیزی عقب نیفتاده',
  ];

  final tokenBefore = micros(() {
    for (final title in titles) {
      tokensBefore(title);
    }
  }, rounds: 20);
  final tokenAfter = micros(() {
    for (final title in titles) {
      tokensAfter(title);
    }
  }, rounds: 20);
  final anyBefore = micros(() {
    for (final line in lines) {
      anyInBefore(nexAttentionFold(line));
    }
  });
  final anyAfter = micros(() {
    for (final line in lines) {
      anyInAfter(nexAttentionFold(line));
    }
  });

  String change(int before, int after) =>
      before == 0 ? 'n/a' : '${((1 - after / before) * 100).round()}% less';

  // ignore: avoid_print
  print(
    'attention tokens: ${tokenBefore}us -> ${tokenAfter}us '
    '(${change(tokenBefore, tokenAfter)})',
  );
  // ignore: avoid_print
  print(
    'any needle:       ${anyBefore}us -> ${anyAfter}us '
    '(${change(anyBefore, anyAfter)})',
  );
}
