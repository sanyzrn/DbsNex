import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/reminders.dart';
import 'package:nex_core/nex_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stands in for the notification plugin, counting what the launch sweep
/// asks of it: how many times the whole pending queue was serialised over
/// the platform channel, and how many alarms were set.
class _CountingPlugin implements FlutterLocalNotificationsPlugin {
  final pending = <int>{};

  /// Reads of the whole pending queue — each one serialises every alarm the
  /// system holds, so a sweep that reads it per note grows with the square
  /// of the reminder count.
  int queueReads = 0;
  int schedules = 0;

  /// Ids whose `zonedSchedule` silently fails, as a phone that dropped them
  /// would behave.
  final drop = <int>{};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final id = invocation.namedArguments[#id] as int?;
    switch (invocation.memberName) {
      case #initialize:
        return Future<bool?>.value(true);
      case #zonedSchedule:
        schedules++;
        if (id != null && !drop.contains(id)) pending.add(id);
        return Future<void>.value();
      case #cancel:
        pending.remove(id);
        return Future<void>.value();
      case #pendingNotificationRequests:
        queueReads++;
        return Future<List<PendingNotificationRequest>>.value([
          for (final id in pending)
            PendingNotificationRequest(id, null, null, null),
        ]);
      case #getNotificationAppLaunchDetails:
        return Future<NotificationAppLaunchDetails?>.value();
      case #resolvePlatformSpecificImplementation:
        return null;
    }
    return super.noSuchMethod(invocation);
  }
}

