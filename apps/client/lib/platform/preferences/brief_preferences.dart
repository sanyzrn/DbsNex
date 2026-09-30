part of '../nex_preferences.dart';

/// The daily brief, the day summary and the timeline headline, with their
/// caches.
mixin _BriefPreferences on _PreferencesStore {
  NexBriefStyle get briefStyle =>
      NexBriefStyle.fromWire(_prefs.getString('brief.style'));

  Future<void> setBriefStyle(NexBriefStyle value) async {
    await _prefs.setString('brief.style', value.wireName);
    notifyListeners();
  }

  /// How the brief sounds, under the styles that have a model write anything.
  ///
  /// Its own key rather than the assistant's: the two are read in different
  /// places for different reasons — a chat you opened, and a card that writes
  /// itself while you are looking at something else — and somebody who wants
  /// their assistant playful may well want the thing telling them what is
  /// overdue to be flat.
  AiResponseStyle get briefTone =>
      AiResponseStyle.fromWire(_prefs.getString('brief.tone'));

  Future<void> setBriefTone(AiResponseStyle value) async {
    await _prefs.setString('brief.tone', value.wireName);
    notifyListeners();
  }

  /// How many lines the card may fill — see [NexBriefLength].
  NexBriefLength get briefLength =>
      NexBriefLength.fromWire(_prefs.getString('brief.length'));

  Future<void> setBriefLength(NexBriefLength value) async {
    await _prefs.setString('brief.length', value.wireName);
    notifyListeners();
  }

  String get briefInstruction => _prefs.getString('brief.instruction') ?? '';

  Future<void> setBriefInstruction(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await _prefs.remove('brief.instruction');
    } else {
      await _prefs.setString(
        'brief.instruction',
        trimmed.length <= NexPreferences.briefInstructionMaxLength
            ? trimmed
            : trimmed.substring(0, NexPreferences.briefInstructionMaxLength),
      );
    }
    notifyListeners();
  }

  /* --------------------------------------------------------- AI day summary */

  /// The timeline's daily AI recap, cached against the date it was written
  /// for — see `_TimelineScreenState._loadAiSummary`. Generating it is a real
  /// network call, so a cold launch that already has today's text shows it
  /// immediately instead of re-asking the provider on every open.
  ///
  /// No [notifyListeners] here: this cache is read by the one screen that
  /// writes it, on its own schedule, not something the rest of the app
  /// reacts to.
  String? get aiDaySummaryText => _prefs.getString('ai.daySummary.text');
  String? get aiDaySummaryDate => _prefs.getString('ai.daySummary.date');

  /// When the recap on file was written, and a fingerprint of the notes it
  /// was written from.
  ///
  /// Together they are what turns "once a calendar day" into a cadence: the
  /// timeline re-asks only when both the notes have moved on *and* enough
  /// time has passed since the last answer. A day was too coarse — a recap
  /// written at nine in the morning described nine in the morning until
  /// midnight — and re-asking on every capture would spend a provider call on
  /// every line anybody types.
  DateTime? get aiDaySummaryAt {
    final value = _prefs.getInt('ai.daySummary.at');
    return value == null ? null : DateTime.fromMillisecondsSinceEpoch(value);
  }

  String? get aiDaySummarySource => _prefs.getString('ai.daySummary.source');

  /// [at] and [source] default to "written now, from notes this does not
  /// claim to recognise": a caller that only has a string to file — a test,
  /// or any future path that is not the timeline's own — gets a recap that is
  /// treated as current and left alone until the interval is up, rather than
  /// one the next launch immediately re-asks for.
  Future<void> setAiDaySummary({
    required String text,
    required String dateKey,
    DateTime? at,
    String source = '',
  }) async {
    await _prefs.setString('ai.daySummary.text', text);
    await _prefs.setString('ai.daySummary.date', dateKey);
    await _prefs.setInt(
      'ai.daySummary.at',
      (at ?? DateTime.now()).millisecondsSinceEpoch,
    );
    await _prefs.setString('ai.daySummary.source', source);
  }

  /// The most recent recap there is, whatever day it was written for.
  ///
  /// This used to be `todaysRecap`, gated on the summary having been written
  /// for today — deliberately, on the reasoning that yesterday's digest
  /// delivered as this morning's would describe a day that is over.
  ///
  /// That reasoning had one caller and was wrong for it. The notification's
  /// text is fixed when the alarm is scheduled, because nothing can generate a
  /// sentence at seven in the morning while the app is not running. The last
  /// time the app was open was almost certainly yesterday, so by the time it
  /// fires the date has rolled over and the gate has closed — every morning,
  /// without exception. A library of hundreds of notes was greeted with
  /// "nothing written down yet today", which is not the notification admitting
  /// it has nothing: it reads as the app having lost everything.
  ///
  /// A morning greeting carrying what you wrote yesterday is the useful thing
  /// anyway. What you have written since midnight, at seven in the morning, is
  /// a description of an empty page.
  String? get lastRecap {
    final text = aiDaySummaryText;
    return (text == null || text.isEmpty) ? null : text;
  }

  /// The timeline's one-line headline, cached the same way and for the same
  /// reason as the recap above. Tapping the line asks for a new one, which is
  /// what makes this a cache rather than a daily lock.
  String? get aiHeadlineText => _prefs.getString('ai.headline.text');
  String? get aiHeadlineDate => _prefs.getString('ai.headline.date');

  /// Which language the cached line was written in.
  ///
  /// The headline is joined onto the greeting as one sentence, and the
  /// greeting follows the script of the user's own name — so a name changed
  /// from Persian to Latin (or back) has to throw the cached line away, not
  /// glue yesterday's Persian half onto today's English greeting.
  String? get aiHeadlineLang => _prefs.getString('ai.headline.lang');

  Future<void> setAiHeadline({
    required String text,
    required String dateKey,
    String? lang,
  }) async {
    await _prefs.setString('ai.headline.text', text);
    await _prefs.setString('ai.headline.date', dateKey);
    if (lang == null) {
      await _prefs.remove('ai.headline.lang');
    } else {
      await _prefs.setString('ai.headline.lang', lang);
    }
  }
}
