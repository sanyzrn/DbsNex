import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/brief_refresh.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NexPreferences prefs;
  late NexBriefRefresh refresh;
  late DateTime now;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await NexPreferences.load();
    now = DateTime.utc(2026, 10, 18, 12);
    refresh = NexBriefRefresh(prefs, clock: () => now);
  });

  tearDown(() => prefs.dispose());

  test('expired replies are not cached', () async {
    final reply = Completer<String?>();
    final flight = refresh.refresh(
      fingerprint: 'expired',
      dateKey: '2026-10-18',
      validUntil: now.add(const Duration(minutes: 1)),
      request: () => reply.future,
    );
    now = now.add(const Duration(minutes: 1));
    reply.complete('obsolete');
    final result = await flight;
    expect(result.updated, isFalse);
    expect(prefs.aiDaySummaryText, isNull);
    expect(prefs.aiDaySummaryAt, isNull);
  });

  test('rejected replies preserve the cache', () async {
    await refresh.refresh(
      fingerprint: 'new',
      dateKey: '2026-10-18',
      request: () async => 'new brief',
    );
    final result = await refresh.refresh(
      fingerprint: 'changed',
      dateKey: '2026-10-18',
      force: true,
      request: () async => 'obsolete',
      canPersist: () async => false,
    );
    expect(result.updated, isFalse);
    expect(prefs.aiDaySummaryText, 'new brief');
    expect(prefs.aiDaySummarySource, 'new');
  });
}
