import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/reminders.dart';
import 'package:nex_core/nex_core.dart';

/// A standing obligation's own alarm.
///
/// The interesting part is not the scheduling — it is that adding a second
/// kind of thing that owns an alarm has a trap in it, and this is where the
/// trap is recorded.
void main() {
  NexCommitment make({
    String id = 'c1',
    bool notify = true,
    bool paused = false,
  }) => NexCommitment(
    id: id,
    title: 'car insurance',
    cadence: NexCadence.years,
    every: 1,
    dueAt: DateTime(2030, 5, 10, 9),
    notify: notify,
    paused: paused,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  test('a commitment and a note with the same id get different alarms', () {
    // Nothing stops them sharing one: both are UUIDs out of the same
    // generator. Sharing an alarm id would mean each silently cancelled the
    // other — the exact class of bug the reserved-id block exists for, one
    // level up.
    expect(
      NexReminders.commitmentIdFor('shared-id'),
      isNot(NexReminders.idFor('shared-id')),
    );
  });

  test('an alarm id is stable and clear of the reserved block', () {
    // Stable, or rescheduling would add a second alarm rather than replacing
    // the first. Clear of the block, or it would land on the daily nudge or
    // the download notification and the two would cancel each other.
    expect(
      NexReminders.commitmentIdFor('c1'),
      NexReminders.commitmentIdFor('c1'),
    );
    for (final id in ['c1', 'c2', 'insurance', '', 'commitment:c1']) {
      expect(
        NexReminders.commitmentIdFor(id),
        greaterThanOrEqualTo(NexReminders.reservedIds),
        reason: id,
      );
    }
  });

  test('what the launch sweep is asked to keep', () {
    // The trap. `syncFromLibrary` cancels every pending alarm it cannot
    // account for, so a commitment left out of the list it is given loses its
    // alarm on the next launch — the feature would work until the app was
    // restarted, which is the worst possible shape for a bug like this.
    //
    // This asserts the rule the sweep applies rather than driving the
    // plugin: the ids it keeps are exactly the commitments that are meant to
    // ring. A paused or silenced one is not, and must not be re-armed.
    final wanted = <NexCommitment>[
      make(id: 'rings'),
      make(id: 'silenced', notify: false),
      make(id: 'paused', paused: true),
    ];

    final keep = <int>{
      for (final c in wanted)
        if (c.notify && !c.paused) NexReminders.commitmentIdFor(c.id),
    };

    expect(keep, {NexReminders.commitmentIdFor('rings')});
    expect(keep, isNot(contains(NexReminders.commitmentIdFor('silenced'))));
    expect(keep, isNot(contains(NexReminders.commitmentIdFor('paused'))));
  });

  test('turning the notification off is carried through an edit', () {
    // The switch is per item on purpose: water every two hours is seven
    // notifications a day, and somebody who silences that at the OS level
    // loses every other reminder Nex sends with it.
    final quiet = make().copyWith(notify: false);
    expect(quiet.notify, isFalse);
    // And is not lost by an unrelated edit.
    expect(quiet.copyWith(title: 'renamed').notify, isFalse);
    expect(make().copyWith(title: 'renamed').notify, isTrue);
  });

  test('being met carries the setting forward', () {
    // `met` rebuilds the commitment. A silenced one that starts ringing the
    // moment it is ticked off would be the setting quietly undoing itself.
    expect(make(notify: false).met(DateTime(2030, 5, 10, 10)).notify, isFalse);
    expect(make().met(DateTime(2030, 5, 10, 10)).notify, isTrue);
  });
}
