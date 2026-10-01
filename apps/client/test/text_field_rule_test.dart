import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ADR-037, enforced: how a field that takes a person's own words is built.
///
/// 1. More than one line of it is a `NexTextField` — the platform's own
///    editor on Android, where every paragraph keeps its own direction. A
///    bare `TextField` gives the whole text one direction, which is what
///    put a Persian sentence's `!` on the wrong end and turned the
///    selection handles around while editing.
/// 2. A single line states its direction: it is built inside
///    `NexAutoDirection`, which follows the script being typed, or it says
///    `textDirection:` itself (a link, a key, an amount: left to right).
///
/// A field added later that breaks either fails here, with where it is.
void main() {
  final fields = _fields();

  test('the scan finds the fields', () {
    // Guards the scanner itself: a parsing slip that found nothing would
    // pass both rules below.
    expect(fields.length, greaterThan(20));
  });

  test('multi-line user text is a NexTextField', () {
    final offenders = [
      for (final field in fields)
        if (field.multiLine) field.where,
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'Use NexTextField (lib/widgets/nex_text_field.dart) for these: a '
          'multi-line TextField lays a two-language note out in one '
          'direction. See ADR-037.',
    );
  });

  test('every single-line field states its direction', () {
    final offenders = [
      for (final field in fields)
        if (!field.multiLine && !field.directed) field.where,
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'Build these inside NexAutoDirection, or give them a '
          'textDirection. See ADR-037.',
    );
  });
}

class _Field {
  _Field(this.where, this.args, {required this.inAutoDirection});

  final String where;
  final String args;
  final bool inAutoDirection;

  bool get multiLine {
    if (args.contains('TextInputType.multiline') ||
        RegExp(r'\bexpands:\s*(?!false)').hasMatch(args) ||
        RegExp(r'\bminLines:').hasMatch(args)) {
      return true;
    }
    final maxLines = RegExp(r'\bmaxLines:\s*([^,\n]+)').firstMatch(args);
    return maxLines != null && maxLines.group(1)!.trim() != '1';
  }

  bool get directed =>
      inAutoDirection || RegExp(r'\btextDirection:').hasMatch(args);
}

List<_Field> _fields() {
  final found = <_Field>[];
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.endsWith('nex_text_field.dart'));
  for (final file in files) {
    final source = _withoutComments(file.readAsStringSync());
    for (final match in RegExp(
      r'\b(TextField|TextFormField)\(',
    ).allMatches(source)) {
      final open = match.end - 1;
      final close = _closing(source, open);
      final before = source.substring(
        (match.start - 400).clamp(0, match.start),
        match.start,
      );
      final line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
      found.add(
        _Field(
          '${file.path}:$line',
          source.substring(open, close),
          // `builder: (context, direction) => TextField(` under a
          // NexAutoDirection — or a field handed to one whole, as the
          // vault editor builds it.
          inAutoDirection:
              RegExp(
                r'NexAutoDirection\([^;]*builder:\s*\([^)]*\)\s*=>\s*$',
              ).hasMatch(before.trimRight()) ||
              RegExp(r'final field = $').hasMatch(before) &&
                  source.substring(close).contains('NexAutoDirection('),
        ),
      );
    }
  }
  return found;
}

/// Comments blanked out, line breaks kept, so a `maxLines:` in prose does
/// not count and line numbers stay true.
String _withoutComments(String source) => source.replaceAllMapped(
  RegExp(r'//[^\n]*'),
  (m) => ' ' * m.group(0)!.length,
);

int _closing(String source, int open) {
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    final c = source[i];
    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') {
      depth--;
      if (depth == 0) return i;
    }
    if (c == "'" || c == '"') {
      final end = source.indexOf(c, i + 1);
      if (end > i) i = end;
    }
  }
  return source.length;
}
