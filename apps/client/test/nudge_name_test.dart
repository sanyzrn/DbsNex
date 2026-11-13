import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/daily_nudge_content.dart';
import 'package:nex_client/platform/reminders.dart';
import 'package:nex_core/nex_core.dart';

/// The daily nudge has one name per language: the Settings row, its sound row,
/// the channel the app creates and the channel the native alarm renames when
/// it posts. They were three names in Persian («یادآور روزانه», «یادآوری
/// روزانه», «خلاصهٔ روزانه»), and the app and the alarm renamed the same
/// Android channel back and forth.
void main() {
  for (final persian in [false, true]) {
    test('${persian ? 'fa' : 'en'}: one name for the daily nudge', () {
      final l10n = lookupAppLocalizations(Locale(persian ? 'fa' : 'en'));
      final channel = (persian ? NexChannelText.fa : NexChannelText.en).daily;
      expect(l10n.nudgeTitle, channel);
      expect(l10n.notificationSoundDaily, contains(channel));
      final plan = NexDailyNudgeContent.plan(
        source: const NexNudgeSnapshot(
          notes: [],
          commitments: [],
          hasData: true,
        ),
        now: DateTime(2026, 11, 13, 8),
        minutes: 9 * 60,
        persian: persian,
        title: 'Nex',
        aiEnabled: false,
        summaryEnabled: false,
        sourceMatches: false,
        summary: null,
        summaryAt: null,
        secret: false,
      );
      expect(plan['channelName'], channel);
    });
  }
}
