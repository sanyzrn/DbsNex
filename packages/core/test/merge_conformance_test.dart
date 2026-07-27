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
void main() {
  final specFile = File('../../spec/merge-conformance.json');

  late List<dynamic> cases;

  setUpAll(() {
    expect(
      specFile.existsSync(),
      isTrue,
      reason: 'spec/merge-conformance.json must be reachable from packages/core',
    );
    cases = jsonDecode(specFile.readAsStringSync()) as List<dynamic>;
    expect(cases, isNotEmpty);
  });

  test('corpus is non-empty', () {
    expect(cases.length, greaterThan(0));
  });

  group('conformance', () {
    setUp(() {});

    test('every case matches, in both argument orders', () {
      for (final raw in cases) {
        final testCase = raw as Map<String, dynamic>;
        final name = testCase['name'] as String;

        final a = MergeableNote.fromJson(
          testCase['a'] as Map<String, dynamic>,
        );
        final b = MergeableNote.fromJson(
          testCase['b'] as Map<String, dynamic>,
        );
        final expected = testCase['expected'] as Map<String, dynamic>;

        expect(
          FieldAwareMerger.merge(a, b).toJson(),
          equals(expected),
          reason: 'case: ' + name,
        );

        // ADR-020 requires commutativity: two devices resolving the same pair
        // in opposite argument order must reach the same state.
        expect(
          FieldAwareMerger.merge(b, a).toJson(),
          equals(expected),
          reason: 'case (commutative): ' + name,
        );
      }
    });
  });
}
