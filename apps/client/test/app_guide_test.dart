import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/app_guide.dart';

/// The assistant answers questions about Nex from the guide: the passages a
/// question is about, in its own language, and nothing for a question about
/// the notes.
void main() {
  final en = NexAppGuide.parse(File('assets/guide/en.md').readAsStringSync());
  final fa = NexAppGuide.parse(File('assets/guide/fa.md').readAsStringSync());

  test('a question about the app finds the passage that answers it', () {
    final pin = en.relevant(
      'How do I pin a tool to the home screen?',
      budget: 3500,
    );
    expect(pin, contains('pin it to the top of the home screen'));

    final ring = en.relevant('Why did my reminder not ring?', budget: 3500);
    expect(ring, contains('test notification'));

    final lock = en.relevant(
      'How can I make the app lock only when I ask?',
      budget: 3500,
    );
    expect(lock, contains('Only when I ask'));

    final move = en.relevant('how do I move to a new phone', budget: 3500);
    expect(move, contains('complete backup'));
  });

  test('in Persian, from the Persian guide', () {
    final lock = fa.relevant('چطور قفل برنامه را روشن کنم؟', budget: 3500);
    expect(lock, contains('قفل برنامه'));

    final trash = fa.relevant(
      'یادداشتی را اشتباهی پاک کردم چطور برگردانم؟',
      budget: 3500,
    );
    expect(trash, contains('سطل زباله'));
  });

  // From the 1.99.96 reviews (UX-11, AI-15/16): a budget one past the first
  // passage's length used to throw, and the throw was swallowed into "no
  // guide"; a contraction or a colloquial Persian question found nothing.
  test('any budget is safe, and casual questions still find the guide', () {
    final line = en.relevant(
      'How do I pin a tool to the home screen?',
      budget: 3500,
    );
    final first = line.split('\n\n').first;
    for (final budget in [first.length - 1, first.length, first.length + 1]) {
      expect(
        () => en.relevant(
          'How do I pin a tool to the home screen?',
          budget: budget,
        ),
        returnsNormally,
      );
    }
    expect(
      en.relevant("how's the app lock turned on?", budget: 3500),
      contains('lock'),
    );
    expect(
      fa.relevant('قفل برنامه رو چجوری روشن کنم؟', budget: 3500),
      contains('قفل برنامه'),
    );
  });

  test('a question about the notes brings no guide', () {
    expect(
      en.relevant('What did I write about the boiler?', budget: 3500),
      isEmpty,
    );
    expect(
      en.relevant('summarise my notes from last week', budget: 3500),
      isEmpty,
    );
    expect(fa.relevant('قبض برق این ماه چقدر بود؟', budget: 3500), isEmpty);
  });

  test('never past its budget, and the passages carry their section', () {
    final text = en.relevant(
      'How do backups and restoring work in Nex?',
      budget: 600,
    );
    expect(text, isNotEmpty);
    expect(text.length, lessThanOrEqualTo(600));
    expect(text, startsWith('['));
  });
}
