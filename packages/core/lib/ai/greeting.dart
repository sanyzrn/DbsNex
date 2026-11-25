/// The greeting at the top of the timeline, as a rule rather than a widget.
///
/// The complaint behind 2.9.0's step 3: the evening's line was still there in
/// the morning. The model had been asked for a phrase at the right hour, but
/// nothing tied the *answer* to the hour it was written for — the cache held a
/// phrase and a date, so a day that rolled over while the app was open kept
/// last night's words, and a cache hit in the morning looked exactly like a
/// cache hit at midnight.
///
/// So a greeting is valid for a **moment**: one calendar day, one part of the
/// day, one language. The moment is computed here, the phrase is checked
/// against it here, and the cache stores the moment beside the words. A phrase
/// from another moment is not reused — the local phrasing stands in until a
/// new one arrives.
library;

/// Morning, afternoon, evening, night — the four the app already greets in.
///
/// The boundaries are the ones the local phrasings were written against and
/// must stay in step with them: 05:00, 12:00, 17:00 and 23:00.
enum NexGreetingPart {
  morning,
  afternoon,
  evening,
  night;

  /// The form stored in preferences and sent to a provider.
  String get wireName => switch (this) {
    NexGreetingPart.morning => 'morning',
    NexGreetingPart.afternoon => 'afternoon',
    NexGreetingPart.evening => 'evening',
    NexGreetingPart.night => 'night',
  };

  static NexGreetingPart? fromWire(String? value) {
    for (final part in NexGreetingPart.values) {
      if (part.wireName == value) return part;
    }
    return null;
  }
}

/// Which part of the day [at] falls in, by the device's own clock.
NexGreetingPart nexGreetingPartOf(DateTime at) {
  final hour = at.toLocal().hour;
  if (hour >= 5 && hour < 12) return NexGreetingPart.morning;
  if (hour >= 12 && hour < 17) return NexGreetingPart.afternoon;
  if (hour >= 17 && hour < 23) return NexGreetingPart.evening;
  return NexGreetingPart.night;
}

/// The four moments after [at] at which the greeting must change, in order.
///
/// Returned as instants rather than durations so a caller can arm one timer
/// for the next one and let the following call continue the chain; daylight
/// saving and a changed time zone are picked up because the list is rebuilt
/// from the local clock each time.
List<DateTime> nexGreetingBoundaries(DateTime at) {
  final local = at.toLocal();
  return [
    for (var day = 0; day <= 1; day++)
      for (final hour in const [5, 12, 17, 23])
        DateTime(local.year, local.month, local.day + day, hour),
    DateTime(local.year, local.month, local.day + 1),
  ]..sort();
}

/// One greeting's validity: the day, the part of it, and the language.
class NexGreetingMoment {
  const NexGreetingMoment({
    required this.dateKey,
    required this.part,
    required this.language,
  });

  /// The local calendar day, in the app's existing `yyyy-MM-dd` form.
  final String dateKey;
  final NexGreetingPart part;

  /// `fa`, `en`, … — the interface language, not the user's name.
  final String language;

  /// The cache key this moment is stored under.
  String get key => '$dateKey|${part.wireName}|$language';

  @override
  bool operator ==(Object other) =>
      other is NexGreetingMoment &&
      other.dateKey == dateKey &&
      other.part == part &&
      other.language == language;

  @override
  int get hashCode => Object.hash(dateKey, part, language);

  @override
  String toString() => key;
}

