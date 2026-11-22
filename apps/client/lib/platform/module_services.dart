part of 'nex_services.dart';

/// Module records (ADR-040, `docs/17-modules.md`).
extension NexModuleServices on NexServices {
  /// Module records — reached through a module's own NexModuleStore, never
  /// directly (lib/modules/nex_module_store.dart).
  Future<List<ModuleRecord>> moduleRecords(String module, String kind) =>
      worker.moduleRecords(module, kind);

  Future<ModuleRecord?> moduleRecord(String module, String kind, String id) =>
      worker.moduleRecord(module, kind, id);

  Future<ModuleRecord> modulePut(
    String module,
    String kind,
    String id,
    Map<String, Object?> body,
  ) => _moduleWrite(
    module,
    worker.modulePut(module, kind, id, body),
    kind: kind,
    sources: {'$kind:$id'},
  );

  Future<void> moduleDelete(String module, String kind, String id) =>
      _moduleWrite(
        module,
        worker.moduleDelete(module, kind, id),
        kind: kind,
        sources: {'$kind:$id'},
      );

  /// Several of [module]'s records in one storage transaction — what a
  /// record bundle's delete runs in place of the journal it used to keep.
  Future<void> moduleDeleteMany(
    String module,
    List<({String kind, String id})> records,
  ) => _moduleWrite(
    module,
    worker.moduleDeleteMany(module, records),
    sources: {for (final record in records) '${record.kind}:${record.id}'},
  );

  /// Everything [module] saved, gone — and, as with Cycle, the backups on
  /// this phone that still held it replaced by one that does not.
  ///
  /// Whether or not this removed anything: a module that emptied its own
  /// records from its own screen left nothing here to count, while the
  /// older backups still held them (1.99.96 reviews, SEC-07).
  Future<void> moduleDeleteAll(String module) async {
    await _moduleWrite(module, worker.moduleDeleteAll(module));
    await _replaceBackupsHoldingDeleted();
  }

  bool moduleRemindersEnabled(String module) =>
      nexModuleActive(module, _preferences);

  Future<bool> setModuleReminder(
    String module,
    String key, {
    required String sourceKind,
    required String sourceId,
    required DateTime at,
    required String title,
    required String body,
    bool daily = false,
  }) async {
    // A daily reminder is given as a time of day: its first ring is the next
    // time that is still ahead, today or tomorrow.
    if (daily) at = nexNextDailyRing(at, DateTime.now());
    if (!moduleRemindersEnabled(module) || !at.isAfter(DateTime.now())) {
      return false;
    }
    if (!await reminders.requestPermission() ||
        !moduleRemindersEnabled(module)) {
      return false;
    }
    final source = await worker.moduleRecord(module, sourceKind, sourceId);
    if (source == null || source.body['archived'] == true) return false;
    if (module == 'habits' &&
        sourceKind == 'habit' &&
        Habit.fromRecord(source).isPausedOn(at.toLocal())) {
      return false;
    }
    await worker.modulePut(module, '__reminder', key, {
      'sourceKind': sourceKind,
      'sourceId': sourceId,
      'at': at.toUtc().toIso8601String(),
      // The face of the clock the person chose, kept beside the instant.
      // Restoring a daily reminder from the instant alone hands its hour to
      // `at.toLocal()`, and once the zone or a daylight-saving rule has
      // moved since it was set, nine on the wall comes back as eight. The
      // instant stays for one-shot reminders, and for daily records written
      // before the face was kept.
      if (daily) 'wallMinutes': at.hour * 60 + at.minute,
      'title': title,
      'body': body,
      if (daily) 'repeat': 'daily',
    });
    return reminders.scheduleModule(
      module,
      key,
      at: at,
      title: title,
      body: body,
      daily: daily,
      sourceKind: sourceKind,
      sourceId: sourceId,
      habitCounted: module == 'habits' && sourceKind == 'habit'
          ? source.body['goal'] is num && (source.body['goal'] as num) > 1
          : null,
    );
  }

  Future<void> clearModuleReminder(String module, String key) async {
    await worker.moduleDelete(module, '__reminder', key);
    await reminders.cancelModule(module, key);
  }

  /// Automatic housekeeping withdraws future alarms, preserving a rung notice.
  Future<void> withdrawModuleReminder(String module, String key) async {
    await worker.moduleDelete(module, '__reminder', key);
    await reminders.withdrawModule(module, key);
  }

  Future<void> cancelModuleReminders(String module) =>
      reminders.cancelModule(module);

  /// Rebuilds only available, installed modules; paused modules stay silent.
  Future<Set<int>> restoreModuleReminders() async {
    final wanted = <int>{};
    for (final module in nexModules) {
      if (!moduleRemindersEnabled(module.id) || module.id == 'cycle') continue;
      for (final record in await worker.moduleRecords(
        module.id,
        '__reminder',
      )) {
        await _reconcileReminderRecord(module.id, record, wanted: wanted);
      }
    }
    return wanted;
  }

