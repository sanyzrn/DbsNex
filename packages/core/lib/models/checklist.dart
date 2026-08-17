/// One line of a checklist note.
class ChecklistItem {
  const ChecklistItem({required this.text, required this.done});

  final String text;
  final bool done;

  ChecklistItem toggled() => ChecklistItem(text: text, done: !done);

  @override
  bool operator ==(Object other) =>
      other is ChecklistItem && other.text == text && other.done == done;

  @override
  int get hashCode => Object.hash(text, done);

  @override
  String toString() => '${done ? '[x]' : '[ ]'} $text';
}

/// A checklist note stores its items in `content`, as markdown task lines:
///
/// ```
/// - [x] milk
/// - [ ] bread
/// ```
///
/// A table of its own was the obvious alternative and the wrong one. Every
/// other part of this app already knows how to carry a note's `content`:
/// full-text search indexes it, the sync protocol pushes and merges it, the
/// export archive writes it out, and last-writer-wins resolves it. A second
/// table would have needed all of that again, and a checklist would have been
/// the one note type that syncs its body and loses its items.
///
/// The format is also the one people already write by hand, so an exported
/// archive opens as a checklist in any markdown editor, and a text note
/// someone happens to have written this way converts with no translation.
final _itemPattern = RegExp(r'^\s*[-*]?\s*\[([ xX])\]\s?(.*)$');

/// Reads [content] as checklist lines. Anything that is not a task line is
/// kept as an unticked item rather than dropped — text arriving from a
/// conversion, a paste or another editor should not silently lose lines.
List<ChecklistItem> parseChecklist(String? content) {
  final source = content;
  if (source == null || source.trim().isEmpty) return const [];
  final items = <ChecklistItem>[];
  for (final line in source.split('\n')) {
    if (line.trim().isEmpty) continue;
    final match = _itemPattern.firstMatch(line);
    if (match == null) {
      items.add(ChecklistItem(text: line.trim(), done: false));
      continue;
    }
    items.add(
      ChecklistItem(
        text: match.group(2)!.trim(),
        done: match.group(1)!.toLowerCase() == 'x',
      ),
    );
  }
  return items;
}

/// Writes [items] back out in the format [parseChecklist] reads.
///
/// Empty items are dropped on the way out, so deleting a line's text is how
/// you delete the line — there is no separate remove gesture to discover.
String formatChecklist(List<ChecklistItem> items) => [
  for (final item in items)
    if (item.text.trim().isNotEmpty)
      '- [${item.done ? 'x' : ' '}] ${item.text.trim()}',
].join('\n');

/// How many of [items] are ticked, and how many there are.
({int done, int total}) checklistProgress(List<ChecklistItem> items) =>
    (done: items.where((item) => item.done).length, total: items.length);
