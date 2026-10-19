import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:nex_core/nex_core.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

part 'reminders/scheduled_reminders.dart';
part 'reminders/notice_reminders.dart';
part 'reminders/note_reminders.dart';
part 'reminders/module_reminders.dart';

/// Brings a note back up at the time its owner asked for.
///
/// The note carries the time (`Note.dueAt`); this only schedules the alarm
/// that acts on it. That split matters: an OS alarm is not durable — a
/// reinstall drops every one, a restore from backup brings notes back with no
/// alarms behind them, and Android has spent several versions making exact
/// alarms harder to keep — whereas the note is durable by definition. So the
/// library is the record and the alarms are a copy of it, rebuilt from the
/// library on every launch by [syncFromLibrary].
///
/// Everything here degrades to doing nothing rather than throwing. A phone
/// that refuses notifications, a desktop build with no plugin behind it, a
/// test — none of those are errors a person capturing a note should ever see.
class NexReminders {
  NexReminders({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// Android needs a channel; both platforms need the tap handler bound
  /// before anything is scheduled, or a tap on a reminder opens the app with
  /// no idea which note it was about.
  static const _channelId = 'nex.reminders';

  /// Separate from the note channel so the daily nudge can be silenced in
  /// system settings without silencing the reminders someone set by hand.
  static const _dailyChannelId = 'nex.daily';

  bool _ready = false;
  Completer<void>? _initialising;

  /// Whether this phone will let Nex wake at an exact minute.
  ///
  /// *Read* on every [initialise] and re-read whenever permission is asked
  /// for. Android lets someone revoke this in Settings at any time, and a
  /// cached yes from last week is how a reminder quietly becomes
  /// approximate — but the worse failure was the opposite one, and it was
  /// live: this was only ever written inside [requestPermission], so on a
  /// cold launch it was false no matter what the OS actually allowed. Every
  /// alarm rebuilt by [syncFromLibrary] and every daily nudge re-armed by the
  /// timeline was therefore downgraded to an inexact alarm on every start,
  /// which Android batches — the reported symptom being a seven o'clock
  /// notification arriving at twenty past.
  bool _exactAlarms = false;

  /// Exact when allowed, approximate when not.
  ///
  /// `inexactAllowWhileIdle` was the only mode this used, and it is the wrong
  /// one for something a person calls a reminder: Android defers inexact
  /// alarms under Doze, sometimes by hours, so a note due at 9 arrives at
  /// lunchtime or not that day at all.
  ///
  /// `alarmClock` was the answer to that and went too far the other way. The
  /// plugin turns it into `AlarmManager.setAlarmClock`, whose documented job
  /// is not just to fire — the system "will typically also use the
  /// information supplied here to tell the user about this upcoming alarm".
  /// In practice that is the alarm icon in the status bar and the "Alarm"
  /// tile in quick settings, and Android shows the next alarm clock *on the
  /// device*, across every app. So every note reminder sooner than the user's
  /// real wake-up alarm quietly replaced it there: the one place you glance
  /// to check what time your phone will wake you was answering with a note.
  /// Tapping it opened Nex rather than the clock, because the plugin passes
  /// the notification's own intent as the `AlarmClockInfo` show intent.
  ///
  /// Reported from a phone whose owner had no idea where "Sat 10:00" had come
  /// from. Android's own guidance is that `setAlarmClock` "should only be
  /// used for [its] intended purpose", and a note that pops a notification is
  /// not an alarm clock.
  ///
  /// `exactAllowWhileIdle` keeps what the change was for. Android documents
  /// `setAlarmClock` as Doze-exempt "similar to setExactAndAllowWhileIdle" —
  /// the same exemption, from the same page — and both require the same
  /// exact-alarm permission and the same `RTC_WAKEUP`. What is given up is
  /// the system's extra prep-work and the exemption from the per-app rate
  /// limit on exact alarms, neither of which a handful of reminders a day
  /// comes near.
  ///
  /// This is the mode [_scheduleDailyNudge] already chose, for this reason,
  /// written down there before anyone noticed it applied here too.
  AndroidScheduleMode get _scheduleMode =>
      scheduleModeFor(exactAllowed: _exactAlarms);

  /// The mode decision on its own, so a test can reach it.
  ///
  /// Extracted for the same reason [scheduledDateFor] was: [schedule] returns
  /// early on anything that is not Android, so on a test host the whole
  /// decision is unreachable — not merely uncovered. `alarmClock` was chosen
  /// here, shipped, and only came back through someone noticing their phone's
  /// alarm chip had started announcing a note. Nothing in the suite could
  /// have said otherwise.
  @visibleForTesting
  static AndroidScheduleMode scheduleModeFor({required bool exactAllowed}) =>
      exactAllowed
      ? AndroidScheduleMode.exactAllowWhileIdle
      : AndroidScheduleMode.inexactAllowWhileIdle;

  /// Called with the note id when a reminder is tapped.
  void Function(String noteId)? onOpenNote;

  /// Called when the update notification is tapped.
  ///
  /// Separate from [onOpenNote] because the payload has to be told apart
  /// before it is used: a note id is opaque, so anything routed there is
  /// looked up as one, and "nex:update" would be a note nobody has.
  void Function()? onOpenUpdate;

  /// The note whose reminder started the app, if one did.
  ///
  /// [onDidReceiveNotificationResponse] is only called while the app is
  /// already running. A tap that launches it cold is reported once, here, by
  /// the plugin's launch details — so without this the case that matters most
  /// (the phone was in a pocket, the reminder arrived, the notification was
  /// tapped) was the one case that did nothing.
  ///
  /// Read once and cleared by [takeLaunchNoteId]: it describes a single tap,
  /// not a standing state, and a timeline that rebuilt would otherwise keep
  /// re-answering the same one.
  String? _launchNoteId;

  String? takeLaunchNoteId() {
    final id = _launchNoteId;
    _launchNoteId = null;
    return id;
  }

  /// Whether the app was started by a tap on the update notification.
  ///
  /// Read once and cleared, for the same reason [takeLaunchNoteId] is: it
  /// describes one tap, not a standing state.
  bool _launchedFromUpdate = false;

  /// Told what was actually handed to the operating system, every time.
  ///
  /// Wired to the shared diagnostics log by `NexServices`, and null in tests.
  /// A reminder arriving at an hour nobody asked for is the one bug in this
  /// class that leaves no trace: the note keeps the right time, the queue
  /// says an alarm exists, and the only thing that knows what the OS was
  /// actually told is the call that told it. This is that record.
  void Function(String message)? onDiagnostic;

  /// Whether a reminder's words must be kept off the lock screen.
  ///
  /// The title of a reminder is the note's own text, and Android's framework
  /// default (`VISIBILITY_PRIVATE`) renders it in full on the lock screen
  /// under the out-of-the-box "show all content" setting. The app lock covers
  /// Nex's own screens and stops at the shade — so someone who put their
  /// notes behind a fingerprint was still having them read out on a locked
  /// phone.
  ///
  /// Asked rather than assumed, and asked at schedule time, because the
  /// honest answer is the user's own lock setting: `secret` hides the
  /// notification from the lock screen entirely, and doing that to everyone
  /// would take a medication reminder off the lock screen of every person who
  /// never asked for a lock. `NexServices` wires this to `appLockEnabled`.
  ///
  /// Not `private`: that shows a redacted line only for someone who has
  /// *already* set Android to hide sensitive content, so it protects nobody
  /// who has not. And a redacted "Nex" still says a reminder exists and when,
  /// which for the kind of note that needs a lock is most of what was wanted.
  bool Function()? hideOnLockScreen;

  bool takeLaunchedFromUpdate() {
    final launched = _launchedFromUpdate;
    _launchedFromUpdate = false;
    return launched;
  }

  /// Whether reminders can work here at all.
  ///
  /// Android and iOS only. The desktop builds have no scheduling backend in
  /// this plugin worth relying on, and offering a reminder that never arrives
  /// is worse than not offering one.
  static bool get supported =>
      debugSupported ?? (!kIsWeb && (Platform.isAndroid || Platform.isIOS));

  /// Lets a test drive the scheduling with a fake plugin on a desktop VM.
  @visibleForTesting
  static bool? debugSupported;

  /// Takes back an alarm that has not gone off yet, and leaves alone one that
  /// has (2.1.9).
  ///
  /// The plugin's `cancel` does both: it also takes a notification already
  /// on the screen away. Every re-arm used to start with it — and opening
  /// the app re-arms everything — so each reminder that had fired vanished
  /// from the notification shade the moment the app was opened, before
  /// anyone had tapped or dismissed it. Re-arming needs no cancel at all:
  /// scheduling under the same id replaces the alarm. What remains is the
  /// alarm that should no longer ring, and only that one is taken back.
  Future<void> _withdraw(int id) async {
    try {
      final pending = await _plugin.pendingNotificationRequests();
      if (pending.any((request) => request.id == id)) {
        await _plugin.cancel(id: id);
      }
    } catch (_) {}
  }

  Future<void> initialise() async {
    if (_ready || !supported) return;
    final current = _initialising;
    if (current != null) return current.future;

    final completer = Completer<void>();
    _initialising = completer;
    try {
      await _initialise();
      completer.complete();
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
      // The originating caller gets this by `rethrow`; the completer's future
      // is a *second* future carrying the same error, and it has a listener
      // only when another caller happened to be waiting. With no concurrent
      // caller — the ordinary case — it would go unheard, and an unheard
      // error on a future is reported to the zone as an unhandled async
      // exception, which this app writes into its own crash log.
      completer.future.ignore();
      rethrow;
    } finally {
      if (identical(_initialising, completer)) _initialising = null;
    }
  }

  /// Declares the channels up front instead of letting the first
  /// notification create them.
  ///
  /// Two reasons, and the second is the one that matters. A channel that does
  /// not exist yet has nothing for the system's own notification settings to
  /// show, so "choose a sound" would open an empty screen on a phone where
  /// no reminder had ever fired. And a channel's sound, vibration and
  /// importance belong to the *user* from the moment it exists — Android will
  /// not let an app change them afterwards, by design — so the only honest
  /// place to offer those choices is the OS screen this makes reachable.
  ///
  /// Creating a channel that already exists is a no-op that keeps whatever
  /// the user has set, which is what makes this safe to run on every launch.
  Future<void> _createChannels() async {
    if (!Platform.isAndroid) return;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;
    try {
      await android.createNotificationChannel(
        AndroidNotificationChannel(
          _channelId,
          _text.reminders,
          description: _text.remindersAbout,
          importance: Importance.high,
        ),
      );
      await android.createNotificationChannel(
        AndroidNotificationChannel(
          _dailyChannelId,
          _text.daily,
          description: _text.dailyAbout,
          importance: Importance.defaultImportance,
        ),
      );
    } catch (error) {
      // Same rule as the exact-alarm probe above: a startup step that failed
      // must not land in [lastError], which answers "did the alarm I just
      // asked for get taken". The channels are created again on the next
      // launch, and the plugin creates one implicitly when it posts anyway.
      _initialisationWarning ??= 'channels: $error';
    }
  }

  /// What Android calls this app's notification channels in its settings,
  /// in Nex's own language (LOC-06). English until the app says otherwise.
  static NexChannelText _text = NexChannelText.en;
  static NexChannelText get channelText => _text;

  /// Names the channels in the app's language. Android lets an app rename a
  /// channel it owns at any time (never change its sound or importance), so
  /// re-creating them with the new names is all a language change takes.
  Future<void> useLanguage({required bool persian}) async {
    final text = persian ? NexChannelText.fa : NexChannelText.en;
    if (identical(text, _text)) return;
    _text = text;
    // Before initialisation the channels are created by it, already named.
    if (_ready) await _createChannels();
  }

  /// The channel ids the settings screen can send someone to.
  static const remindersChannel = _channelId;
  static const dailyChannel = _dailyChannelId;

  Future<void> _initialise() async {
    tz_data.initializeTimeZones();
    // Loading the database is only half of it. Without this `tz.local` is
    // UTC, and anything scheduled by wall-clock time — the daily nudge, and
    // any repeat matched on the time of day — lands at the wrong hour by
    // exactly the device's offset. A note reminder survived that because it
    // is scheduled from an instant rather than a clock face, which is why the
    // gap went unnoticed.
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (error) {
      // An unknown zone name leaves `tz.local` at UTC, which is where it was
      // before. Recorded rather than swallowed — into [_initialisationWarning],
      // which [schedule] merges into what the user actually sees, because
      // [lastError] is cleared at the start of every schedule and a value
      // written here would otherwise never survive to be read.
      _initialisationWarning = 'timezone: $error';
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_nex'),
        iOS: DarwinInitializationSettings(
          // Asked for at the moment a reminder is first set instead — a
          // permission prompt on first launch, before anyone has seen what
          // the app does, is the reliable way to be refused.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == _updatePayload) {
          onOpenUpdate?.call();
          return;
        }
        if (payload != null &&
            payload.isNotEmpty &&
            !payload.startsWith('nex:module:')) {
          onOpenNote?.call(payload);
        }
      },
    );
    await _createChannels();
    // Asked, not assumed, and before anything is scheduled. `canSchedule…`
    // only reads the current state — it shows nobody a prompt — which is what
    // makes it safe here, where a permission request would not be.
    if (Platform.isAndroid) {
      try {
        _exactAlarms =
            await _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.canScheduleExactNotifications() ??
            false;
      } catch (error) {
        // An older Android has no such concept and allows exact alarms
        // outright. Deliberately *not* recorded in [lastError]: that field
        // answers "did the alarm I just asked for get taken", and a startup
        // probe writing to it makes every reminder set afterwards report a
        // failure that has nothing to do with it.
        _exactAlarms = false;
      }
    }
    try {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        final payload = launch?.notificationResponse?.payload;
        // A cold tap on "ready to install" is the case that matters most for
        // the update notification, the same way it is for a reminder: the
        // phone was in a pocket and the app was not running.
        if (payload == _updatePayload) {
          _launchedFromUpdate = true;
        } else if (payload != null &&
            payload.isNotEmpty &&
            !payload.startsWith('nex:module:')) {
          _launchNoteId = payload;
        }
      }
    } catch (error) {
      // Not worth failing initialisation over — reminders still schedule and
      // still arrive. Recorded rather than swallowed, because a tap that goes
      // nowhere is exactly the kind of thing that gets called "flaky".
      lastError = 'launch details: $error';
    }
    _ready = true;
  }

