import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/documents/text_import.dart';
import 'package:nex_client/platform/password_csv.dart';

void main() {
  test(
    'quoted fields and multiline notes round-trip without trimming passwords',
    () {
      final e = parsePasswordCsv(
        '﻿name,url,username,password,note\r\n"حساب, یک",https://example.test,u," p""ass ","line 1\nline 2"\r\n',
      ).entries.single;
      expect(e.title, 'حساب, یک');
      expect(e.value('password'), ' p"ass ');
      expect(e.value('notes'), 'line 1\nline 2');
    },
  );

  test('a file that is not a password export is refused whole', () {
    for (final s in ['', 'name,url\na,b', 'title,notes\nx,y']) {
      expect(() => parsePasswordCsv(s), throwsFormatException);
    }
  });

  test('one bad row does not stop the others: good rows import, bad rows are '
      'reported by line', () {
    final result = parsePasswordCsv(
      'name,url,username,password,note\n'
      'Mail,https://mail.test,me,secret1,\n' // line 2: fine
      'Passkey,https://pk.test,me,,\n' // line 3: no password
      'Bank,https://bank.test,me,secret2,,extra\n' // line 4: extra column
      'Shop,https://shop.test,me,secret3,\n', // line 5: fine
    );
    expect(result.entries.map((e) => e.title), ['Mail', 'Shop']);
    expect(result.problems.map((p) => (p.line, p.issue)), [
      (3, PasswordCsvIssue.noPassword),
      (4, PasswordCsvIssue.wrongColumns),
    ]);
  });

  test('Persian letters and stray quotes inside passwords are kept', () {
    final result = parsePasswordCsv(
      'name,url,username,password\n'
      'سایت,https://a.test,کاربر,رمزِفارسی۱۲۳\n'
      'B,https://b.test,u,ab"cd\n',
    );
    expect(result.problems, isEmpty);
    expect(result.entries[0].value('password'), 'رمزِفارسی۱۲۳');
    expect(result.entries[0].value('login'), 'کاربر');
    expect(result.entries[1].value('password'), 'ab"cd');
  });

  test('numbers a spreadsheet kept as ="…" formulas are read as text', () {
    final e = parsePasswordCsv(
      'name,url,username,password\nA,https://a.test,"=""0912345""","=""007"""\n',
    ).entries.single;
    expect(e.value('login'), '0912345');
    expect(e.value('password'), '007');
  });

  test('an unclosed quote loses only its own row', () {
    final result = parsePasswordCsv(
      'name,url,username,password\n'
      'A,https://a.test,u,"broken\n'
      'B,https://b.test,u,fine\n',
    );
    expect(result.problems.single.line, 2);
    expect(result.problems.single.issue, PasswordCsvIssue.unclosedQuote);
    expect(result.entries.single.title, 'B');
  });

  test('semicolon-separated files and trailing empty columns are read', () {
    final result = parsePasswordCsv(
      'name;url;username;password\nA;https://a.test;u;p1;;\n',
    );
    expect(result.problems, isEmpty);
    expect(result.entries.single.value('password'), 'p1');
  });

  test('a two-thousand-row export imports in full', () {
    final rows = [
      for (var i = 0; i < 2500; i++) 'S$i,https://s$i.test,u$i,p$i',
    ];
    final result = parsePasswordCsv(
      'name,url,username,password\n${rows.join('\n')}\n',
    );
    expect(result.entries, hasLength(2500));
    expect(result.problems, isEmpty);
  });

  test('a Windows-1256 file a spreadsheet saved again still decodes', () {
    // "رمز" in Windows-1256: ر=0xD1, م=0xE3, ز=0xD2.
    final bytes = [
      ...utf8.encode('name,url,username,password\nA,https://a.test,u,'),
      0xD1,
      0xE3,
      0xD2,
      0x0A,
    ];
    final e = parsePasswordCsv(NexTextImport.decodeText(bytes)).entries.single;
    expect(e.value('password'), 'رمز');
  });
}
