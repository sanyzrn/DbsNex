import 'package:nex_client/modules/module_api.dart';

import 'habit_reminder.dart';

/// The platform's record bundle, with a habit's reminder setting captured
/// beside it — what its Undo needs to put a deleted habit back exactly as
/// it was. Before the platform bundle learned to capture extra records
/// (`also`), this file was a fork of the whole class, fix for fix.
typedef RecordBundle = NexModuleRecordBundle;

/// Captures [id], its checks, its edit draft and its reminder setting.
Future<RecordBundle> captureHabitBundle(NexModuleStore store, String id) =>
    RecordBundle.capture(
      store,
      'habit',
      id,
      'check',
      'habit',
      also: [(kind: habitRemindKind, id: id)],
    );