  /// Whether the last schedule attempt failed, and what it said.
  ///
  /// Kept rather than swallowed. This used to be an empty catch, and the
  /// result was a feature that silently did nothing: the note kept its due
  /// date, the banner said the reminder was set, and no notification ever
  /// arrived — with nothing anywhere to say why. A rare, technical string is
  /// worth more than a confident lie.
  String? lastError;

  /// A problem noticed while initialising — most importantly a device zone
  /// that could not be resolved, which silently shifts every wall-clock
  /// schedule by the offset to UTC.
  ///
  /// [lastError] is cleared at the start of every [schedule], so a startup
  /// diagnostic written straight into it was overwritten before anyone read
  /// it. It lives here instead, and [schedule] merges it in — a reminder set
  /// on a phone whose zone never loaded reports the truth rather than a
  /// confident success.
  String? _initialisationWarning;

  /// Gate for the system "Alarms & reminders" screen.
  ///
  /// [requestPermission] used to open that screen on *every* reminder set,
  /// forever, on every Android 14+ phone where the OS ships with the
  /// permission off — once per reminder, even for someone who had already
  /// declined. The composition root sets this to answer "has the user already
  /// been asked once?", which turns a teleport-per-reminder into one
  /// explained prompt. Null (tests, desktop) means "ask freely".
  Future<bool> Function()? shouldRequestExactAlarms;

