import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every database command that waits on a model runs off the worker's queue.
///
/// The queue serves one command at a time, and a model is allowed minutes. A
/// command that asks one and stays on the queue holds every capture, delete
/// and attach behind it for as long as the model takes — which is what
/// reading attached photos did in 1.99.90, until it was added to the list.
void main() {
  test('commands that ask a model are on the background list', () {
    final dispatch = File(
      'lib/platform/db_worker_dispatch.dart',
    ).readAsStringSync();
    final worker = File('lib/platform/db_worker.dart').readAsStringSync();

    // Each `_DbCommand.name =>` arm, up to the next one.
    final arms = RegExp(
      r'_DbCommand\.(\w+) =>([\s\S]*?)(?=_DbCommand\.\w+ =>|$)',
    ).allMatches(dispatch);
    const asksAModel = [
      'enrichment.enrichNote',
      'enrichment.readMediaOnDemand',
      'enrichment.backfill',
      'enrichment.suggestTags',
      'enrichment.summarizeOnDemand',
      'enrichment.relatedNotes',
      'enrichment.semanticSearch',
      'attachmentText.read',
      'attachmentText.backfill',
      '_fusedSearch',
    ];
    final waiting = {
      for (final arm in arms)
        if (asksAModel.any(arm.group(2)!.contains)) arm.group(1)!,
    };
    expect(waiting, contains('attachmentReadText'));

    final listStart = worker.indexOf('static const _background = {');
    expect(listStart, isNonNegative);
    final list = worker.substring(listStart, worker.indexOf('};', listStart));
    for (final command in waiting) {
      expect(
        list.contains('_DbCommand.$command,'),
        isTrue,
        reason: '$command waits on a model and must not hold the queue',
      );
    }
  });
}
