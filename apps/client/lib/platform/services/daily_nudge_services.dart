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
        '${p.briefHabitsAllowed}|${p.appLockEnabled}|'
        '${p.dailyNudgeMemories}|${p.solarCalendar}';
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
    _nudgeFlight = (_nudgeFlight ?? Future<void>.value())
        .catchError((Object _) {})
        .then((_) async {
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
            // A failure recorded while the app was not running — a boot whose
            // alarm Android refused, a post the shade dropped — is worth one line
            // in the diagnostics file. It is read before this rebuild replaces the
            // state, so a later success cannot erase the evidence of an earlier
            // failure nobody was awake to see.
            if (NexDailyNudgeNative.supported) {
              final previous = await NexDailyNudgeNative.lastError();
              if (previous != null) {
                reminders.onDiagnostic?.call('nudge alarm: $previous');
              }
            }
            // The nudge plans against the note, not against the hand-off list
            // the timeline drains at launch. Writing any **Done** from the
            // shade into the library first means the answer no longer depends
            // on whether `syncRinging` ran before this plan.
            await settleReminderAcks();
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
                            n.reminderAckedAt?.toIso8601String(),
                            n.setAsideUntil?.toIso8601String(),
                          ],
                      ],
                      'memories': [
                        for (final n in source.memories)
                          [n.id, n.updatedAt.toIso8601String()],
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
            // A reminder answered today is a fact about today, read from the
            // note itself. It is not a reason to forget the reminder: a
            // repeating one comes back at its own time, and the plan for every
            // later day still carries it.
            final answeredToday = source.notes.any(
              (note) => note.reminderAnsweredOn(now),
            );
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
                !answeredToday &&
                met.isEmpty &&
                store.getString('dailyNudge.summarySource') == key &&
                store.getInt('dailyNudge.summaryAt') ==
                    summaryAt?.millisecondsSinceEpoch &&
                !(_preferences.aiDaySummaryIncludesHabits &&
                    !_preferences.briefHabitsAllowed);
            final input = (
              source: NexNudgeSnapshot(
                notes: source.notes,
                commitments: source.commitments
                    .where((item) => !met.contains(item.id))
                    .toList(),
                hasData: source.hasData,
                memories: _preferences.dailyNudgeMemories
                    ? source.memories
                    : const [],
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
              solarCalendar: _preferences.solarCalendar,
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
              final armed = await NexDailyNudgeNative.configure(plan);
              if (!armed) {
                // The plan was written but no alarm was accepted, so the nudge
                // will not arrive. `_nudgePlanKey` is deliberately not set: the
                // next update tries again rather than treating a refused alarm as
                // the finished state of this plan.
                reminders.lastError = NexDailyNudgeNative.notArmed;
                reminders.onDiagnostic?.call(
                  'nudge alarm: ${NexDailyNudgeNative.notArmed}',
                );
                result.complete(NexDailyNudgeNative.notArmed);
                return;
              }
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