  /// Called after the exact-alarm screen was actually shown, so the gate can
  /// be latched.
  void Function()? onExactAlarmsRequested;

  /// Asks for permission, and answers whether it was given.
  ///
  /// Called when a reminder is actually being set, which is the only moment
  /// the request explains itself.
  ///
  /// Two permissions on Android, not one. Posting a notification is the
  /// obvious one; being allowed to wake at an exact minute is the one that
  /// decides whether "remind me at 9" means 9 or means somewhere after 9 —
  /// see [_scheduleMode].
  /// Surfaces the startup diagnostic on a schedule that reported no failure
  /// of its own.

  void _reportInitialisationWarning() {
    if (lastError == null || lastError!.isEmpty) {
      lastError = _initialisationWarning;
    }
  }

  /// The exact value handed to the platform for the instant [at].
  ///
  /// Extracted because [schedule] cannot be reached from a test at all:
  /// [supported] is false anywhere that is not a phone, so its first line
  /// returns and every conversion below it is unreachable from the suite.
  /// That is why a reminder arriving at the wrong hour was not something a
  /// test could have caught — not that the conversion was under-tested, but
  /// that no test could execute it. This is the part with an answer worth
  /// checking, so this is the part made checkable.
  ///
  /// `TZDateTime.from` keeps the *instant* and re-derives the wall clock in
  /// [location]. The instant is what a one-off reminder fires on; the wall
  /// clock is what a repeat matches on, which is why the location has to be
  /// the device's real zone and not the UTC that `tz.local` falls back to
  /// when the zone name fails to load.
  @visibleForTesting
  static tz.TZDateTime scheduledDateFor(DateTime at, [tz.Location? location]) =>
      tz.TZDateTime.from(at, location ?? tz.local);