/// The launch-and-return sweep (`syncFromLibrary`) re-arms every note's
/// reminder. These tests pin what that sweep costs the platform channel and
/// what it still reports, so the batched verification cannot quietly become
/// a per-note queue read again, nor a dropped alarm go unreported.
void main() {
  late _CountingPlugin plugin;
  late NexReminders reminders;

  Note upcoming(String id) {
    final now = DateTime.now().toUtc();
    return Note(
      id: id,
      type: NoteType.text,
      content: 'remind me of $id',
      createdAt: now,
      updatedAt: now,
      deviceId: 'd',
      rev: 1,
      syncState: SyncState.synced,
      dueAt: now.add(Duration(hours: 5 + (id.hashCode % 10))),
      dueRepeat: NoteRepeat.once,
    );
  }

  setUp(() {
    NexReminders.debugSupported = true;
    SharedPreferences.setMockInitialValues({});
    plugin = _CountingPlugin();
    reminders = NexReminders(plugin: plugin);
  });
  tearDown(() => NexReminders.debugSupported = null);

  // A plain test has no timezone platform channel behind it; without this,
  // every schedule would end with a timezone warning in `lastError` rather
  // than the quiet null the sweep is meant to leave.
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (call) async => call.method == 'getLocalTimezone' ? 'UTC' : null,
        );
  });

  test('the sweep reads the pending queue once for the prune and once for '
      'the whole batch of notes', () async {
    final notes = [for (var i = 0; i < 20; i++) upcoming('n$i')];
    await reminders.syncFromLibrary(notes);
    // 20 armed alarms, and the queue crossed the channel twice: the prune's
    // read and the batch verification. A per-note verification would read it
    // once per note — 21 reads for 20 notes, and 201 for 200.
    expect(plugin.schedules, 20);
    expect(plugin.queueReads, 2);
    expect(plugin.pending.length, 20);
    expect(reminders.lastError, isNull);
  });

  test(
    'a note whose time has passed is withdrawn, not reported missing',
    () async {
      final now = DateTime.now().toUtc();
      final lapsed = Note(
        id: 'gone',
        type: NoteType.text,
        content: 'already late',
        createdAt: now,
        updatedAt: now,
        deviceId: 'd',
        rev: 1,
        syncState: SyncState.synced,
        dueAt: now.subtract(const Duration(days: 1)),
        dueRepeat: NoteRepeat.once,
      );
      final diagnostics = <String>[];
      reminders.onDiagnostic = diagnostics.add;
      await reminders.syncFromLibrary([lapsed, upcoming('fine')]);
      expect(plugin.schedules, 1);
      expect(reminders.lastError, isNull);
      expect(
        diagnostics.where((line) => line.contains('did not keep')),
        isEmpty,
        reason: 'a deliberately withdrawn alarm is not a missing one',
      );
    },
  );

  test('an alarm the system dropped is still reported, by note', () async {
    final notes = [for (var i = 0; i < 5; i++) upcoming('d$i')];
    plugin.drop.add(NexReminders.idFor('d3'));
    final diagnostics = <String>[];
    reminders.onDiagnostic = diagnostics.add;
    await reminders.syncFromLibrary(notes);
    expect(diagnostics, contains(contains('reminder d3')));
    expect(diagnostics, contains(contains('did not keep the alarm')));
    // The last note armed fine, so the sheet-facing answer stays quiet —
    // the same value a note-by-note pass would have left in lastError.
    expect(reminders.lastError, isNull);
  });

  test(
    'the last note\'s dropped alarm is the answer the sheet reads',
    () async {
      final notes = [for (var i = 0; i < 3; i++) upcoming('l$i')];
      plugin.drop.add(NexReminders.idFor('l2'));
      await reminders.syncFromLibrary(notes);
      expect(reminders.lastError, 'the system did not keep the alarm');
    },
  );

  Note moved(Note note, Duration by) => Note(
    id: note.id,
    type: note.type,
    content: note.content,
    createdAt: note.createdAt,
    updatedAt: note.updatedAt,
    deviceId: note.deviceId,
    rev: note.rev,
    syncState: note.syncState,
    dueAt: note.dueAt!.add(by),
    dueRepeat: note.dueRepeat,
  );

  test('a sweep where nothing changed sets no alarm at all', () async {
    final notes = [for (var i = 0; i < 20; i++) upcoming('k$i')];
    await reminders.syncFromLibrary(notes);
    expect(plugin.schedules, 20);
    expect(plugin.pending.length, 20);
    plugin.schedules = 0;
    plugin.queueReads = 0;
    await reminders.syncFromLibrary(notes);
    // One queue read (the prune's — the only question the sweep still asks),
    // no `zonedSchedule`, and no batch verification to run because nothing
    // was set. The alarms the OS holds are the ones these notes asked for.
    expect(plugin.schedules, 0);
    expect(plugin.queueReads, 1);
    expect(plugin.pending.length, 20);
    expect(reminders.lastError, isNull);
  });

  test('one moved note re-arms exactly its own alarm', () async {
    final notes = [for (var i = 0; i < 10; i++) upcoming('m$i')];
    await reminders.syncFromLibrary(notes);
    plugin.schedules = 0;
    plugin.queueReads = 0;
    final changed = [
      for (final note in notes)
        note.id == 'm7' ? moved(note, const Duration(hours: 3)) : note,
    ];
    await reminders.syncFromLibrary(changed);
    expect(plugin.schedules, 1);
    // The prune's read and the batch verification of the one alarm set.
    expect(plugin.queueReads, 2);
    expect(reminders.lastError, isNull);
  });

  test('a lost signature — a reinstall — re-arms everything', () async {
    final notes = [for (var i = 0; i < 20; i++) upcoming('r$i')];
    await reminders.syncFromLibrary(notes);
    plugin.schedules = 0;
    plugin.queueReads = 0;
    // A reinstall from a backup: the library comes back, the install's own
    // record of what it told the OS is gone, and so is the OS's alarm list.
    plugin.pending.clear();
    SharedPreferences.setMockInitialValues({});
    await reminders.syncFromLibrary(notes);
    expect(plugin.schedules, 20);
    expect(plugin.pending.length, 20);
  });

  test('an alarm the OS dropped is re-armed on the next sweep', () async {
    final notes = [for (var i = 0; i < 6; i++) upcoming('z$i')];
    await reminders.syncFromLibrary(notes);
    // The phone quietly dropped one, the way the prune's read discovers.
    plugin.pending.remove(NexReminders.idFor('z2'));
    plugin.schedules = 0;
    plugin.queueReads = 0;
    await reminders.syncFromLibrary(notes);
    expect(plugin.schedules, 1);
    expect(plugin.pending.length, 6);
    expect(reminders.lastError, isNull);
  });

  test('a repeating reminder\'s signature is its wall clock, not the day', () {
    // `computeNextOccurrence` moves the armed instant forward every day while
    // the alarm the OS holds — "every day at HH:mm" — does not change. The
    // signature has to describe the latter, or every sweep would re-arm
    // every repeating reminder for nothing.
    final start = DateTime(2026, 11, 1, 9, 30);
    String sign(DateTime when) => NexReminderActions.armedSignatureFor(
      when: when,
      repeat: NoteRepeat.daily,
      mode: AndroidScheduleMode.exactAllowWhileIdle,
      secret: false,
      title: 'same title',
      text: 'same body',
    );
    expect(sign(start), sign(start)); // trivially
    // The same series, evaluated "now" a day apart, is still the same alarm.
    expect(sign(start), isNot(sign(start.add(const Duration(hours: 1)))));
    // A one-off signs its instant: a moved one is a different alarm.
    String once(DateTime when) => NexReminderActions.armedSignatureFor(
      when: when,
      repeat: NoteRepeat.once,
      mode: AndroidScheduleMode.exactAllowWhileIdle,
      secret: false,
      title: 't',
      text: 'b',
    );
    expect(
      once(start),
      isNot(once(start.add(const Duration(minutes: 1)))),
    );
    // Exactness is part of the alarm: a permission granted between sweeps
    // re-arms, rather than leaving a quieter alarm in place.
    expect(
      NexReminderActions.armedSignatureFor(
        when: start,
        repeat: NoteRepeat.once,
        mode: AndroidScheduleMode.inexactAllowWhileIdle,
        secret: false,
        title: 't',
        text: 'b',
      ),
      isNot(once(start)),
    );
  });
}
