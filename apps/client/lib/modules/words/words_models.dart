/// One word or phrase a person is keeping, with its own review history —
/// and nothing else. No dictionary definitions are fetched or invented;
/// every field is something the person typed.
///
/// Kind: `card`. Schema 2 (legacy schema 1 is readable). The review log lives inside the record, capped
/// at the newest [WordCard.maxLog] entries, so a delete-and-Undo restores
/// the card *with* its history in one move, and no orphan logs can exist.
library;

import 'words_dates.dart';

/// The four answers a person can give a card. The words live in the
/// module's strings; the scheduling that follows each one is in
/// `words_scheduler.dart`.
enum WordsGrade { again, hard, good, easy }

class WordCard {
  const WordCard({
    required this.id,
    required this.headword,
    required this.language,
    this.meaning = '',
    this.example = '',
    this.note = '',
    this.tag = '',
    required this.createdAtIso,
    this.step = 0,
    this.due = '',
    this.lapses = 0,
    this.reps = 0,
    this.lastReviewIso = '',
    this.paused = false,
    this.log = const [],
    this.schema = 2,
    this.introducedOn = '',
  });

  /// The record's id — a UUIDv7 from the store, kept across edits.
  final String id;

  /// The word or phrase itself, in whichever script it is written.
  final String headword;

  /// A language label the person chose — «English», «فارسی», anything.
  final String language;

  /// The meaning or translation, free-form: one line or several senses on
  /// their own lines. Not a dictionary definition.
  final String meaning;
  final String example;
  final String note;

  /// A tag or source title: «book: The Little Prince», «work».
  final String tag;

  final String createdAtIso;

  /// Where the card sits on the ladder (0..5); see `words_scheduler.dart`.
  final int step;

  /// The next review day, as a date-only ISO `YYYY-MM-DD`. Empty for a
  /// card that has never been reviewed (a new card).
  final String due;

  final int lapses;
  final int reps;
  final String lastReviewIso;
  final bool paused;

  /// The review history, oldest first, newest last.
  final List<({String at, WordsGrade grade})> log;

  final int schema;
  final String introducedOn;

  /// How many log entries are kept; older ones are folded away when the
  /// card is saved. The counts that matter (reps, lapses) live in their
  /// own fields and never depend on the cap.
  static const int maxLog = 200;

  /// A card nobody has answered yet.
  bool get isNew =>
      reps == 0 && log.isEmpty && lastReviewIso.isEmpty && introducedOn.isEmpty;

  /// Whether the card is due on or before [todayIso] (date-only compare:
  /// ISO `YYYY-MM-DD` sorts as a string).
  bool isDueOn(String todayIso) =>
      !paused &&
      !isNew &&
      wordsParseDay(due) != null &&
      wordsParseDay(todayIso) != null &&
      due.compareTo(todayIso) <= 0;

  /// The same headword, same language: the duplication the editor warns
  /// about. Case and whitespace runs are folded so «Serendipity» and
  /// «serendipity » are one word, not two.
  bool sameWordAs(WordCard other) =>
      id != other.id &&
      foldWhitespace(language).toLowerCase() ==
          foldWhitespace(other.language).toLowerCase() &&
      foldWhitespace(headword).toLowerCase() ==
          foldWhitespace(other.headword).toLowerCase();

  WordCard copyWith({
    String? headword,
    String? language,
    String? meaning,
    String? example,
    String? note,
    String? tag,
    int? step,
    String? due,
    int? lapses,
    int? reps,
    String? lastReviewIso,
    bool? paused,
    String? introducedOn,
    List<({String at, WordsGrade grade})>? log,
  }) => WordCard(
    id: id,
    headword: headword ?? this.headword,
    language: language ?? this.language,
    meaning: meaning ?? this.meaning,
    example: example ?? this.example,
    note: note ?? this.note,
    tag: tag ?? this.tag,
    createdAtIso: createdAtIso,
    step: step ?? this.step,
    due: due ?? this.due,
    lapses: lapses ?? this.lapses,
    reps: reps ?? this.reps,
    lastReviewIso: lastReviewIso ?? this.lastReviewIso,
    paused: paused ?? this.paused,
    introducedOn: introducedOn ?? this.introducedOn,
    schema: schema < 2 ? 2 : schema,
    log: log ?? this.log,
  );