  /// The first firing of a repeating reminder that is still ahead.
  ///
  /// A repeat's stored time is when the series *started*, which is in the past
  /// for every repeat that has fired even once — so scheduling it verbatim
  /// would be scheduling a time that has gone, and the alarm would never be
  /// taken. This moves it forward by whole periods, keeping the clock face it
  /// was set at.
  ///
  /// Local time throughout, then back to UTC: "every day at nine" means nine
  /// on the wall, and adding 24 hours across a daylight-saving boundary
  /// silently makes it eight or ten.
  ///
  /// The gap is closed by *arithmetic*, not a walk: a daily series started
  /// three years ago is ~1,100 steps behind, and the old one-day-at-a-time
  /// walk hit its 800-step guard at about twenty-six months — after which it
  /// returned the still-past start, [schedule] refused to schedule it, and a
  /// reminder someone still wanted retired itself silently on the next
  /// launch. The short bounded walk that remains only cleans up sub-period
  /// rounding (a DST-shifted wall clock, a `now` that lands between steps).
  @visibleForTesting
  static DateTime computeNextOccurrence(
    DateTime start,
    NoteRepeat repeat,
    DateTime now,
  ) {
    var at = start.toLocal();
    final step = switch (repeat) {
      NoteRepeat.once => 0,
      NoteRepeat.daily => 1,
      NoteRepeat.weekly => 7,
    };
    if (step == 0) return start;
    final localNow = now.toLocal();
    if (!at.isAfter(localNow)) {
      final daysBehind = localNow.difference(at).inDays;
      final periodsBehind = daysBehind ~/ step;
      // One more period than the whole ones that have passed — the first
      // firing that is still ahead. Wall-clock fields are rebuilt by hand so
      // a period is a period on the clock face, not 24 elapsed hours.
      at = DateTime(
        at.year,
        at.month,
        at.day + step * (periodsBehind + 1),
        at.hour,
        at.minute,
      );
    }
    // Bounded for the same reason as ever: a corrupt date that arithmetic
    // somehow cannot get past costs a skipped reminder, not a hung isolate.
    for (var guard = 0; guard < 800 && !at.isAfter(localNow); guard++) {
      at = DateTime(at.year, at.month, at.day + step, at.hour, at.minute);
    }
    return at.toUtc();
  }

