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

  /// The notes the brief is written from: the library's own candidate set,
  /// read from the database on every pass — everything that can be waiting
  /// (a reminder, an urgent mark, a checklist) plus the newest ordinary
  /// prose. The timeline window is no longer the source of the set: it is a
  /// recency slice whose depth depends on how far somebody has scrolled,
  /// and a brief whose reach changes with a scroll is not reading the
  /// library. The window is used only as a freshness overlay — where it
  /// carries a candidate, its copy is the one the stream last delivered and
  /// the cards are showing, so it wins over the read's copy of the same row.
  ///
  /// An empty candidate set means the read failed (or a library with nothing
  /// eligible in it); the window then stands in, which is what the brief
  /// always fell back to, so a failed read is never a blank card.
  List<Note> _briefLibrary() {
    final candidates = _briefCandidates;
    final window = _model.all ?? _model.notes;
    if (candidates.isEmpty) return window;
    final delivered = {for (final note in window) note.id: note};
    return [for (final note in candidates) delivered[note.id] ?? note];
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