  factory WordCard.fromRecord(String id, Map<String, Object?> body) {
    final log = <({String at, WordsGrade grade})>[];
    final rawLog = body['log'];
    if (rawLog is List<Object?>) {
      for (final entry in rawLog) {
        if (entry is Map<String, Object?>) {
          final grade = switch ('${entry['g'] ?? ''}') {
            'again' => WordsGrade.again,
            'hard' => WordsGrade.hard,
            'easy' => WordsGrade.easy,
            _ => WordsGrade.good,
          };
          final at = '${entry['at'] ?? ''}';
          if (wordsValidStamp(at) != null) log.add((at: at, grade: grade));
        }
      }
    }
    final step = _clamp(_int(body['step']) ?? 0, 0, 5);
    // A record written by anything else (an older build, a future schema)
    // may hold a longer log than this version keeps; read the newest
    // [maxLog] entries and let the rest go, the same way answering does.
    final readLog = log.length > maxLog
        ? log.sublist(log.length - maxLog)
        : log;
    return WordCard(
      id: id,
      headword: foldWhitespace('${body['headword'] ?? ''}'),
      language: foldWhitespace('${body['language'] ?? ''}'),
      meaning: '${body['meaning'] ?? ''}'.trim(),
      example: '${body['example'] ?? ''}'.trim(),
      note: '${body['note'] ?? ''}'.trim(),
      tag: foldWhitespace('${body['tag'] ?? ''}'),
      createdAtIso: wordsValidStamp('${body['createdAt'] ?? ''}') ?? '',
      step: step,
      due: wordsParseDay('${body['due'] ?? ''}') == null
          ? ''
          : '${body['due']}',
      lapses: _max0(_int(body['lapses']) ?? 0),
      reps: _max0(_int(body['reps']) ?? 0),
      lastReviewIso: wordsValidStamp('${body['lastReview'] ?? ''}') ?? '',
      introducedOn: wordsParseDay('${body['introducedOn'] ?? ''}') != null
          ? '${body['introducedOn']}'
          : _oldestDay(log),
      paused: body['paused'] is bool ? body['paused'] as bool : false,
      log: readLog,
      schema: _int(body['schema']) ?? 1,
    );
  }

  Map<String, Object?> toRecord() => {
    'schema': schema,
    'headword': headword,
    'language': language,
    'meaning': meaning,
    'example': example,
    'note': note,
    'tag': tag,
    'createdAt': createdAtIso,
    'step': step,
    'due': due,
    'lapses': lapses,
    'reps': reps,
    'lastReview': lastReviewIso,
    'paused': paused,
    'introducedOn': introducedOn,
    'log': [
      for (final entry in log) {'at': entry.at, 'g': entry.grade.name},
    ],
  };
}

/// The module's settings, one record of kind `settings` under a fixed id.
class WordsSettings {
  const WordsSettings({required this.newPerDay, this.sessionLimit = 20});
  final int sessionLimit;

  /// How many never-reviewed cards a day's session may introduce.
  /// 0 means no cap. The default is 10.
  final int newPerDay;

  static const defaultPerDay = 10;
  static const String recordId = 'settings';

  factory WordsSettings.fromRecord(Map<String, Object?> body) {
    int read(String key, int fallback) {
      final value = _int(body[key]);
      return value != null && value >= 0 && value <= 200 ? value : fallback;
    }

    return WordsSettings(
      newPerDay: read('newPerDay', defaultPerDay),
      sessionLimit: read('sessionLimit', 20),
    );
  }
  Map<String, Object?> toRecord() => {
    'schema': 2,
    'newPerDay': newPerDay,
    'sessionLimit': sessionLimit,
  };
}

/// Folds case-less duplication: trims, collapses whitespace runs.
String foldWhitespace(String text) =>
    text.trim().replaceAll(RegExp(r'\s+'), ' ');

int? _int(Object? value) {
  if (value is int && value.abs() <= 9007199254740991) return value;
  if (value is num &&
      value.isFinite &&
      value.abs() <= 9007199254740991 &&
      value == value.truncateToDouble()) {
    return value.toInt();
  }
  return null;
}

int _clamp(int value, int min, int max) => value < min
    ? min
    : value > max
    ? max
    : value;

int _max0(int value) => value < 0 ? 0 : value;

String _oldestDay(List<({String at, WordsGrade grade})> log) {
  String? oldest;
  for (final entry in log) {
    final day = wordsStampDay(entry.at);
    if (day != null && (oldest == null || day.compareTo(oldest) < 0)) {
      oldest = day;
    }
  }
  return oldest ?? '';
}
