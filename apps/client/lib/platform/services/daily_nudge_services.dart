part of '../nex_services.dart';

extension NexDailyNudgeServices on NexServices {
  void _startDailyNudge() {
    _nudgePreferenceListener = _onNudgePreferences;
    _preferences.addListener(_nudgePreferenceListener!);
    _onNudgePreferences();
  }

  void _onNudgePreferences() {
    final p = _preferences;
    final signature =
        '${p.dailyNudge}|${p.dailyNudgeMinutes}|${p.locale}|${p.shortDisplayName}|'
        '${p.aiEnabled}|${p.showDaySummary}|${p.aiDaySummaryAt}|'
        '${p.briefHabitsAllowed}|${p.appLockEnabled}';
    if (_nudgePreferences == signature) return;
    _nudgePreferences = signature;
    _queueDailyNudge(preferencesChanged: true);
  }

  void _queueDailyNudge({bool preferencesChanged = false}) {
    if (_closed ||
        _nudgePreferenceListener == null ||
        !NexReminders.supported) {
      return;
    }
    if (!_preferences.dailyNudge && !preferencesChanged) return;
    _nudgeTimer?.cancel();
    _nudgeTimer = Timer(const Duration(milliseconds: 300), () {
      unawaited(updateDailyNudge());
    });
  }

  Future<T> _afterNudgeWrite<T>(Future<T> write) async {
    final result = await write;
    _queueDailyNudge();
    return result;
  }

  /// Serialized, supersedable local work; no provider request is made here.
  Future<String?> updateDailyNudge({bool freshlyGeneratedSummary = false}) {
    if (_closed ||
        _nudgePreferenceListener == null ||
        !NexReminders.supported) {
      return Future.value(null);
    }
    _nudgeTimer?.cancel();
    final epoch = ++_nudgeEpoch;
    final result = Completer<String?>();
    _nudgeFlight = (_nudgeFlight ?? Future<void>.value()).catchError((Object _) {}).then((
      _,
    ) async {
      if (_closed || epoch != _nudgeEpoch) {
        result.complete(null);
        return;
      }
      try {
        if (!_preferences.dailyNudge) {
          _nudgePlanKey = null;
          await reminders.cancelDaily();
          result.complete(null);
          return;
        }
        final source = await worker.nudgeSnapshot();
        if (_closed || epoch != _nudgeEpoch) {
          result.complete(null);
          return;
        }
        final key = sha256
            .convert(
              utf8.encode(
                jsonEncode({
                  'revision': source.revision,
                  'hasData': source.hasData,
                  'notes': [
                    for (final n in source.notes)
                      [
                        n.id,
                        n.content,
                        n.caption,
                        n.updatedAt.toIso8601String(),
                        n.isUrgent,
                        n.dueAt?.toIso8601String(),
                        n.dueRepeat.name,
                        n.setAsideUntil?.toIso8601String(),
                      ],
                  ],
                  'commitments': [
                    for (final c in source.commitments)
                      [
                        c.id,
                        c.title,
                        c.dueAt.toIso8601String(),
                        c.cadence.name,
                        c.every,
                        c.paused,
                        c.timesPerDay,
                        c.details,
                      ],
                  ],
                }),
              ),
            )
            .toString();
        final store = await SharedPreferences.getInstance();
        await store.reload();
        final acknowledged =
            (store.getStringList('reminders.acked') ?? const []).toSet();
        final met = {
          for (final item
              in store.getStringList('reminders.met') ?? const <String>[])
            if (item.lastIndexOf('|') case final split when split > 0)
              item.substring(0, split),
        };
        final summaryAt = _preferences.aiDaySummaryAt;
        if (freshlyGeneratedSummary &&
            _preferences.aiEnabled &&
            _preferences.showDaySummary &&
            summaryAt != null) {
          await store.setString('dailyNudge.summarySource', key);
          await store.setInt(
            'dailyNudge.summaryAt',
            summaryAt.millisecondsSinceEpoch,
          );
        }
        final now = DateTime.now();
        final localeKey =
            _preferences.locale?.languageCode ??
            Platform.localeName.split('_').first;
        final planKey =
            '$key|$localeKey|$_nudgePreferences|${NexDailyNudgeContent.dayKey(now)}|${now.timeZoneOffset}';
        if (_nudgePlanKey == planKey && !freshlyGeneratedSummary) {
          result.complete(null);
          return;
        }
        final summaryMatches =
            acknowledged.isEmpty &&
            met.isEmpty &&
            store.getString('dailyNudge.summarySource') == key &&
            store.getInt('dailyNudge.summaryAt') ==
                summaryAt?.millisecondsSinceEpoch &&
            !(_preferences.aiDaySummaryIncludesHabits &&
                !_preferences.briefHabitsAllowed);
        final input = (
          source: NexNudgeSnapshot(
            notes: [
              for (final note in source.notes)
                acknowledged.contains(note.id)
                    ? note.copyWith(clearDueAt: true)
                    : note,
            ],
            commitments: source.commitments
                .where((item) => !met.contains(item.id))
                .toList(),
            hasData: source.hasData,
          ),
          now: now,
          minutes: _preferences.dailyNudgeMinutes,
          persian: localeKey == 'fa',
          title: DailyNudge.greeting(
            _preferences,
            _preferences.dailyNudgeMinutes,
          ),
          aiEnabled: _preferences.aiEnabled,
          summaryEnabled: _preferences.showDaySummary,
          sourceMatches: summaryMatches,
          summary: _preferences.aiDaySummaryText,
          summaryAt: summaryAt,
          secret: _preferences.appLockEnabled,
        );
        final plan = await nexComputeDailyNudgePlan(input);
        plan['includesHabits'] = _preferences.aiDaySummaryIncludesHabits;
        if (_closed || epoch != _nudgeEpoch || !_preferences.dailyNudge) {
          result.complete(null);
          return;
        }
        if (NexDailyNudgeNative.supported) {
          // One migration cancellation removes the legacy static daily repeat.
          if (store.getInt('dailyNudge.nativeRevision') != 1) {
            await reminders.cancelDaily();
            await store.setInt('dailyNudge.nativeRevision', 1);
          }
          reminders.lastError = null;
          await NexDailyNudgeNative.configure(plan);
        } else {
          // Other supported platforms keep their existing alarm infrastructure.
          // A neutral local fallback never repeats an outdated dated claim.
          final fallback = plan['fallback']! as List<String>;
          await reminders.scheduleDaily(
            hour: _preferences.dailyNudgeMinutes ~/ 60,
            minute: _preferences.dailyNudgeMinutes % 60,
            title: input.title,
            body: fallback[now.day % fallback.length],
          );
        }
        _nudgePlanKey = planKey;
        result.complete(reminders.lastError);
      } catch (error) {
        unawaited(NexCrashLog.handled('nudge.schedule', error));
        result.complete('$error');
      }
    });
    return result.future;
  }
}
