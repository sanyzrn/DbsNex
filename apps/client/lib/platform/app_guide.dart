import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';

/// The in-app guide, as something the assistant can answer from.
///
/// The guide (`assets/guide/{en,fa}.md`) is the one place that says how every
/// screen and setting works, in both languages, and it is kept in step with
/// the app by rule. The assistant never saw it, so "how do I pin a tool?" or
/// "why did my reminder not ring?" got an answer made up from what a notes
/// app usually does. Now the passages a question is about go with it — a
/// few of them, not the whole guide, which would cost every question
/// thousands of tokens and swamp a model on the phone.
///
/// Passages are the guide's own paragraphs and list items, each carrying its
/// section's heading. They are ranked by the question's words, weighted by
/// how rare each word is in the guide, so "lock" counts for more than "the".
class NexAppGuide {
  NexAppGuide._(this._passages);

  /// Splits [markdown] into passages: every paragraph and list item under a
  /// `## ` heading, without the pictures.
  factory NexAppGuide.parse(String markdown) {
    final passages = <_Passage>[];
    var section = '';
    final paragraph = StringBuffer();
    void flush() {
      final text = paragraph.toString().trim();
      paragraph.clear();
      if (text.isEmpty) return;
      passages.add(_Passage(section, text));
    }

    for (final raw in const LineSplitter().convert(markdown)) {
      final line = raw.trimRight();
      if (line.startsWith('# ')) continue;
      if (line.startsWith('## ')) {
        flush();
        section = line.substring(3).trim();
        continue;
      }
      if (line.startsWith('![')) continue;
      if (line.trim().isEmpty) {
        flush();
        continue;
      }
      // Each list item on its own: a question in "Common questions" is a
      // passage, not the whole list.
      if (line.startsWith('- ')) flush();
      if (paragraph.isNotEmpty) paragraph.write(' ');
      paragraph.write(line.trim());
    }
    flush();
    return NexAppGuide._(passages);
  }

  final List<_Passage> _passages;

  static final Map<String, Future<NexAppGuide>> _loaded = {};

  /// The guide in [languageCode] (`fa` or anything else for English), read
  /// once per process.
  static Future<NexAppGuide> load(String languageCode, {AssetBundle? bundle}) {
    final code = languageCode == 'fa' ? 'fa' : 'en';
    return _loaded[code] ??= (bundle ?? rootBundle)
        .load('assets/guide/$code.md')
        .then(
          (data) => NexAppGuide.parse(
            utf8.decode(
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            ),
          ),
        );
  }

  /// The passages [question] is about, best first, within [budget]
  /// characters — or empty when it is not a question about the app.
  ///
  /// The guide in the question's own script: a Persian question is read
  /// against the Persian guide whatever language the app is in.
  static Future<String> forQuestion(
    String question, {
    required int budget,
    AssetBundle? bundle,
  }) async {
    try {
      final persian = RegExp(r'[؀-ۿ]').hasMatch(question);
      final guide = await load(persian ? 'fa' : 'en', bundle: bundle);
      return guide.relevant(question, budget: budget);
    } catch (_) {
      return '';
    }
  }