  /// Confirms the OS actually took the alarm, and says so when it did not.
  ///
  /// `zonedSchedule` returning without throwing means the request was
  /// accepted, not that anything is pending — and the difference is where
  /// this feature spent its longest silence. Reading the queue back is the
  /// one check that distinguishes "scheduled" from "believed to be
  /// scheduled", and it costs one platform call per reminder.
  ///
  /// Returns null when the alarm is there, and a sentence when it is not.
  Future<String?> _verify(int id) async {
    try {
      final pending = await _plugin.pendingNotificationRequests();
      if (pending.any((request) => request.id == id)) return null;
      return 'the system did not keep the alarm';
    } catch (error) {
      // The queue could not be read. Not evidence either way, so it is not
      // reported as a failure — the schedule call itself did not throw.
      return null;
    }
  }

  /// Posts one notification now, and schedules a second a few seconds out.
  ///
  /// A diagnostic, and the fastest way to find out which half of this is
  /// broken on a given phone: the immediate one proves permission and the
  /// channel, the delayed one proves scheduling and delivery. Reminders failed
  /// for a year because those two look identical from inside the app — both
  /// are "nothing happened".
  ///
  /// **Deliberately has no caller.** It had a row in Settings twice and was
  /// taken out of Settings twice — once for a quieter settings screen, once
  /// because it came back in an imported working tree that did not know that.
  /// It is kept because the diagnostic is genuinely useful when reminders
  /// misbehave and rewriting it from scratch each time is worse; it is not
  /// wired up because the owner of this app has now twice decided it does not
  /// belong on that screen. Wiring it up again is a decision for them, not a
  /// loose end to tidy.
  ///
  /// Returns null on success, or what went wrong.
  /// The download notification's own id and channel, and the payload that
  /// tells a tap on it apart from a tap on a reminder.
  ///
  /// Id 3, the last of the block [reservedIds] describes: 0 is the daily
  /// nudge and 1 and 2 are the diagnostics. A note reminder is kept out of
  /// all four by [idFor].

