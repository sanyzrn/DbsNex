part of '../timeline_screen.dart';

/// Source selection, settings signature, and fingerprinting for Smart Summary.
extension _TimelineBriefSources on TimelineScreenState {
  String _briefSettingsSignature() {
    final prefs = widget.preferences;
    final config = prefs.aiProvider;
    return nexBriefSignature(
      source:
          '${config.provider.wireName}|${config.resolvedBaseUrl}|'
          '${config.resolvedModel}|${prefs.aiEnabled}|'
          '${prefs.aiSummaryUnlimited}|${prefs.locale}|${prefs.briefHabitsAllowed}'
          // The interface locale, which the report's own lines are written
          // in. `prefs.locale` alone cannot say it: null means "follow the
          // system", and a system language change then moved nothing the
          // signature named while the facts on the card changed language.
          // Seeded with the first locale the screen resolves — see
          // [didChangeDependencies], which keeps the learning of it from
          // reading as a change.
          '|${_briefLocale ?? ''}',
      style: prefs.briefStyle,
      tone: prefs.briefTone,
      length: prefs.briefLength,
      language: prefs.aiOutputLanguage,
      instruction: prefs.briefInstruction,
    );
  }

  /// The notes the brief is written from: the timeline window — everything
  /// recent — plus the waiting notes beyond it, merged by id with the
  /// window's own copy of a note winning (it is the one the stream last
  /// delivered, so it is the one the cards are showing).
  ///
  /// The window is a recency slice, and the brief's job is only partly about
  /// recency. A reminder set last month for tomorrow morning is the single
  /// most worth mentioning thing in a library, and below a few hundred newer
  /// notes the window stopped carrying it; the waiting notes put it back in
  /// reach of the choosing in `nexRecapSource`, which is where the choosing
  /// was always meant to happen.
  List<Note> _briefLibrary() {
    final window = _model.all ?? _model.notes;
    final waiting = _briefWaitingNotes;
    if (waiting.isEmpty) return window;
    final seen = {for (final note in window) note.id};
    return [
      ...window,
      for (final note in waiting)
        if (!seen.contains(note.id)) note,
    ];
  }

  /// Everything the fingerprint is hashed from, as one string. Split out of
  /// [_briefFingerprint] because the arming pass needs the same source to
  /// answer "is there anything to describe at all" — and building it twice
  /// meant walking the library twice on a path that runs after every pass.
  String _briefFingerprintSource() =>
      '${_aiRecapSource(forFingerprint: true, notes: _briefLibrary())}\n'
      '${widget.preferences.briefHabitsAllowed ? _habitBriefSource : ''}';

  /// The signature the fingerprint hashes: settings, provider, and the
  /// facts the report would state, laid over [stableSource]. Named so
  /// [_briefFingerprint] and the arming pass cannot drift apart — they used
  /// to be one method, and the arming pass rebuilt the whole thing only to
  /// throw the facts half of it away.
  String _briefSignatureBody(String stableSource) {
    final prefs = widget.preferences;
    final config = prefs.aiProvider;
    final budget = nexBriefLines(
      '\n'.allMatches(stableSource).length + 1,
      ceiling: prefs.briefLength.lines,
    );
    final facts = prefs.briefStyle.statesFacts
        ? nexBriefFactsSignature(
            nexBriefFacts(_briefLibrary(), commitments: _model.commitments),
            maxLines: (budget - 1).clamp(1, budget),
          )
        : '';
    return nexBriefSignature(
      source:
          'brief-2.5.2|$stableSource\n$facts\n'
          '${config.provider.wireName}|${config.resolvedBaseUrl}|${config.resolvedModel}|'
          '${prefs.aiSummaryUnlimited}|${prefs.briefStyle.statesFacts ? Localizations.localeOf(context) : ''}',
      style: prefs.briefStyle,
      tone: prefs.briefTone,
      length: prefs.briefLength,
      language: prefs.aiOutputLanguage,
      instruction: prefs.briefInstruction,
    );
  }

  String _briefFingerprint() => TimelineScreenState.recapFingerprint(
    _briefSignatureBody(_briefFingerprintSource()),
  );
}
