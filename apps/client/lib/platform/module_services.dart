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
  );

  Future<void> moduleDelete(String module, String kind, String id) =>
      _moduleWrite(module, worker.moduleDelete(module, kind, id), kind: kind);

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

  bool moduleRemindersEnabled(String module) => nexModules.any(
    (m) => m.id == module && m.available && m.isOn(_preferences),
  );

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
    await worker.modulePut(module, '__reminder', key, {
      'sourceKind': sourceKind,
      'sourceId': sourceId,
      'at': at.toUtc().toIso8601String(),
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
    );
  }

  Future<void> clearModuleReminder(String module, String key) async {
    await worker.moduleDelete(module, '__reminder', key);
    await reminders.cancelModule(module, key);
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
        final b = record.body;
        final daily = b['repeat'] == 'daily';
        var at = b['at'] is String
            ? DateTime.tryParse(b['at'] as String)
            : null;
        if (daily && at != null) at = nexNextDailyRing(at, DateTime.now());
        if (at == null ||
            b['sourceKind'] is! String ||
            b['sourceId'] is! String ||
            b['title'] is! String ||
            b['body'] is! String) {
          continue;
        }
        final source = await worker.moduleRecord(
          module.id,
          b['sourceKind'] as String,
          b['sourceId'] as String,
        );
        if (source == null || source.body['archived'] == true) {
          await reminders.cancelModule(module.id, record.id);
          continue;
        }
        // Past: it has rung, or was missed. Its notification, if showing,
        // stays until it is tapped or dismissed (2.1.9).
        if (!at.isAfter(DateTime.now())) {
          await reminders.withdrawModule(module.id, record.id);
          continue;
        }
        wanted.add(NexModuleAlarms.moduleId(module.id, record.id));
        await reminders.scheduleModule(
          module.id,
          record.id,
          at: at,
          title: b['title'] as String,
          body: b['body'] as String,
          daily: daily,
        );
      }
    }
    return wanted;
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
