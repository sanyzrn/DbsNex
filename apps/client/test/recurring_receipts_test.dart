import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';
import 'package:path/path.dart' as p;

import 'support/nex_harness.dart';

/// A receipt belongs to its Recurring item: a file of its own under the media
/// folder, never a note on the timeline, and swept only once no item lists it.
void main() {
  late NexTestHarness harness;

  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_receipts_');
  });

  tearDown(() => harness.dispose());

  test('a receipt an item lists is kept; one no item lists is swept', () async {
    final services = harness.services;
    final folder = Directory(p.join(services.mediaDir, 'recurring'))
      ..createSync(recursive: true);
    final kept = File(p.join(folder.path, 'receipt-1.jpg'))
      ..writeAsBytesSync([1, 2, 3]);
    final stray = File(p.join(folder.path, 'receipt-2.jpg'))
      ..writeAsBytesSync([4, 5, 6]);
    final fresh = File(p.join(folder.path, 'receipt-3.jpg'))
      ..writeAsBytesSync([7, 8, 9]);
    final old = DateTime.now().subtract(const Duration(hours: 3));
    kept.setLastModifiedSync(old);
    stray.setLastModifiedSync(old);
    await services.worker.saveCommitment(
      NexCommitment(
        id: 'rent',
        title: 'Rent',
        cadence: NexCadence.months,
        every: 1,
        dueAt: DateTime.now(),
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        details: const {
          'receipts': ['recurring/receipt-1.jpg'],
        },
      ),
    );

    await services.sweepOrphanMediaIfDue();

    expect(kept.existsSync(), isTrue);
    expect(stray.existsSync(), isFalse);
    // Added a moment ago, in an editor not yet saved: left alone.
    expect(fresh.existsSync(), isTrue);
    // And none of it is on the timeline.
    expect(await services.timeline(), isEmpty);
  });
}
