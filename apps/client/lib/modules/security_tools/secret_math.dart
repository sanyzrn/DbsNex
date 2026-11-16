import 'eff_words.dart';

final effWords = List<String>.unmodifiable(
  effWordText.trim().split(RegExp(r'\s+')),
);

class SecretOptions {
  const SecretOptions({
    this.length = 24,
    this.upper = true,
    this.lower = true,
    this.digits = true,
    this.symbols = true,
    this.excludeAmbiguous = true,
  });
  final int length;
  final bool upper, lower, digits, symbols, excludeAmbiguous;
  List<String> get groups =>
      [
            if (lower) 'abcdefghijklmnopqrstuvwxyz',
            if (upper) 'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
            if (digits) '0123456789',
            if (symbols) r'!#$%&*+-=?@',
          ]
          .map(
            (g) => excludeAmbiguous ? g.replaceAll(RegExp('[IlO01]'), '') : g,
          )
          .toList();
}

/// Production calls supply Random.secure().nextInt. No insecure fallback.
/// Rejection sampling is uniform over strings containing each selected group.
String makePassword(SecretOptions options, int Function(int) sample) {
  final groups = options.groups;
  if (options.length < 16 || options.length > 64 || groups.isEmpty) {
    throw ArgumentError('invalid generator options');
  }
  final alphabet = groups.join();
  for (var attempt = 0; attempt < 128; attempt++) {
    final text = String.fromCharCodes(
      List.generate(
        options.length,
        (_) => alphabet.codeUnitAt(sample(alphabet.length)),
      ),
    );
    if (groups.every((g) => text.split('').any(g.contains))) return text;
  }
  throw StateError('generation failed');
}

String makePassphrase(int count, int Function(int) sample) {
  if (count < 6 || count > 8) throw ArgumentError('invalid word count');
  return List.generate(
    count,
    (_) => effWords[sample(effWords.length)],
  ).join(' ');
}
