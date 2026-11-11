import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/screens/timeline/timeline_model.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_core/nex_core.dart';

import 'support/nex_harness.dart';

/// W4.2: what the timeline shows can be checked without building it.
void main() {
  late NexTestHarness harness;
  late TimelineModel model;

  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_timeline_model_');
    model = TimelineModel(
      services: harness.services,
      preferences: harness.preferences,
    );
  });

  tearDown(() async {
    model.dispose();
    await harness.dispose();
  });

  test(
    'tagging the last bare note hides and clears the untagged filter',
    () async {
      final note = (await harness.services.captureText('bare'))!;
      await model.load();
      await model.loadFilterTags();
      expect(model.hasUntagged, isTrue);
      await model.selectUntagged(true);
      await harness.services.addTag(noteId: note.id, name: 'work');
      await model.load();
      await model.loadFilterTags();
      expect(model.hasUntagged, isFalse);
      expect(model.onlyUntagged, isFalse);
      expect(model.notes.single.id, note.id);
    },
  );

  test(
    'untagged is exclusive with tags and layers with type and reminders',
    () async {
      final bare = (await harness.services.captureText('bare'))!;
      final tagged = (await harness.services.captureText('tagged'))!;
      final tag = await harness.services.addTag(
        noteId: tagged.id,
        name: 'work',
      );
      await harness.services.setDueAt(
        bare.id,
        DateTime.now().add(const Duration(days: 1)),
      );
      await model.load();
      await model.selectTags({tag.id});
      await model.selectUntagged(true);
      expect(model.selectedTagIds, isEmpty);
      expect(model.notes.map((n) => n.id), [bare.id]);
      await model.selectType(NoteType.text);
      await model.selectOnlyReminders(true);
      expect(model.notes.map((n) => n.id), [bare.id]);
      await model.selectType(NoteType.checklist);
      expect(model.notes, isEmpty);
      await model.selectTags({tag.id});
      expect(model.onlyUntagged, isFalse);
      await model.selectUntagged(true);
      await model.clearFilters();
      expect(model.filtering, isFalse);
      expect(model.onlyUntagged, isFalse);
      expect(model.notes, hasLength(2));
      expect(
        (await harness.services.listTags()).any(
          (t) => t.name == 'Untagged' || t.name == 'بدون تگ',
        ),
        isFalse,
      );
    },
  );

  test(
    'nothing is known before the first read, which is not "empty"',
    () async {
      expect(model.all, isNull);
      await model.load();
      expect(model.all, isEmpty);
      expect(model.loadFailed, isFalse);
    },
  );

  test('filters layer: tags OR-ed, then the type, then reminders', () async {
    final work = (await harness.services.captureText('work item'))!;
    final home = (await harness.services.captureText('home item'))!;
    await harness.services.captureText('untagged');
    final list = (await harness.services.captureChecklist([
      const ChecklistItem(text: 'milk', done: false),
    ]))!;
    final workTag = await harness.services.addTag(
      noteId: work.id,
      name: 'work',
    );
    final homeTag = await harness.services.addTag(
      noteId: home.id,
      name: 'home',
    );
    await harness.services.addTag(noteId: list.id, name: 'home');
    await model.load();
    expect(model.notes, hasLength(4));

    await model.selectTags({workTag.id, homeTag.id});
    expect(
      model.notes.map((n) => n.id),
      unorderedEquals([work.id, home.id, list.id]),
    );
    expect(model.filtering, isTrue);

    await model.selectType(NoteType.checklist);
    expect(model.notes.map((n) => n.id), [list.id]);

    await model.selectOnlyReminders(true);
    expect(model.notes, isEmpty);

    await model.clearFilters();
    expect(model.notes, hasLength(4));
    expect(model.filtering, isFalse);
  });

  test('folded groups are remembered across a restart', () async {
    model.setCollapsedGroups({'week', 'older'});
    final again = TimelineModel(
      services: harness.services,
      preferences: harness.preferences,
    );
    addTearDown(again.dispose);
    expect(again.collapsedGroups, {'week', 'older'});
  });

  test(
    'a one-off reminder that has rung is retired; a repeating one is not',
    () async {
      final once = (await harness.services.captureText('once'))!;
      final weekly = (await harness.services.captureText('weekly'))!;
      final past = DateTime.now().toUtc().subtract(const Duration(hours: 1));
      await harness.services.setDueAt(once.id, past);
      await harness.services.setDueAt(
        weekly.id,
        past,
        repeat: NoteRepeat.weekly,
      );
      await model.load();

      await model.retireSpentReminders();

      expect((await harness.services.getById(once.id))!.dueAt, isNull);
      expect((await harness.services.getById(weekly.id))!.dueAt, isNotNull);
    },
  );
}