  static const _updateId = 3;
  static const _updateChannelId = 'nex.updates';
  static const _updatePayload = 'nex:update';

  /// The two ids [sendTestNotification] uses, kept away from note hashes and
  /// from [_dailyId].
  static const _testId = 1;

  /// How many ids at the bottom of the space this class keeps for itself:
  /// [_dailyId] (0), the two [sendTestNotification] ids (1 and 2), and
  /// [_updateId] (3).
  ///
  /// A note's reminder is keyed on a hash, so it can land on any of them —
  /// [idFor] is what keeps it out, and [syncFromLibrary] is what keeps the
  /// prune from cancelling them. Both read this rather than listing the ids
  /// again, because the last time they were listed separately one of the two
  /// lists gained an entry and the other did not.
  @visibleForTesting
  static const reservedIds = 4;

  /// The one repeating notification: a nudge at a time the user picked.
  ///
  /// Its own id, and it stays its own because [idFor] bumps a note out of the
  /// reserved block — not because a note could never hash to it. This comment
  /// used to claim the second thing ("zero is not a hash any string produces
  /// here"), which is false, and [idFor] a few hundred lines below says so
  /// outright. A reader who believed this one would conclude the bump was
  /// redundant and remove it, and a note landing on 0 would then cancel this
  /// nudge — or the update download at 3 — silently and permanently.
  static const _dailyId = 0;

  /// A commitment's alarm id.
  ///
  /// Prefixed before hashing so a commitment and a note that happen to share
  /// an id — nothing stops that, both are UUIDs from the same generator —
  /// cannot land on the same alarm and cancel each other.
  @visibleForTesting
  static int commitmentIdFor(String commitmentId) =>
      idFor('commitment:$commitmentId');

