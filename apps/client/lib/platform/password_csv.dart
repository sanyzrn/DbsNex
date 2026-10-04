import 'dart:convert';

import 'vault_store.dart';

/// Why one row of a password export was left out.
enum PasswordCsvIssue {
  /// No password in the row. Google Password Manager exports these for
  /// passkeys, sign-in-with-Google entries and sites marked "never save".
  noPassword,

  /// More or fewer columns than the header, with something in the extras.
  wrongColumns,

  /// A field longer than the vault holds (10,000 characters).
  tooLong,

  /// A quote that is never closed. The row it opens is left out and reading
  /// resumes on the next line, so one stray quote cannot swallow the file.
  unclosedQuote,

  /// Past the most rows one import reads ([maxPasswordCsvRows]).
  tooMany,
}

/// One row that was left out, by its line in the file (the header is line 1),
/// which is the number a spreadsheet shows for it.
class PasswordCsvProblem {
  const PasswordCsvProblem(this.line, this.issue);
  final int line;
  final PasswordCsvIssue issue;
}

/// What a password export yielded: the rows that read cleanly, and the ones
/// that did not, with why.
class PasswordCsvResult {
  const PasswordCsvResult(this.entries, this.problems);
  final List<VaultEntry> entries;
  final List<PasswordCsvProblem> problems;
}

/// The most data rows one import reads, the same as the vault's own bound.
const maxPasswordCsvRows = VaultSnapshot.maxEntries;

/// Reads a password export from Chrome, Google Password Manager, Edge,
/// Firefox or a spreadsheet that saved one.
///
/// A whole-file failure is only for a file that is not a password export at
/// all (no `url`, `username` and `password` columns) or is too large. Any
/// other problem is one row's, reported in [PasswordCsvResult.problems] with
/// its line, while every other row is still imported: a two-thousand-row
/// export used to be refused outright over one row without a password.
///
/// Parsing completes before any vault write.
PasswordCsvResult parsePasswordCsv(String source) {
  if (source.length > 16 * 1024 * 1024) {
    throw const FormatException('CSV too large');
  }
  final text = source.startsWith('﻿') ? source.substring(1) : source;
  final records = _records(text, _delimiter(text));
  if (records.isEmpty) {
    throw const FormatException('Expected a password CSV');
  }
  final head = records.removeAt(0);
  final header = head.fields.map((s) => s.trim().toLowerCase()).toList();
  if (!header.contains('url') ||
      !header.contains('username') ||
      !header.contains('password')) {
    throw const FormatException('Expected a password CSV');
  }

  final entries = <VaultEntry>[];
  final problems = <PasswordCsvProblem>[];
  var read = 0;
  for (final record in records) {
    if (record.unclosed) {
      problems.add(
        PasswordCsvProblem(record.line, PasswordCsvIssue.unclosedQuote),
      );
      continue;
    }
    if (++read > maxPasswordCsvRows) {
      problems.add(PasswordCsvProblem(record.line, PasswordCsvIssue.tooMany));
      continue;
    }
    final values = record.fields;
    // Trailing empty columns are what a spreadsheet adds when a row was
    // touched past its last value; they carry nothing and are not an error.
    if (values.length < header.length ||
        values.skip(header.length).any((v) => v.trim().isNotEmpty)) {
      problems.add(
        PasswordCsvProblem(record.line, PasswordCsvIssue.wrongColumns),
      );
      continue;
    }
    String value(String key) {
      final i = header.indexOf(key);
      return i < 0 ? '' : _unformula(values[i]);
    }

    final password = value('password');
    if (password.isEmpty) {
      problems.add(
        PasswordCsvProblem(record.line, PasswordCsvIssue.noPassword),
      );
      continue;
    }
    final name = value('name').trim();
    final url = value('url').trim();
    final fields = {
      'title': name.isEmpty ? url : name,
      'website': url,
      'login': value('username').trim(),
      'password': password,
      'notes': value('note').isEmpty ? value('notes') : value('note'),
    };
    if (fields.values.any((v) => v.length > 10000)) {
      problems.add(PasswordCsvProblem(record.line, PasswordCsvIssue.tooLong));
      continue;
    }
    final entry = VaultStore.empty(VaultKind.password);
    entries.add(
      VaultEntry(
        id: entry.id,
        kind: entry.kind,
        fields: fields,
        updatedAt: entry.updatedAt,
      ),
    );
  }
  return PasswordCsvResult(entries, problems);
}

/// A value a spreadsheet turned into a formula to keep it text, such as
/// `="0912345"` for a number with a leading zero, read back as the text.
String _unformula(String value) {
  final match = RegExp(r'^="(.*)"$', dotAll: true).firstMatch(value);
  return match == null ? value : match.group(1)!;
}

/// The header line's separator. Chrome writes commas; a spreadsheet saved in
/// a locale with a decimal comma writes semicolons, and some tools tabs.
String _delimiter(String text) {
  final end = text.indexOf('\n');
  final first = end < 0 ? text : text.substring(0, end);
  var best = ',';
  var most = ','.allMatches(first).length;
  for (final candidate in [';', '\t']) {
    final count = candidate.allMatches(first).length;
    if (count > most) {
      best = candidate;
      most = count;
    }
  }
  return best;
}

class _Record {
  _Record(this.line, this.fields, {this.unclosed = false});
  final int line;
  final List<String> fields;
  final bool unclosed;
}

/// RFC 4180, read leniently: a quote inside an unquoted field is a character,
/// and text after a closing quote joins the field. An unclosed quote marks
/// its row and reading starts again at the line after the row began.
List<_Record> _records(String text, String delimiter) {
  final records = <_Record>[];
  var start = 0;
  var line = 1;
  while (start < text.length) {
    var row = <String>[];
    var field = StringBuffer();
    var quoted = false;
    var rowLine = line;
    var i = start;
    var unclosed = false;
    for (; i < text.length; i++) {
      final c = text[i];
      if (quoted) {
        if (c == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          if (c == '\n') line++;
          field.write(c);
        }
        continue;
      }
      if (c == '"' && field.isEmpty) {
        quoted = true;
      } else if (c == delimiter) {
        row.add(field.toString());
        field = StringBuffer();
      } else if (c == '\n' || c == '\r') {
        row.add(field.toString());
        field = StringBuffer();
        if (row.any((v) => v.isNotEmpty)) records.add(_Record(rowLine, row));
        row = <String>[];
        if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        line++;
        rowLine = line;
      } else {
        field.write(c);
      }
    }
    if (quoted) {
      unclosed = true;
    } else {
      row.add(field.toString());
      if (row.any((v) => v.isNotEmpty)) records.add(_Record(rowLine, row));
      break;
    }
    if (unclosed) {
      records.add(_Record(rowLine, const [], unclosed: true));
      // Resume on the line after the one the broken row began on.
      final next = _lineStart(text, rowLine + 1);
      if (next < 0) break;
      start = next;
      line = rowLine + 1;
    }
  }
  return records;
}

/// Where 1-based [line] starts in [text], or -1 past the end.
int _lineStart(String text, int line) {
  var current = 1;
  for (var i = 0; i < text.length; i++) {
    if (current == line) return i;
    if (text[i] == '\n') current++;
  }
  return current == line ? text.length : -1;
}

String passwordIdentity(VaultEntry entry) => jsonEncode([
  entry.value('website'),
  entry.value('login'),
  entry.value('password'),
]);
