import 'package:nex_client/modules/module_api.dart';

String studioFold(String text) => text
    .toLowerCase()
    .replaceAll('ي', 'ی')
    .replaceAll('ك', 'ک')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

class PromptEntry {
  PromptEntry(this.id, this.raw);
  factory PromptEntry.fromRecord(ModuleRecord r) => PromptEntry(r.id, r.body);
  final String id;
  final Map<String, Object?> raw;
  String text(String key) => raw[key] is String ? raw[key] as String : '';
  String get title => text('title');
  String get body => text('body');
  late final int slotCount = PromptTemplate(body).slots.length;
  String get category => text('category');
  String get notes => text('notes');
  bool get block => raw['block'] == true;
  bool get favorite => raw['favorite'] == true;
  bool get valid =>
      raw['v'] == 1 &&
      title.trim().isNotEmpty &&
      title.length <= 100 &&
      body.trim().isNotEmpty &&
      body.length <= 50000 &&
      category.length <= 40 &&
      notes.length <= 2000;
  List<Map<String, Object?>> get history => [
    for (final item
        in raw['history'] is List ? raw['history'] as List : const [])
      if (item is Map && item['body'] is String && item['title'] is String)
        Map<String, Object?>.fromEntries(
          item.entries
              .where((e) => e.key is String)
              .map((e) => MapEntry(e.key as String, e.value)),
        ),
  ].take(10).toList();
  bool matches(String query) =>
      studioFold('$title $body $category $notes').contains(studioFold(query));
}

/// Deliberate double-brace slots avoid mistaking JSON, links or checklists
/// for variables. Substitution is single-pass: inserted values stay literal.
class PromptTemplate {
  PromptTemplate(this.body);
  final String body;
  static final pattern = RegExp(
    r'(?<!\{)\{\{[ \t]*([A-Za-z0-9_\u0600-\u06FF][A-Za-z0-9_\u0600-\u06FF .-]{0,39})[ \t]*\}\}(?!\})',
  );
  late final List<String> slots = List.unmodifiable({
    for (final m in pattern.allMatches(body)) m.group(1)!.trim(),
  });
  String fill(Map<String, String> values) => body.replaceAllMapped(
    pattern,
    (m) => values[m.group(1)!.trim()]?.trim().isNotEmpty == true
        ? values[m.group(1)!.trim()]!
        : m.group(0)!,
  );
  List<String> missing(Map<String, String> values) =>
      slots.where((s) => values[s]?.trim().isNotEmpty != true).toList();
}

Map<String, Object?> promptRevision(Map<String, Object?> raw) => {
  for (final key in ['title', 'body', 'category', 'notes', 'block', 'favorite'])
    if (raw.containsKey(key)) key: raw[key],
};
