import 'dart:convert';
import 'dart:io';

import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

/// Cross-language conformance suite.
///
/// This file and apps/backend/src/services/merge.conformance.test.ts consume
/// the identical corpus at spec/merge-conformance.json. If the Dart and
/// TypeScript implementations ever disagree on a single case, one of the two
/// suites fails.
///
/// The two implementations were previously hand-maintained ports with separate
/// fixtures, so divergence was undetectable — which is exactly how the
/// localeCompare ordering defect survived on the server side.
///
/// This file was itself part of that story: it shipped written against an API
/// that never existed (`MergeableNote`, a static `merge`), so it had never once
/// compiled. The first run after repairing it found a real disagreement — the
/// Dart merger kept a tombstone's payload and tag set where the server erases
/// both.
void main() {
  final specFile = File('../../spec/merge-conformance.json');

  const merger = FieldAwareMerger();
  late List<dynamic> cases;

  setUpAll(() {
    expect(
      specFile.existsSync(),
      isTrue,
      reason:
          'spec/merge-conformance.json must be reachable from packages/core',
    );
    cases = jsonDecode(specFile.readAsStringSync()) as List<dynamic>;
    expect(cases, isNotEmpty);
  });

  test('corpus is non-empty', () {
    expect(cases.length, greaterThan(0));
  });

  test('every case matches, in both argument orders', () {
    for (final raw in cases) {
      final testCase = raw as Map<String, dynamic>;
      final name = testCase['name'] as String;

      final a = NoteRevision.fromJson(testCase['a'] as Map<String, dynamic>);
      final b = NoteRevision.fromJson(testCase['b'] as Map<String, dynamic>);
      final expected = testCase['expected'] as Map<String, dynamic>;

      expect(
        merger.merge(a, b).toJson(),
        equals(expected),
        reason: 'case: $name',
      );

      // ADR-020 requires commutativity: two devices resolving the same pair
      // in opposite argument order must reach the same state.
      expect(
        merger.merge(b, a).toJson(),
        equals(expected),
        reason: 'case (commutative): $name',
      );
    }
  });
}