/// Whether a phrase can be shown at [moment].
///
/// Three things are checked, and each one is a failure that happened:
///
/// * **The shape.** One line, short enough to sit above the date without
///   wrapping the card, no newline — a model that answered with a paragraph
///   was cut mid-sentence and read as a bug.
/// * **The language.** The same rule the provider applies when it returns a
///   phrase, repeated here because a cache can be written by another path (an
///   older version, a restored backup) and the interface may have changed
///   since.
/// * **The time of day.** "Good morning" at 23:00 is the exact bug this
///   release fixes; a phrase that names a part of the day is only valid in
///   that part. A phrase that names none is welcome at any hour.
bool nexGreetingFits(String? text, {required NexGreetingMoment moment}) {
  if (text == null) return false;
  final phrase = text.trim();
  if (phrase.isEmpty) return false;
  if (phrase.contains('\n') || phrase.contains('\r')) return false;
  if (phrase.runes.length > 90) return false;
  if (phrase.split(RegExp(r'\s+')).length > 14) return false;
  if (!nexGreetingLanguageFits(phrase, moment.language)) return false;
  // Every part the phrase names has to be the current one: "morning to
  // night" is a lovely line and the wrong thing to greet somebody with at
  // noon.
  final named = _namedParts(phrase);
  return named.every((part) => part == moment.part);
}

/// The provider's greeting test, for a string that never left the device.
///
/// Persian is the interface's Persian: more Persian letters than Latin ones
/// (a Latin nickname inside the phrase is fine). English is the reverse: some
/// Latin, no Persian. Anything else is accepted rather than refused — a
/// language this build does not know is not a reason to show nothing.
bool nexGreetingLanguageFits(String phrase, String language) {
  if (language == 'auto' || (language != 'fa' && language != 'en')) {
    return true;
  }
  final persian = RegExp(
    r'(?=\p{L})[\u0600-\u06ff]',
    unicode: true,
  ).allMatches(phrase).length;
  final latin = RegExp(r'[A-Za-z]').allMatches(phrase).length;
  return language == 'fa' ? persian > latin : latin > 0 && persian == 0;
}

/// The parts of the day a phrase names.
///
/// Deliberately conservative in one direction only: a phrase that names a
/// *different* part is refused, a phrase that names none is not. Words are
/// matched whole, so "morning" is caught in "good morning" and a phrase about
/// a "nightshift" is not mistaken for one — the greeting is a phrase, not a
/// summary, and the provider is told to keep it to one thought.
Set<NexGreetingPart> _namedParts(String phrase) {
  final lower = phrase.toLowerCase();
  bool says(String word) {
    // Persian attaches its suffixes to the word: «صبح» is inside «صبحت بخیر»
    // and «ظهر» inside «ظهرت بخیر», so those are looked for as stems. Latin
    // words are matched whole, so "night" in "nightshift" is not a greeting.
    if (word.codeUnits.any((unit) => unit > 0x7f)) return lower.contains(word);
    return RegExp(
      '(^|[^\\p{L}])${RegExp.escape(word)}([^\\p{L}]|\$)',
      unicode: true,
    ).hasMatch(lower);
  }

  return {
    for (final MapEntry(key: part, value: words) in _partWords.entries)
      if (words.any(says)) part,
  };
}

const _partWords = <NexGreetingPart, List<String>>{
  // Matched as whole words. The multi-word forms are here for the model's
  // sake — it writes "good morning" rather than "morning" — and either way
  // the answer is the same part.
  NexGreetingPart.morning: ['good morning', 'morning', 'صبح', 'بامداد'],
  NexGreetingPart.afternoon: ['good afternoon', 'afternoon', 'ظهر', 'بعدازظهر'],
  NexGreetingPart.evening: ['good evening', 'evening', 'عصر'],
  NexGreetingPart.night: [
    'good night',
    'tonight',
    'night',
    // The phrase from the bug report: true at 01:00, wrong at 09:00.
    'still up',
    'still awake',
    'up late',
    'شب',
    'بیدار',
    'بیداری',
    'هنوز بیدار',
    'شب‌زنده‌دار',
  ],
};

/// The `yyyy-MM-dd` key for [at] in the device's own time zone.
///
/// The client already has one of these for its caches; it is repeated here in
/// the shape the greeting needs (a local day, never UTC) so a moment can be
/// built without importing the app's preferences into core.
String nexGreetingDateKey(DateTime at) {
  final local = at.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

/// The moment [at] belongs to, in [language].
NexGreetingMoment nexGreetingMomentAt(
  DateTime at, {
  required String language,
}) => NexGreetingMoment(
  dateKey: nexGreetingDateKey(at),
  part: nexGreetingPartOf(at),
  language: language,
);
