import 'local_values.dart';

/// Exact arbitrary-precision rational arithmetic. JSON inputs remain bounded.
class Fraction {
  const Fraction(int numerator, [int denominator = 1])
    : assert(denominator != 0),
      _n = numerator,
      _d = denominator,
      _bigN = null,
      _bigD = null;
  Fraction._(BigInt n, BigInt d)
    : _n = 0,
      _d = 1,
      _bigN = _reduce(n, d).$1,
      _bigD = _reduce(n, d).$2;
  final int _n, _d;
  final BigInt? _bigN, _bigD;
  BigInt get exactNumerator =>
      _bigN ??
      (BigInt.from(_d).isNegative ? -BigInt.from(_n) : BigInt.from(_n));
  BigInt get exactDenominator => _bigD ?? BigInt.from(_d).abs();

  /// Bounded serialization only; never used for derived arithmetic.
  int get numerator => _checked(exactNumerator);
  int get denominator => _checked(exactDenominator);
  static int _checked(BigInt value) {
    if (value.abs() > BigInt.parse('9007199254740991')) {
      throw RangeError('Rational outside JSON integer bounds');
    }
    return value.toInt();
  }

  static (BigInt, BigInt) _reduce(BigInt n, BigInt d) {
    if (d == BigInt.zero) throw ArgumentError('Zero denominator');
    if (d.isNegative) {
      n = -n;
      d = -d;
    }
    final g = n.abs().gcd(d);
    return (n ~/ g, d ~/ g);
  }

  static Fraction exact(BigInt n, BigInt d) => Fraction._(n, d);
  Fraction operator +(Fraction o) => Fraction._(
    exactNumerator * o.exactDenominator + o.exactNumerator * exactDenominator,
    exactDenominator * o.exactDenominator,
  );
  Fraction operator -(Fraction o) => Fraction._(
    exactNumerator * o.exactDenominator - o.exactNumerator * exactDenominator,
    exactDenominator * o.exactDenominator,
  );
  Fraction operator *(Fraction o) => Fraction._(
    exactNumerator * o.exactNumerator,
    exactDenominator * o.exactDenominator,
  );
  Fraction operator /(Fraction o) => Fraction._(
    exactNumerator * o.exactDenominator,
    exactDenominator * o.exactNumerator,
  );
  int compareTo(Fraction o) => (exactNumerator * o.exactDenominator).compareTo(
    o.exactNumerator * exactDenominator,
  );
  bool operator <(Fraction o) => compareTo(o) < 0;
  bool operator >(Fraction o) => compareTo(o) > 0;
  bool operator <=(Fraction o) => compareTo(o) <= 0;
  bool operator >=(Fraction o) => compareTo(o) >= 0;
  @override
  bool operator ==(Object other) => other is Fraction && compareTo(other) == 0;
  @override
  int get hashCode {
    final reduced = _reduce(exactNumerator, exactDenominator);
    return Object.hash(reduced.$1, reduced.$2);
  }

  bool terminatesWithin(int digits) {
    var remainder = exactNumerator.abs() % exactDenominator;
    for (var i = 0; i < digits && remainder != BigInt.zero; i++) {
      remainder = (remainder * BigInt.from(10)) % exactDenominator;
    }
    return remainder == BigInt.zero;
  }

  String toDecimalString({int digits = 4}) {
    if (digits < 0 || digits > 30) throw RangeError.range(digits, 0, 30);
    final n = exactNumerator, d = exactDenominator;
    var rem = n.abs() % d;
    final whole = n.abs() ~/ d, tail = StringBuffer();
    for (var i = 0; i < digits && rem != BigInt.zero; i++) {
      rem *= BigInt.from(10);
      tail.write(rem ~/ d);
      rem %= d;
    }
    return '${n.isNegative ? '-' : ''}$whole${tail.isEmpty ? '' : '.$tail'}';
  }

  int roundHalfUp() {
    final n = exactNumerator, d = exactDenominator;
    final rounded = (n.abs() * BigInt.two + d) ~/ (d * BigInt.two);
    return _checked(n.isNegative ? -rounded : rounded);
  }
}

/// Plain exact decimals, 15 significant input digits and at most six decimals.
Fraction? fractionFromDecimal(String input) {
  final text = LocalValues.ascii(input.trim()).replaceAll(',', '.');
  if (!RegExp(r'^([0-9]+(\.[0-9]*)?|\.[0-9]+)$').hasMatch(text)) return null;
  final parts = text.split('.'),
      whole = parts.first.isEmpty ? '0' : parts.first,
      tail = parts.length > 1 ? parts.last : '';
  if ((whole + tail).length > 15 || tail.length > 6) return null;
  final value = int.tryParse(whole + tail);
  if (value == null) return null;
  var denominator = 1;
  for (var i = 0; i < tail.length; i++) {
    denominator *= 10;
  }
  return Fraction(value, denominator);
}
