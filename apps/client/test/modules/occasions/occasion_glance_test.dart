import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/occasions/occasions_shared.dart';

import '../../support/nex_harness.dart';

/// The glance is what the pinned tile on the home screen shows, read over a
/// shoulder. A remembrance's name never goes on it — the module's own rule,
/// which the dates card and the assistant already follow through the
/// `private` flag; the tile takes the headline, so the headline has to hold
/// the line itself.
void main() {
  final now = DateTime(2026, 11, 2, 12);
  late NexTestHarness h;
  late AppLocalizations l10n;
  late NexModuleStore store;

  setUp(() async {
    h = await NexTestHarness.create(name: 'occasions_glance_');
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
    store = NexModuleStore(h.services, 'occasions');
  });
  tearDown(() => h.dispose());

  Map<String, Object?> body({
    required String title,
    String kind = 'birthday',
    required int month,
    required int day,
    String calendar = 'gregorian',
  }) => {
    'v': 1,
    'title': title,
    'kind': kind,
    'calendar': calendar,
    'month': month,
    'day': day,
    'yearKnown': false,
    'note': '',
    'favorite': false,
    'muted': false,
    'archived': false,
    'remindMinutes': 540,
    'createdAt': '2026-01-01T00:00:00.000',
  };

  test('nothing yet says so, and nothing else', () async {
    final glance = (await occasionsGlance(store, l10n, now))!;
    expect(glance.headline, 'Add a birthday or a date that matters');
    expect(glance.detail, isNull);
    expect(glance.facts, isEmpty);
  });

  test('the next date that may be named leads the tile', () async {
    await store.put(
      'occasion',
      'a',
      body(title: 'Sara', month: now.month, day: now.day + 3),
    );
    final glance = (await occasionsGlance(store, l10n, now))!;
    expect(glance.headline, 'Sara');
    expect(glance.detail, 'in 3 days');
    expect(glance.facts.first.label, 'Sara');
  });

  test('a nearer remembrance never takes its name to the tile', () async {
    await store.put(
      'occasion',
      'm',
      body(
        title: 'Grandpa',
        kind: 'memorial',
        month: now.month,
        day: now.day + 1,
      ),
    );
    await store.put(
      'occasion',
      'a',
      body(title: 'Sara', month: now.month, day: now.day + 5),
    );
    final glance = (await occasionsGlance(store, l10n, now))!;
    expect(glance.headline, 'Sara');
    expect(glance.headline, isNot(contains('Grandpa')));
    expect(glance.detail, 'in 5 days');
    // The quick view, behind a tap, may name it (the medicine precedent).
    expect(glance.facts.any((f) => f.label == 'Grandpa'), isTrue);
  });

  test('only remembrances: one neutral line, a count, never a name', () async {
    await store.put(
      'occasion',
      'm1',
      body(
        title: 'Grandpa',
        kind: 'memorial',
        month: now.month,
        day: now.day + 1,
      ),
    );
    await store.put(
      'occasion',
      'm2',
      body(
        title: 'Nanna',
        kind: 'memorial',
        month: now.month,
        day: now.day + 9,
      ),
    );
    final glance = (await occasionsGlance(store, l10n, now))!;
    expect(glance.headline, 'A date you keep is coming up');
    expect(glance.detail, 'tomorrow');
    expect(glance.headline, isNot(contains('Grandpa')));
    expect(glance.detail, isNot(contains('Grandpa')));
    // The month count still counts them, without naming them.
    expect(glance.facts.last.label, 'In the next 30 days');
    expect(glance.facts.last.value, '2');
  });

  test(
    'a nearer muted or archived date still leads when it may be named',
    () async {
      await store.put(
        'occasion',
        'a',
        body(title: 'Sara', month: now.month, day: now.day + 2)
          ..['muted'] = true,
      );
      final glance = (await occasionsGlance(store, l10n, now))!;
      expect(glance.headline, 'Sara');
    },
  );
}
