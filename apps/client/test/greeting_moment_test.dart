import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_core/nex_core.dart';

import 'support/nex_harness.dart';

/// The greeting on screen belongs to the moment it is shown in.
///
/// The model is off in these tests on purpose: what is being checked is the
/// line the app puts up *before* any provider is asked — the cached phrase for
/// this day and part of it, and the local phrasing when the cache is from
/// another moment.
void main() {
  final now = DateTime.now();
  final today = NexPreferences.daySummaryDateKey(now);
  final part = nexGreetingPartOf(now).wireName;
  final otherPart = NexGreetingPart.values
      .firstWhere((value) => value.wireName != part)
      .wireName;

  Future<NexTestHarness> harness() async {
    final h = await NexTestHarness.create();
    addTearDown(h.dispose);
    await h.preferences.setLocale('en');
    await h.preferences.setDisplayName('Saeed');
    await h.services.captureText('a note for today');
    return h;
  }

  testWidgets('a phrase cached for this moment opens the screen', (
    tester,
  ) async {
    final h = await harness();
    await h.preferences.setAiHeadline(
      text: 'Ready when you are',
      dateKey: today,
      lang: 'en',
      part: part,
    );
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    expect(find.textContaining('Ready when you are'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("last night's phrase is not the greeting this morning", (
    tester,
  ) async {
    final h = await harness();
    await h.preferences.setAiHeadline(
      text: 'Still up?',
      dateKey: today,
      lang: 'en',
      part: otherPart,
    );
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    expect(find.textContaining('Still up?'), findsNothing);
    // The local greeting is there immediately, without waiting for anything.
    expect(find.textContaining('Saeed'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