  /// Puts the reminders whose sources were just written back in step with
  /// them — and nothing else. Every module write used to answer with a
  /// rebuild of every module's every reminder: one habit checked off
  /// rescheduled the occasions, the words and every other habit before the
  /// check-in's own write could resolve. A reminder's source is the one
  /// thing a write can change about it, so this reads [module]'s reminders
  /// once and touches only those pointing at [sources] ("kind:id").
  Future<void> _reconcileModuleSources(
    String module,
    Set<String> sources,
  ) async {
    for (final record in await worker.moduleRecords(module, '__reminder')) {
      final body = record.body;
      if (!sources.contains('${body['sourceKind']}:${body['sourceId']}')) {
        continue;
      }
      await _reconcileReminderRecord(module, record);
    }
  }

  /// One `__reminder` record, put back in step with its source: re-armed
  /// when the source exists and its moment is still ahead, cancelled when
  /// it does not, and left as a shown notice when its moment has passed.
  /// [wanted], when given, collects the alarm ids the launch-time sweep
  /// must leave alone.
  Future<void> _reconcileReminderRecord(
    String module,
    ModuleRecord record, {
    Set<int>? wanted,
  }) async {
    final b = record.body;
    final daily = b['repeat'] == 'daily';
    final at = nexNextDailyReminderRing(b, DateTime.now());
    if (at == null ||
        b['sourceKind'] is! String ||
        b['sourceId'] is! String ||
        b['title'] is! String ||
        b['body'] is! String) {
      return;
    }
    final source = await worker.moduleRecord(
      module,
      b['sourceKind'] as String,
      b['sourceId'] as String,
    );
    if (source == null || source.body['archived'] == true) {
      await reminders.cancelModule(module, record.id);
      return;
    }
    if (module == 'habits' &&
        b['sourceKind'] == 'habit' &&
        Habit.fromRecord(source).isPausedOn(at.toLocal())) {
      // Keep the stored preferences available for a legacy daily reminder.
      // Habits re-arms the next eligible alarm after the rest is saved.
      await reminders.withdrawModule(module, record.id);
      return;
    }
    if (module == 'habits') {
      final target = NexModuleTarget(
        module,
        kind: b['sourceKind'] as String,
        id: b['sourceId'] as String,
        key: record.id,
        day:
            '${at.toLocal().year.toString().padLeft(4, '0')}-${at.toLocal().month.toString().padLeft(2, '0')}-${at.toLocal().day.toString().padLeft(2, '0')}',
      );
      wanted?.add(NexReminders.snoozeIdFor(target.payload));
    }
    // Past: it has rung, or was missed. Its notification, if showing,
    // stays until it is tapped or dismissed (2.1.9).
    if (!at.isAfter(DateTime.now())) {
      await reminders.withdrawModule(module, record.id);
      return;
    }
    wanted?.add(NexModuleAlarms.moduleId(module, record.id));
    await reminders.scheduleModule(
      module,
      record.id,
      at: at,
      title: b['title'] as String,
      body: b['body'] as String,
      daily: daily,
      sourceKind: b['sourceKind'] as String,
      sourceId: b['sourceId'] as String,
      habitCounted: module == 'habits' && b['sourceKind'] == 'habit'
          ? source.body['goal'] is num && (source.body['goal'] as num) > 1
          : null,
    );
  }
}

/// The first moment at or after [now] that shows the clock face of [at]: the
/// time a daily reminder was set for, today if it is still ahead and tomorrow
/// if not. Local time — "every day at nine" is nine on the wall, daylight
/// saving included.
DateTime nexNextDailyRing(DateTime at, DateTime now) {
  final local = at.toLocal();
  var next = DateTime(now.year, now.month, now.day, local.hour, local.minute);
  if (!next.isAfter(now)) {
    next = DateTime(now.year, now.month, now.day + 1, local.hour, local.minute);
  }
  return next;
}

/// When the reminder [body] describes rings next, from [now] on.
///
/// A daily reminder is kept by the face of the clock it was set for
/// (`wallMinutes`), and that face is what the next ring is read from. The
/// stored instant alone hands its hour to `at.toLocal()`, and once the zone
/// or a daylight-saving rule has moved since it was set, nine on the wall
/// comes back as eight. Records written before the face was kept fall back
/// to the instant, which is what they always did; a one-shot reminder is its
/// instant, untouched. Null when the record holds no moment that parses.
DateTime? nexNextDailyReminderRing(Map<String, Object?> body, DateTime now) {
  final at = body['at'] is String
      ? DateTime.tryParse(body['at'] as String)
      : null;
  if (body['repeat'] != 'daily') return at;
  final wall = body['wallMinutes'];
  final face = wall is int && wall >= 0 && wall < 1440
      ? DateTime(now.year, now.month, now.day, wall ~/ 60, wall % 60)
      : at?.toLocal();
  return face == null ? null : nexNextDailyRing(face, now);
}