  /// See [forQuestion].
  String relevant(String question, {required int budget}) {
    final terms = _terms(question).toSet();
    if (terms.isEmpty || _passages.isEmpty) return '';
    final cued = _cued(question);
    final folded = [for (final p in _passages) _fold('${p.section} ${p.text}')];
    final heads = [for (final p in _passages) _fold(p.section)];
    // How rare each word is across the guide: a word in every passage says
    // nothing about which one is meant.
    final weight = <String, double>{};
    for (final term in terms) {
      final count = folded.where((text) => _has(text, term)).length;
      if (count == 0) continue;
      weight[term] = math.log((_passages.length + 1) / count);
    }
    if (weight.isEmpty) return '';
    final scored = <(int, double)>[];
    for (var i = 0; i < _passages.length; i++) {
      var score = 0.0;
      var matched = 0;
      for (final MapEntry(key: term, value: w) in weight.entries) {
        if (!_has(folded[i], term)) continue;
        matched++;
        score += w * (_has(heads[i], term) ? 1.5 : 1);
      }
      if (matched == 0) continue;
      scored.add((i, score * (1 + 0.25 * (matched - 1))));
    }
    if (scored.isEmpty) return '';
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    // Only for a question asked about the app. The guide quotes the kind of
    // thing people ask the assistant to do — "remind me Saturday at 9",
    // "summarise my work notes" — so a request about the notes can match it
    // as strongly as a question about Nex does; its wording is what tells
    // them apart.
    final best = scored.first.$2;
    if (!cued || best < 2) return '';
    final out = StringBuffer();
    for (final (index, score) in scored) {
      if (score < best * 0.35) break;
      final passage = _passages[index];
      final line = '[${passage.section}] ${passage.text}';
      if (out.length + line.length + 2 > budget) {
        if (out.isEmpty) out.write(line.substring(0, math.max(0, budget)));
        break;
      }
      if (out.isNotEmpty) out.write('\n\n');
      out.write(line);
    }
    return out.toString();
  }

  /// Whether a question reads as one about using the app.
  static bool _cued(String question) {
    final text = ' ${_fold(question)} ';
    return _cues.any(text.contains);
  }

  static const _cues = [
    ' how ',
    ' where ',
    ' why ',
    ' can i ',
    ' what is ',
    ' what does ',
    ' setting',
    ' nex ',
    ' app ',
    ' turn on',
    ' turn off',
    ' enable',
    ' disable',
    ' feature',
    ' button',
    ' does not work',
    ' not working',
    ' چطور',
    ' چگونه',
    ' کجا',
    ' چرا',
    ' تنظیم',
    ' نکس',
    ' برنامه',
    ' اپ ',
    ' قابلیت',
    ' روشن',
    ' خاموش',
    ' کار نمی',
    ' دکمه',
    ' استفاده',
  ];

  static Iterable<String> _terms(String question) => _fold(question)
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((word) => word.length >= 3 && !_stop.contains(word));

  /// Lower case, Arabic letters and digits as Persian ones, no joiners.
  static String _fold(String text) => text
      .toLowerCase()
      .replaceAll('ي', 'ی')
      .replaceAll('ك', 'ک')
      .replaceAll('‌', ' ')
      .replaceAll('ة', 'ه');

  /// A shared stem is enough: "reminders" asked, "reminder" written.
  static bool _has(String text, String term) => text.contains(
    term.length > 5 ? term.substring(0, term.length - 1) : term,
  );

  static const _stop = {
    'the',
    'and',
    'for',
    'with',
    'how',
    'can',
    'what',
    'why',
    'where',
    'when',
    'does',
    'did',
    'not',
    'are',
    'you',
    'your',
    'this',
    'that',
    'there',
    'have',
    'has',
    'get',
    'use',
    'from',
    'into',
    'about',
    'nex',
    'app',
    'want',
    'way',
    'will',
    'should',
    'would',
    'could',
    'please',
    'make',
    'چطور',
    'چگونه',
    'کجا',
    'چرا',
    'برای',
    'این',
    'آن',
    'که',
    'را',
    'با',
    'از',
    'به',
    'در',
    'هم',
    'یک',
    'می',
    'کنم',
    'کنید',
    'کرد',
    'شود',
    'شد',
    'است',
    'هست',
    'نیست',
    'باید',
    'چیه',
    'چیست',
    'نکس',
    'برنامه',
    'اپ',
    'چی',
    'میشه',
    'بکنم',
    'کار',
    'رو',
    'من',
    'تو',
    'خودم',
  };
}

class _Passage {
  const _Passage(this.section, this.text);
  final String section;
  final String text;
}
