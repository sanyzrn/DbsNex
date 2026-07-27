import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { mergeNotes, type NoteRow } from "./merge.ts";

/**
 * Cross-language conformance suite.
 *
 * This file and packages/core/test/merge_conformance_test.dart consume the
 * identical corpus at spec/merge-conformance.json. If the TypeScript and Dart
 * implementations ever disagree on a single case, one of the two suites fails.
 *
 * Previously the two implementations were hand-maintained ports with separate
 * fixtures, so divergence was undetectable — which is exactly how the
 * localeCompare defect survived.
 */
type Case = {
  name: string;
  a: NoteRow;
  b: NoteRow;
  expected: NoteRow;
};

const SPEC_PATH = join(
  dirname(fileURLToPath(import.meta.url)),
  "..",
  "..",
  "..",
  "..",
  "spec",
  "merge-conformance.json",
);

const cases = JSON.parse(readFileSync(SPEC_PATH, "utf8")) as Case[];

assert.ok(cases.length > 0, "conformance corpus must not be empty");

for (const c of cases) {
  test(`conformance: ${c.name}`, () => {
    assert.deepEqual(mergeNotes(c.a, c.b), c.expected);
  });

  // ADR-020 requires the merge to be commutative: two devices resolving the
  // same pair in opposite argument order must reach the same state.
  test(`conformance (commutative): ${c.name}`, () => {
    assert.deepEqual(mergeNotes(c.b, c.a), c.expected);
  });
}
