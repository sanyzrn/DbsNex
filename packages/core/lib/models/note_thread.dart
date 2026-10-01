import 'link_url.dart';
import 'note.dart';

/// A thread: notes about the same thing, gathered without moving them (W5.3).
///
/// A view, not a container. A note in a thread is still on the timeline, in
/// search and under its tags exactly as before; it can be in several threads
/// or in none, and leaving a thread — or the thread being deleted — changes
/// nothing about the note. That is what keeps this from being the folders
/// Nex exists to avoid, and the rules that hold it there are written down in
/// `docs/11-roadmap-2.0.md` (W5.3, kill criteria).
class NoteThread {
  const NoteThread({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.noteCount = 0,
    this.lastActivityAt,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Live notes in it — deleted ones are not counted.
  final int noteCount;

  /// When its newest live note was captured; null when it has none.
  final DateTime? lastActivityAt;
}

/// What the app offers right after a capture, when the new note clearly
/// continues something. Always after the save, never required, dismissible.
class ThreadSuggestion {
  /// Add the note to an existing thread.
  const ThreadSuggestion.join({required NoteThread this.thread})
    : withNoteId = null,
      name = null;

  /// Start a thread from the new note and an earlier one it continues.
  const ThreadSuggestion.start({
    required String this.withNoteId,
    required String this.name,
  }) : thread = null;

  final NoteThread? thread;
  final String? withNoteId;

  /// The proposed name of a new thread.
  final String? name;

  bool get joins => thread != null;
}

/// How strongly two notes are about the same thing, from their words and
/// links alone — no model, so it works for everyone and explains itself.
///
/// Significant words are compared as sets (a word repeated ten times in one
/// note is still one word), and the overlap is measured against the smaller
/// note, so a one-line follow-up to a long note can still match it. The
/// thresholds are deliberately high: a wrong suggestion is the thing that
/// would make people turn threads off.
class ThreadAffinity {
  const ThreadAffinity._();

  /// Shared significant words needed before an overlap counts at all.
  static const minSharedWords = 3;

  /// The share of the smaller note's words that must be shared.
  static const minOverlap = 0.34;

  /// A score at or above this joins an existing thread.
  static const joinScore = 1.0;

  /// A higher bar for starting a new thread, which is a bigger ask.
  static const startScore = 1.4;

  static final _word = RegExp(r'[\p{L}\p{N}]+', unicode: true);

  /// Words too common to say two notes are about the same thing.
  static const _stop = {
    'the',
    'and',
    'for',
    'that',
    'this',
    'with',
    'from',
    'have',
    'has',
    'was',
    'were',
    'are',
    'but',
    'not',
    'you',
    'your',
    'our',
    'about',
    'into',
    'then',
    'than',
    'there',
    'their',
    'they',
    'them',
    'what',
    'when',
    'which',
    'will',
    'would',
    'should',
    'could',
    'can',
    'just',
    'also',
    'some',
    'more',
    'most',
    'very',
    'all',
    'any',
    'one',
    'two',
    'get',
    'got',
    'did',
    'does',
    'done',
    'out',
    'now',
    'today',
    'tomorrow',
    'note',
    'notes',
    'http',
    'https',
    'www',
    'com',
    'این',
    'آن',
    'که',
    'را',
    'با',
    'از',
    'به',
    'در',
    'برای',
    'هم',
    'یک',
    'است',
    'بود',
    'شد',
    'شده',
    'کرد',
    'کردم',
    'کنم',
    'کن',
    'باید',
    'می',
    'های',
    'ها',
    'تا',
    'یا',
    'اما',
    'ولی',
    'اگر',
    'چه',
    'هر',
    'دو',
    'امروز',
    'فردا',
    'خیلی',
    'روی',
    'بعد',
    'قبل',
    'نیز',
    'دیگر',
  };

  /// The words of [note] that can say what it is about.
  static Set<String> wordsOf(Note note) {
    final text = [
      note.title,
      note.content,
      note.transcriptText,
      note.ocrText,
      note.linkExcerpt,
      note.caption,
    ].whereType<String>().join(' ').toLowerCase();
    return {
      for (final match in _word.allMatches(text))
        if (match.group(0)!.length >= 3 && !_stop.contains(match.group(0)))
          match.group(0)!,
    };
  }

  static String? _host(Note note) {
    if (note.type != NoteType.link) return null;
    return urlHost(
      normaliseUrl(note.content ?? ''),
    )?.replaceFirst(RegExp(r'^www\.'), '');
  }

  /// 0 for unrelated; [joinScore] and up for "clearly continues".
  static double score(
    Note a,
    Note b, {
    Set<String>? wordsA,
    Set<String>? wordsB,
  }) {
    final left = wordsA ?? wordsOf(a);
    final right = wordsB ?? wordsOf(b);
    var total = 0.0;
    final shared = left.intersection(right).length;
    final smaller = left.length < right.length ? left.length : right.length;
    if (shared >= minSharedWords && smaller > 0) {
      final overlap = shared / smaller;
      if (overlap >= minOverlap) total += overlap * 2;
    }
    final hostA = _host(a);
    if (hostA != null && hostA == _host(b)) {
      total += (a.content?.trim() == b.content?.trim()) ? 1.5 : 1.0;
    }
    final tagsA = {for (final tag in a.tags) tag.id};
    if (total > 0 && b.tags.any((tag) => tagsA.contains(tag.id))) total += 0.2;
    return total;
  }

  /// A short name for a thread started from [note]: its title, or its first
  /// line, cut at a word.
  static String nameFrom(Note note) {
    final source = [note.title, note.content, note.transcriptText, note.ocrText]
        .whereType<String>()
        .map((text) => text.trim())
        .firstWhere((text) => text.isNotEmpty, orElse: () => '');
    var line = source
        .split('\n')
        .map((line) => line.trim().replaceAll(RegExp(r'^[#>*\-\s\[\]x]+'), ''))
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    if (note.type == NoteType.link) {
      line = _host(note) ?? line;
    }
    if (line.length <= 40) return line;
    final cut = line.substring(0, 40);
    final space = cut.lastIndexOf(' ');
    return '${space > 20 ? cut.substring(0, space) : cut}…';
  }
}
