import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/platform/nex_services.dart';

import '../../support/nex_harness.dart';

/// Shared pieces for the upgrade tests: a harness that disposes itself, a
/// pump under the real localisations, a record builder and a store whose
/// reminders are on so the planner's work can be inspected.

Future<NexTestHarness> upgradeHarness() async {
  final harness = await NexTestHarness.create(name: 'medicine_upgrade_');
  addTearDown(harness.dispose);
  return harness;
}

Future<void> pumpMedicine(
  WidgetTester tester,
  Widget home, {
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  );
  await tester.pumpAndSettle();
}

ModuleRecord medicineRecord(String id, Map<String, Object?> body) =>
    ModuleRecord(
      module: 'medicine',
      kind: 'medicine',
      id: id,
      body: body,
      updatedAt: DateTime.now(),
    );

/// A store whose reminders are on, recording what the planner would arm.
class ReminderStore extends NexModuleStore {
  ReminderStore(NexServices services) : super(services, 'medicine');

  final armed =
      <
        ({String key, String title, String body, DateTime at, String sourceId})
      >[];
  final _records = <String, Map<String, Object?>>{};

  @override
  bool get remindersEnabled => true;

  @override
  Future<List<ModuleRecord>> list(String kind) async {
    if (kind != '__reminder') {
      return super.list(kind);
    }
    return [
      for (final entry in _records.entries)
        ModuleRecord(
          module: 'medicine',
          kind: kind,
          id: entry.key,
          body: entry.value,
          updatedAt: DateTime.now(),
        ),
    ];
  }

  @override
  Future<bool> setReminder(
    String key, {
    required String sourceKind,
    required String sourceId,
    required DateTime at,
    required String title,
    required String body,
  }) async {
    armed.add((key: key, title: title, body: body, at: at, sourceId: sourceId));
    _records[key] = {'sourceKind': sourceKind, 'sourceId': sourceId};
    return true;
  }

  /// Daily reminders, armed for an every-day routine (2.8.4), by key.
  final daily = <String>{};

  @override
  Future<bool> setDailyReminder(
    String key, {
    required String sourceKind,
    required String sourceId,
    required DateTime at,
    required String title,
    required String body,
  }) async {
    daily.add(key);
    return setReminder(
      key,
      sourceKind: sourceKind,
      sourceId: sourceId,
      at: at,
      title: title,
      body: body,
    );
  }

  @override
  Future<void> withdrawReminder(String key) async {
    _records.remove(key);
  }
}
