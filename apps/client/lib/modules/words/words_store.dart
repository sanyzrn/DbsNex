/// The module's one shelf in the library, wrapped: cards, settings, and
/// a reload that listens to the store's change stream. Everything a
/// screen does to data goes through here, so the record shapes have one
/// reader and one writer.
library;

import 'dart:async';

import 'package:nex_client/modules/module_api.dart';

import 'words_models.dart';
import 'words_scheduler.dart';
import 'words_dates.dart';
import 'record_bundle.dart';

enum WordsAnswerStatus { saved, changed, missing, failed }

class WordsRepository {
  WordsRepository(this._store);

  final NexModuleStore _store;
  NexModuleStore get store => _store;
  static final _tails = Expando<Future<void>>();
  Future<T> _serial<T>(Future<T> Function() action) {
    final result = Completer<T>();
    final previous = _tails[_store] ?? Future<void>.value();
    final next = previous.then((_) async {
      try {
        result.complete(await action());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    _tails[_store] = next;
    return result.future;
  }

  static const String cardKind = 'card';
  static const String settingsKind = 'settings';

  /// Fires after this module's records change — what a list rebuilds on.
  Stream<void> get changes => _store.changes;

  /// Every card, newest first as the store keeps them.
  Future<List<WordCard>> loadCards() async {
    await RecordBundle.recover(_store);
    final records = await _store.list(cardKind);
    return [
      for (final record in records) WordCard.fromRecord(record.id, record.body),
    ];
  }

  /// Saves a card (creating it when its id is new). Returns false when the
  /// write failed — the caller keeps what was on screen.
  Future<bool> saveCard(
    WordCard card, {
    bool preserveProgress = false,
    bool requireExisting = false,
  }) => _serial(() async {
    try {
      final body = await _store.get(cardKind, card.id);
      if (requireExisting && body == null) return false;
      final latest = body == null ? card : WordCard.fromRecord(card.id, body);
      final next = preserveProgress
          ? latest.copyWith(
              headword: card.headword,
              language: card.language,
              meaning: card.meaning,
              example: card.example,
              note: card.note,
              tag: card.tag,
            )
          : card;
      await _store.put(
        cardKind,
        card.id,
        preserveProgress && body != null
            ? {
                ...body,
                'headword': next.headword,
                'language': next.language,
                'meaning': next.meaning,
                'example': next.example,
                'note': next.note,
                'tag': next.tag,
                'schema': next.schema,
                'introducedOn': next.introducedOn,
              }
            : {...?body, ...next.toRecord()},
      );
      return true;
    } catch (_) {
      return false;
    }
  });

  Future<WordCard?> setPaused(String id, bool paused) => _serial(() async {
    try {
      final body = await _store.get(cardKind, id);
      if (body == null) return null;
      final next = WordCard.fromRecord(id, body).copyWith(paused: paused);
      await _store.put(cardKind, id, {...body, 'paused': paused});
      return next;
    } catch (_) {
      return null;
    }
  });

  /// Explicit repair; a stale request cannot change a now-valid schedule.
  Future<WordCard?> repairDue(String id) => _serial(() async {
    try {
      final body = await _store.get(cardKind, id);
      if (body == null) return null;
      final latest = WordCard.fromRecord(id, body);
      if (latest.isNew || wordsParseDay(latest.due) != null) return latest;
      final next = {...body, 'due': wordsIsoDay(DateTime.now())};
      await _store.put(cardKind, id, next);
      return WordCard.fromRecord(id, next);
    } catch (_) {
      return null;
    }
  });

  Future<({WordsAnswerStatus status, WordCard? card})> answer(
    WordCard expected,
    WordsGrade grade,
    String eventId,
  ) => _serial(() async {
    try {
      final body = await _store.get(cardKind, expected.id);
      if (body == null) return (status: WordsAnswerStatus.missing, card: null);
      final latest = WordCard.fromRecord(expected.id, body);
      if (body['lastReviewId'] == eventId) {
        return (status: WordsAnswerStatus.saved, card: latest);
      }
      if (latest.paused) return (status: WordsAnswerStatus.missing, card: null);
      if (latest.reps != expected.reps ||
          latest.lastReviewIso != expected.lastReviewIso ||
          latest.due != expected.due ||
          latest.step != expected.step) {
        return (status: WordsAnswerStatus.changed, card: null);
      }
      if (latest.headword != expected.headword ||
          latest.meaning != expected.meaning ||
          latest.language != expected.language) {
        return (status: WordsAnswerStatus.changed, card: latest);
      }
      if (latest.isNew) {
        final settings = await loadSettings();
        if (settings.newPerDay > 0) {
          final cards = await loadCards();
          final today = isoDay(DateTime.now());
          final introduced = cards
              .where((c) => !c.isNew && c.introducedOn == today)
              .length;
          if (introduced >= settings.newPerDay) {
            return (status: WordsAnswerStatus.changed, card: null);
          }
        }
      }
      final next = answerCard(latest, grade, DateTime.now());
      await _store.put(cardKind, next.id, {
        ...body,
        ...next.toRecord(),
        'lastReviewId': eventId,
      });
      return (status: WordsAnswerStatus.saved, card: next);
    } catch (_) {
      // A provider can report a failure after committing. Confirm this event
      // before a retry could apply the same grade twice.
      try {
        final body = await _store.get(cardKind, expected.id);
        if (body?['lastReviewId'] == eventId) {
          return (
            status: WordsAnswerStatus.saved,
            card: WordCard.fromRecord(expected.id, body!),
          );
        }
      } catch (_) {
        /* Retry keeps the same event ID. */
      }
      return (status: WordsAnswerStatus.failed, card: null);
    }
  });

  Future<RecordBundle?> deleteCard(WordCard card) => _serial(() async {
    try {
      final bundle = await RecordBundle.capture(
        _store,
        cardKind,
        card.id,
        'unused',
        'cardId',
      );
      if (!bundle.records.any((r) => r.kind == cardKind && r.id == card.id)) {
        return null;
      }
      await bundle.delete();
      return bundle;
    } catch (_) {
      return null;
    }
  });

  Future<bool> restoreBundle(RecordBundle bundle) => _serial(() async {
    try {
      await bundle.restore();
      return true;
    } catch (_) {
      return false;
    }
  });

  /// A brand-new card, today-stamped, with the ladder's first day as its
  /// due date (new cards are picked up by the session, not by «due»).
  Future<WordCard> newCard({
    required String headword,
    required String language,
    String meaning = '',
    String example = '',
    String note = '',
    String tag = '',
  }) async {
    final now = DateTime.now();
    return WordCard(
      id: _store.newId(),
      headword: headword,
      language: language,
      meaning: meaning,
      example: example,
      note: note,
      tag: tag,
      createdAtIso: now.toIso8601String(),
      step: 0,
      due: isoDay(now),
    );
  }

  Future<WordsSettings> loadSettings() async {
    final body = await _store.get(settingsKind, WordsSettings.recordId);
    if (body == null) {
      return const WordsSettings(newPerDay: WordsSettings.defaultPerDay);
    }
    return WordsSettings.fromRecord(body);
  }

  Future<bool> saveSettings(WordsSettings settings) => _serial(() async {
    try {
      await _store.put(settingsKind, WordsSettings.recordId, {
        ...?await _store.get(settingsKind, WordsSettings.recordId),
        ...settings.toRecord(),
      });
      return true;
    } catch (_) {
      return false;
    }
  });

  Future<bool> updateSettings({int? newPerDay, int? sessionLimit}) =>
      _serial(() async {
        try {
          final body = await _store.get(settingsKind, WordsSettings.recordId);
          final current = WordsSettings.fromRecord(body ?? const {});
          final next = WordsSettings(
            newPerDay: newPerDay ?? current.newPerDay,
            sessionLimit: sessionLimit ?? current.sessionLimit,
          );
          await _store.put(settingsKind, WordsSettings.recordId, {
            ...?body,
            ...next.toRecord(),
          });
          return true;
        } catch (_) {
          return false;
        }
      });

  /// The words of the day's session, and how many are waiting.
  Future<
    ({
      List<WordCard> due,
      List<WordCard> fresh,
      int newPerDay,
      int sessionLimit,
    })
  >
  loadSession() async {
    final settings = await loadSettings();
    final cards = await loadCards();
    final session = buildSession(
      cards: cards,
      todayIso: isoDay(DateTime.now()),
      newPerDay: settings.newPerDay,
      sessionLimit: settings.sessionLimit,
    );
    return (
      due: session.due,
      fresh: session.fresh,
      newPerDay: settings.newPerDay,
      sessionLimit: settings.sessionLimit,
    );
  }
}
