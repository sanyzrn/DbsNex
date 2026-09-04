import 'dart:convert';
import 'dart:io';

import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

/// Cross-language conformance, the same shape as merge_conformance_test.dart.
///
/// This file and apps/backend/src/routes/note-types.conformance.test.ts read
/// the identical list at spec/note-types.json. If [NoteType] and the server's
/// wire enum ever disagree about which types exist, one of the two suites
/// fails.
///
/// It exists because they did disagree and nothing noticed for two releases.
/// `checklist` and `link` were added here and to the capture service; the
/// server's push schema still named four types, and its `notes` table carried
/// a CHECK for the same four. A device that captured a checklist got a 400 on
/// the whole push. That is worse than a rejected note: [SyncClient.sync]
/// pushes before it pulls and throws on any non-2xx, so the device stopped
/// receiving other devices' changes as well as sending its own — on every
/// retry, for as long as the note existed. Deleting it did not help, because
/// the tombstone is pushed carrying the same type. Only purging it did, at the
/// cost of the note.
///
/// The gap was invisible from either side alone. This file is the cheap thing
/// that closes it: adding a seventh type to [NoteType] without adding it to
/// the spec fails here, and adding it to the spec without widening the
/// server's enum fails there.
void main() {
  final specFile = File('../../spec/note-types.json');

  late List<String> specTypes;

  setUpAll(() {
    expect(
      specFile.existsSync(),
      isTrue,
      reason: 'spec/note-types.json must be reachable from packages/core',
    );
    final decoded =
        jsonDecode(specFile.readAsStringSync()) as Map<String, dynamic>;
    specTypes = (decoded['types'] as List<dynamic>).cast<String>();
    expect(specTypes, isNotEmpty);
  });

  test('NoteType matches spec/note-types.json exactly', () {
    // Order included. The two enums get read side by side whenever a type is
    // added, and agreeing on contents while disagreeing on order makes that
    // comparison harder than it needs to be.
    expect(
      NoteType.values.map((t) => t.wireName).toList(),
      specTypes,
      reason:
          'NoteType and spec/note-types.json disagree — a type in one and not '
          'the other is a device that cannot sync',
    );
  });

  test('every name in the spec parses back to a type', () {
    // The other direction. `fromWire` is the gate the model comment says it
    // is, so a name the spec promises the wire may carry has to survive it —
    // otherwise the failure moves from the push to the pull, and lands on
    // whichever device is unlucky enough to receive one.
    for (final name in specTypes) {
      expect(NoteType.fromWire(name).wireName, name);
    }
  });
}