  /// «Cycle»'s alarms, by key: `soon`, `pill`, and `log0`…`log9` for the
  /// evenings of a period.
  ///
  /// Kept out of [syncFromLibrary]'s sweep: the library does not know
  /// them, `CycleReminders` does, and it re-arms them whenever the cycle
  /// changes or the app opens.
  static final cycleKeys = [
    'soon',
    'pill',
    for (var i = 0; i < 10; i++) 'log$i',
  ];

  static final Set<int> _cycleIds = {
    for (final key in cycleKeys) cycleIdFor(key),
  };

  @visibleForTesting
  static int cycleIdFor(String key) => idFor('cycle:$key');

  /// A scheduled note's arrival alarm id — prefixed, like
  /// [commitmentIdFor], so it never collides with a reminder later set on
  /// the same note.
  @visibleForTesting
  static int arrivalIdFor(String noteId) => idFor('scheduled:$noteId');

  /// A stable 31-bit id derived from the note's own id.
  ///
  /// The plugin keys alarms by int, and notes by string. Hashing means
  /// rescheduling the same note replaces its alarm rather than adding a
  /// second one, without keeping a mapping table that could drift.
  ///
  /// The low ids are reserved — see [reservedIds]. A 31-bit hash *can* land
  /// there — an older comment claimed it could not, and that claim was false
  /// — in which case setting that note's reminder would silently replace one
  /// of them, and it would silently replace the reminder, each cancelling the
  /// other forever. Bumping past the reserved block costs a handful of ids at
  /// one end of the space and removes the entire class of bug.
  ///
  /// The bump is `+ reservedIds`, not `+ 3`. It was `+ 3` when there were
  /// three reserved ids, so when the download notification took id 3 the
  /// bump started landing a note straight on top of it: a note whose hash was
  /// 0 became 3, which is the download. The whole point of the block is that
  /// its size is one number, used by everything that has to respect it.

  @visibleForTesting
  static int idFor(String noteId) => unreserved(noteId.hashCode & 0x7fffffff);

  /// Moves [id] out of the reserved block.
  ///
  /// Split out from [idFor] so it can be tested for what it does. The test
  /// that was here fed [idFor] the string `'note-0'` and checked the answer
  /// was not 0 — which it is not, and would not have been however wrong this
  /// arithmetic was, because that string's hash was never in the block to
  /// begin with. A test that cannot reach the line it is about is not a test
  /// of it.
  @visibleForTesting
  static int unreserved(int id) => id < reservedIds ? id + reservedIds : id;

  static int _idFor(String noteId) => idFor(noteId);

  static String _clamp(String text, int max) {
    final one = text.replaceAll(RegExp(r'\s+'), ' ');
    return one.length <= max ? one : '${one.substring(0, max)}…';
  }
}

/// The names and descriptions of Nex's notification channels, in one
/// language.
class NexChannelText {
  const NexChannelText._({
    required this.reminders,
    required this.remindersAbout,
    required this.daily,
    required this.dailyAbout,
    required this.updates,
    required this.updatesAbout,
  });

  final String reminders;
  final String remindersAbout;
  final String daily;
  final String dailyAbout;
  final String updates;
  final String updatesAbout;

  static const en = NexChannelText._(
    reminders: 'Reminders',
    remindersAbout: 'Notes you asked Nex to bring back up',
    daily: 'Daily digest',
    dailyAbout: 'One reminder a day, at a time you chose',
    updates: 'Updates',
    updatesAbout: 'Downloading a new version of Nex',
  );

  static const fa = NexChannelText._(
    reminders: 'یادآورها',
    remindersAbout: 'یادداشت‌هایی که خواستید Nex دوباره نشانتان بدهد',
    daily: 'خلاصهٔ روزانه',
    dailyAbout: 'روزی یک یادآوری، در ساعتی که خودتان انتخاب کردید',
    updates: 'به‌روزرسانی‌ها',
    updatesAbout: 'دریافت نسخهٔ تازهٔ Nex',
  );
}
