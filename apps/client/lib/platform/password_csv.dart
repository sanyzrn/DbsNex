import 'dart:convert';
import 'vault_store.dart';

/// Chrome's UTF-8 CSV export. Quoted commas, quotes and newlines are preserved.
/// Parsing completes before any vault write; malformed files change nothing.
List<VaultEntry> parsePasswordCsv(String source) {
  if (source.length > 4 * 1024 * 1024) {
    throw const FormatException('CSV too large');
  }
  final rows = <List<String>>[];
  var row = <String>[];
  var field = StringBuffer();
  var quoted = false, closed = false;
  final text = source.startsWith('\ufeff') ? source.substring(1) : source;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
          closed = true;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"' && field.isEmpty && !closed) {
      quoted = true;
    } else if (c == ',' || c == '\n' || c == '\r') {
      row.add(field.toString());
      field = StringBuffer();
      closed = false;
      if (c != ',') {
        if (row.any((v) => v.isNotEmpty)) rows.add(row);
        row = <String>[];
        if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      }
    } else {
      if (closed || c == '"') {
        throw const FormatException('Invalid CSV quoting');
      }
      field.write(c);
    }
  }
  if (quoted) throw const FormatException('Unclosed CSV field');
  row.add(field.toString());
  if (row.any((v) => v.isNotEmpty)) rows.add(row);
  if (rows.isEmpty || rows.length > 2001) {
    throw const FormatException('Invalid CSV size');
  }
  final header = rows.removeAt(0).map((s) => s.trim().toLowerCase()).toList();
  if (!header.contains('url') ||
      !header.contains('username') ||
      !header.contains('password') ||
      header.toSet().length != header.length) {
    throw const FormatException('Expected Chrome password CSV');
  }
  return rows.map((values) {
    if (values.length != header.length) {
      throw const FormatException('Invalid CSV row');
    }
    String value(String key) =>
        header.contains(key) ? values[header.indexOf(key)] : '';
    if (value('password').isEmpty) {
      throw const FormatException('Password missing');
    }
    final entry = VaultStore.empty(VaultKind.password);
    final fields = {
      'title': value('name').isEmpty ? value('url') : value('name'),
      'website': value('url'),
      'login': value('username'),
      'password': value('password'),
      'notes': value('note'),
    };
    if (fields.values.any((v) => v.length > 10000)) {
      throw const FormatException('CSV field too large');
    }
    return VaultEntry(
      id: entry.id,
      kind: entry.kind,
      fields: fields,
      updatedAt: entry.updatedAt,
    );
  }).toList();
}

String passwordIdentity(VaultEntry entry) => jsonEncode([
  entry.value('website'),
  entry.value('login'),
  entry.value('password'),
]);
