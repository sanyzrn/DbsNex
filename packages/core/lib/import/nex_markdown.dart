import 'dart:convert';

/// Only Nex's own envelope: arbitrary Markdown/YAML stays the author's text.
class NexMarkdown {
  const NexMarkdown(
    this.body,
    this.type,
    this.tags,
    this.createdAt,
    this.title,
  );

  final String body;
  final String type;
  final List<String> tags;
  final DateTime createdAt;
  final String? title;

  static NexMarkdown? read(String source) {
    final lines = const LineSplitter().convert(source);
    if (lines.isEmpty || lines.first != '---') return null;
    final end = lines.indexOf('---', 1);
    if (end < 0 || end > 20) return null;
    final fields = <String, String>{};
    for (final line in lines.sublist(1, end)) {
      final colon = line.indexOf(':');
      if (colon < 1) return null;
      final key = line.substring(0, colon).trim();
      if (fields.containsKey(key)) return null;
      fields[key] = line.substring(colon + 1).trim();
    }
    if (fields.containsKey('nex_export')) {
      if (fields['nex_export'] != '1') return null;
    } else if (fields.length != 4 ||
        !RegExp(
          r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$',
        ).hasMatch(fields['id'] ?? '')) {
      return null;
    }
    // Required in both the original export and the explicitly marked format.
    if (!fields.keys.toSet().containsAll([
          'id',
          'type',
          'created_at',
          'tags',
        ]) ||
        fields['id']!.isEmpty ||
        !{
          'text',
          'checklist',
          'link',
          'photo',
          'voice',
          'file',
        }.contains(fields['type'])) {
      return null;
    }
    final created = DateTime.tryParse(fields['created_at']!);
    if (created == null) return null;
    final rawTags = fields['tags']!;
    if (!rawTags.startsWith('[') || !rawTags.endsWith(']')) return null;
    List<String> tags;
    try {
      final decoded = jsonDecode(rawTags);
      if (decoded is! List || decoded.any((value) => value is! String)) {
        return null;
      }
      tags = decoded.cast<String>();
    } on FormatException {
      // Pre-2.5.4 exports used an unquoted YAML flow list. Never interpret
      // this as executable YAML or resolve aliases/custom types.
      tags = rawTags
          .substring(1, rawTags.length - 1)
          .split(',')
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toList();
    }
    var body = lines.sublist(end + 1).join('\n').trim();
    String? title;
    if (fields['nex_export'] == '1') {
      try {
        final decoded = jsonDecode(fields['title'] ?? 'null');
        if (decoded != null && decoded is! String) return null;
        title = decoded as String?;
      } on FormatException {
        return null;
      }
      if (title != null && body.startsWith('# $title\n')) {
        body = body.substring('# $title\n'.length).trim();
      } else if (title != null && body == '# $title') {
        body = '';
      }
    }
    return NexMarkdown(body, fields['type']!, tags, created.toUtc(), title);
  }
}
