import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/platform/note_search.dart';

import 'support/in_process_db.dart';

/// The chip filters. The controller has carried a tag set, a type set and a
/// date range since search moved onto the timeline; nothing in the UI could
/// write to them, and these tests pin the write path the filter sheet uses —
/// including that every change actually re-runs the search.
void main() {
  late Directory tmp;
  late NexServices services;
  late NoteSearchController search;

  Future<NexServices> buildServices() async {
    final dbPath = p.join(tmp.path, 'nex.sqlite');
    final mediaDir = p.join(tmp.path, 'media');
    final backupDir = p.join(tmp.path, 'backups');
    Directory(mediaDir).createSync(recursive: true);
    Directory(backupDir).createSync(recursive: true);
    return NexServices.forTest(
      worker: InProcessDb(dbPath: dbPath, deviceId: 'test'),
      deviceId: 'test',
      preferences: await NexPreferences.load(),
      backupPolicy: BackupPolicy(await SharedPreferences.getInstance()),
      dbPath: dbPath,
      mediaDir: mediaDir,
      backupDir: backupDir,
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('nex_search_filters_');
    services = await buildServices();
    // Two tagged notes to filter against.
    final breakfast = await services.captureText('oatmeal and coffee');
    final meeting = await services.captureText('quarterly planning meeting');
    final tag = await services.createTag('food');
    await services.addTag(noteId: breakfast!.id, name: tag.name);
    await services.addTag(noteId: meeting!.id, name: 'work');
    search = NoteSearchController(services: services);
    await search.loadTags();
    await Future<void>.delayed(const Duration(milliseconds: 220));
  });

  tearDown(() {
    search.dispose();
    services.dispose().ignore();
    tmp.deleteSync(recursive: true);
  });

  // Longer than the 150ms debounce, so a scheduled search has run.
  Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 220));

  test('toggling a tag narrows and re-widens the results', () async {
    await search.run();
    expect(search.results, hasLength(2));

    final food = search.allTags.singleWhere((t) => t.name == 'food');
    search.toggleTag(food.id);
    await pump();
    expect(search.results, hasLength(1));
    expect(search.results.single.content, contains('oatmeal'));
    expect(search.activeFilterCount, 1);

    search.toggleTag(food.id);
    await pump();
    expect(search.results, hasLength(2));
    expect(search.activeFilterCount, 0);
  });

  test('toggling a note type filters by that type alone', () async {
    await search.run();
    search.toggleType(NoteType.text);
    await pump();
    expect(search.results, hasLength(2));

    search.toggleType(NoteType.text);
    await pump();
    expect(search.results, hasLength(2), reason: 'both notes are text');

    search.toggleType(NoteType.photo);
    await pump();
    expect(search.results, isEmpty, reason: 'no photo notes exist');
  });

  test('the date presets bound the window', () async {
    // Everything here was captured "now", so Today matches and no other
    // window can lose it.
    await search.run();
    search.setDatePreset(NoteDatePreset.today);
    await pump();
    expect(search.results, hasLength(2));

    search.setDatePreset(NoteDatePreset.any);
    await pump();
    expect(search.results, hasLength(2));
    expect(search.range, isNull);
  });

  test('clearFilters drops every chip at once and keeps the typed query', () async {
    search.query.text = 'quarterly';
    await search.run();
    final food = search.allTags.singleWhere((t) => t.name == 'food');
    search.toggleTag(food.id);
    search.toggleType(NoteType.photo);
    search.setDatePreset(NoteDatePreset.today);
    await pump();
    expect(search.results, isEmpty, reason: 'a photo named food does not exist');
    expect(search.activeFilterCount, 3);

    search.clearFilters();
    await pump();

    expect(search.activeFilterCount, 0);
    expect(search.results, hasLength(1));
    expect(search.results.single.content, contains('quarterly'));
    expect(search.query.text, 'quarterly', reason: 'typed text is not touched');
  });
}
