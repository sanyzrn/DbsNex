part of '../nex_preferences.dart';

/// The daily brief, the day summary and the timeline headline, with their
/// caches.
mixin _BriefPreferences on _PreferencesStore {
  bool get briefUseHabits => _prefs.getBool('brief.useHabits') ?? false;
  bool get briefHabitsAllowed =>
      briefUseHabits && (_prefs.getBool('module.habits.on') ?? false);
  Future<void> setBriefUseHabits(bool on) => _setBool('brief.useHabits', on);

  bool get aiDaySummaryIncludesHabits =>
      _prefs.getBool('ai.daySummary.habits') ?? false;
  // Revision 1 includes ordinary notes in factual briefs and balances habits.
  // Older generated summaries may stay visible until their replacement arrives.
  bool get aiDaySummaryCurrent => _prefs.getInt('ai.daySummary.revision') == 1;
  NexBriefStyle get briefStyle =>
      NexBriefStyle.fromWire(_prefs.getString('brief.style'));

  Future<void> setBriefStyle(NexBriefStyle value) async {
    await _prefs.setString('brief.style', value.wireName);
    _notifyNow();
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
    _notifyNow();
  }

  /// How many lines the card may fill — see [NexBriefLength].
  NexBriefLength get briefLength =>
      NexBriefLength.fromWire(_prefs.getString('brief.length'));

  Future<void> setBriefLength(NexBriefLength value) async {
    await _prefs.setString('brief.length', value.wireName);
    _notifyNow();
  }

  /// Whether the day summary on the timeline is folded.
  ///
  /// Kept rather than held by the screen: it was a field that started open,
  /// so a summary folded by hand or by a scroll opened again on its own each
  /// time the app came back and rebuilt the timeline — mid-refresh, looking
  /// as if it had opened to update. Folded stays folded until a tap opens
  /// it; a refresh happens inside the folded card.
  bool get daySummaryFolded => _prefs.getBool('brief.summary_folded') ?? false;

  Future<void> setDaySummaryFolded(bool value) =>
      _prefs.setBool('brief.summary_folded', value);

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
    _notifyTypingSettled();
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
  String? get aiDaySummaryText =>
      aiDaySummaryIncludesHabits && !briefHabitsAllowed
      ? _prefs.getString('ai.daySummary.notesOnly')
      : _prefs.getString('ai.daySummary.text');
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

  /// The instant the recap on file stops being true, as the app computed it
  /// when the words were written.
  ///
  /// A brief is written from facts that change on their own — an item's
  /// moment passes, a recurring item's early window opens, the day turns —
  /// and not one of those writes a row. Storing the instant it was checked
  /// against is what lets a later read tell a brief that still holds from one
  /// that merely looks current, without re-reading the library.
  ///
  /// Absent means "not known", which is not "expired": a cache written
  /// before 2.9.0 keeps the behaviour it had.
  DateTime? get aiDaySummaryValidUntil {
    final value = _prefs.getInt('ai.daySummary.validUntil');
    return value == null ? null : DateTime.fromMillisecondsSinceEpoch(value);
  }

  /// Whether the recap on file is still within the moment it was written for.
  bool get aiDaySummaryFresh {
    final until = aiDaySummaryValidUntil;
    return until == null || DateTime.now().isBefore(until);
  }

  /// The model's recap when it is still true — today's, and written before
  /// the moment its facts moved — and null otherwise.
  ///
  /// The one question every surface that republishes the recap asks: the
  /// card, the home-screen widget and the daily nudge all read
  /// [aiDaySummaryText] directly before this existed, which is how a
  /// yesterday's sentence (or one whose "nothing overdue" had stopped being
  /// true an hour ago) could be published as the state of the library now.
  String? get currentAiBrief {
    final text = aiDaySummaryText;
    if (text == null || text.trim().isEmpty) return null;
    if (aiDaySummaryDate != NexPreferences.daySummaryDateKey(DateTime.now())) {
      return null;
    }
    return aiDaySummaryFresh ? text : null;
  }

  DateTime? get aiDaySummaryFailedAt {
    final value = _prefs.getInt('ai.daySummary.failedAt');
    return value == null ? null : DateTime.fromMillisecondsSinceEpoch(value);
  }

  Future<void> setAiDaySummaryFailure(DateTime at) async {
    await _prefs.setInt('ai.daySummary.failedAt', at.millisecondsSinceEpoch);
  }

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
    bool includesHabits = false,
    String? notesOnlyFallback,
    DateTime? validUntil,
  }) async {
    if (includesHabits && !briefHabitsAllowed) return;
    if (!includesHabits) {
      await _prefs.setString('ai.daySummary.notesOnly', text);
    } else if (_prefs.getString('ai.daySummary.notesOnly') == null) {
      await _prefs.setString(
        'ai.daySummary.notesOnly',
        !aiDaySummaryIncludesHabits
            ? (_prefs.getString('ai.daySummary.text') ??
                  notesOnlyFallback ??
                  '')
            : (notesOnlyFallback ?? ''),
      );
    }
    await _prefs.setBool('ai.daySummary.habits', includesHabits);
    await _prefs.setString('ai.daySummary.text', text);
    await _prefs.setString('ai.daySummary.date', dateKey);
    await _prefs.setInt(
      'ai.daySummary.at',
      (at ?? DateTime.now()).millisecondsSinceEpoch,
    );
    await _prefs.setString('ai.daySummary.source', source);
    if (validUntil == null) {
      await _prefs.remove('ai.daySummary.validUntil');
    } else {
      await _prefs.setInt(
        'ai.daySummary.validUntil',
        validUntil.millisecondsSinceEpoch,
      );
    }
    await _prefs.setInt('ai.daySummary.revision', 1);
    await _prefs.remove('ai.daySummary.failedAt');
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

  /// The part of the day the cached line was written for: `morning`,
  /// `afternoon`, `evening` or `night`.
  ///
  /// Absent on a line cached before 2.9.0, which is exactly why it is checked
  /// rather than assumed: a cache with no part is not a cache for the current
  /// moment, so the local greeting is used until a new line arrives.
  String? get aiHeadlinePart => _prefs.getString('ai.headline.part');

  DateTime? get aiHeadlineFailedAt {
    final value = _prefs.getInt('ai.headline.failedAt');
    return value == null ? null : DateTime.fromMillisecondsSinceEpoch(value);
  }

  Future<void> setAiHeadlineFailure(DateTime at) async {
    await _prefs.setInt('ai.headline.failedAt', at.millisecondsSinceEpoch);
  }

  /// Which language the cached line was written in.
  ///
  /// This is the interface language, independent of the user's name. A cache
  /// from a different language must not replace the local greeting on failure.
  String? get aiHeadlineLang => _prefs.getString('ai.headline.lang');

  Future<void> setAiHeadline({
    required String text,
    required String dateKey,
    String? lang,
    String? part,
  }) async {
    await _prefs.setString('ai.headline.text', text);
    await _prefs.setString('ai.headline.date', dateKey);
    await _prefs.remove('ai.headline.failedAt');
    if (lang == null) {
      await _prefs.remove('ai.headline.lang');
    } else {
      await _prefs.setString('ai.headline.lang', lang);
    }
    if (part == null) {
      await _prefs.remove('ai.headline.part');
    } else {
      await _prefs.setString('ai.headline.part', part);
    }
  }
}
