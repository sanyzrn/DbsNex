import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart' show nexMaxTagsPerNote;
import 'package:nex_data/nex_data.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import 'nex_dialog.dart';
import 'tag_label.dart';

/// What the picker hands back: an existing tag, or a name to create.
class TagChoice {
  const TagChoice.existing(this.tag) : name = null, color = null;
  const TagChoice.create(this.name, {this.color}) : tag = null;

  final Tag? tag;
  final String? name;
  final String? color;
}

/// Choose tags for a note.
///
/// It offers the tags that actually exist. It used to offer a hardcoded list of
/// five starter names and nothing else — not the tags the user had made, which
/// is the one thing the list needed to contain.
///
/// Picking is now several at once: a tap ticks a tag in place — the sheet
/// stays open — and one Add at the bottom commits the lot. It used to close
/// on every single pick, so three tags on one note meant three rounds of
/// open, pick, wait out the closing animation.
class TagPickerSheet extends StatefulWidget {
  const TagPickerSheet({
    super.key,
    required this.tags,
    this.alreadyOn = const {},
  });

  final List<Tag> tags;

  /// Tags the note already carries, shown as taken rather than hidden, so the
  /// list does not reshuffle as tags are added.
  final Set<String> alreadyOn;

  static Future<List<TagChoice>?> show(
    BuildContext context, {
    required List<Tag> tags,
    Set<String> alreadyOn = const {},
  }) => nexShowSheet<List<TagChoice>>(
    context: context,
    builder: (_) => TagPickerSheet(tags: tags, alreadyOn: alreadyOn),
  );

  static String limitMessage(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'fa'
      ? 'هر یادداشت حداکثر ۳ تگ می‌تواند داشته باشد.'
      : 'Each note can have at most 3 tags.';

  @override
  State<TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends State<TagPickerSheet> {
  final _controller = TextEditingController();
  String _query = '';

  /// Tags ticked this visit, by id — added to the note on Add, not on tap.
  final _chosen = <String>{};

  /// Names typed this visit that the note does not have yet, in order.
  final List<String> _toCreate = [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Tag> get _matches {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.tags;
    return widget.tags
        .where(
          (tag) =>
              tag.name.toLowerCase().contains(query) ||
              nexTagLabel(
                tag,
                AppLocalizations.of(context),
              ).toLowerCase().contains(query),
        )
        .toList();
  }

  bool get _canCreate {
    if (widget.alreadyOn.length + _chosen.length + _toCreate.length >=
        nexMaxTagsPerNote) {
      return false;
    }
    final name = _query.trim();
    if (name.isEmpty) return false;
    return !widget.tags.any(
      (tag) =>
          tag.name.toLowerCase() == name.toLowerCase() ||
          nexTagLabel(tag, AppLocalizations.of(context)).toLowerCase() ==
              name.toLowerCase(),
    );
  }

  /// How many tag slots the note still has, counting what is ticked here.
  bool get _full {
    final at = widget.alreadyOn.length + _chosen.length + _toCreate.length;
    return at >= nexMaxTagsPerNote;
  }

  void _toggle(Tag tag) {
    setState(() {
      if (!_chosen.remove(tag.id)) {
        if (_full) return;
        _chosen.add(tag.id);
      }
    });
  }

  void _create(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _toCreate.add(trimmed);
      _controller.clear();
      _query = '';
    });
  }

  void _add() {
    // The create field's pending name goes with the rest rather than being
    // lost to an early Add.
    if (_canCreate) _toCreate.add(_query.trim());
    Navigator.pop(context, [
      for (final tag in widget.tags)
        if (_chosen.contains(tag.id)) TagChoice.existing(tag),
      for (final name in _toCreate) TagChoice.create(name),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final matches = _matches;
    final atLimit = widget.alreadyOn.length >= nexMaxTagsPerNote;
    final legacyOverflow = widget.alreadyOn.length > nexMaxTagsPerNote;
    final picked = _chosen.length + _toCreate.length;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NexSpacing.lg,
              0,
              NexSpacing.lg,
              NexSpacing.sm,
            ),
            child: Text(l10n.addTag, style: theme.textTheme.titleLarge),
          ),
          if (atLimit)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: NexSpacing.lg),
              child: Text(
                legacyOverflow
                    ? (Localizations.localeOf(context).languageCode == 'fa'
                          ? 'این یادداشت بیش از ۳ تگ قدیمی دارد؛ از جزئیات یادداشت تگ‌های اضافه را حذف کنید. هیچ تگی خودکار پاک نمی‌شود.'
                          : 'This older note has over 3 tags. Remove extras in note details; no tags are deleted automatically.')
                    : TagPickerSheet.limitMessage(context),
                style: theme.textTheme.bodySmall,
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: NexSpacing.lg),
            // Finds a tag or names a new one: the shared search box, with
            // Done making the name a tag rather than searching.
            child: NexSearchField(
              controller: _controller,
              contextMenuBuilder: nexReadingMenu,
              autofocus: !atLimit,
              enabled: !atLimit,
              textInputAction: TextInputAction.done,
              hintText: l10n.tagName,
              onChanged: (value) => setState(() => _query = value),
              onSubmitted: (value) {
                // Done on the keyboard makes the name a ticked tag — the
                // sheet stays open, like every other pick here — rather
                // than committing the whole visit.
                if (_canCreate) _create(value);
              },
            ),
          ),
          const SizedBox(height: NexSpacing.sm),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_canCreate)
                    ListTile(
                      leading: const Icon(Icons.add),
                      title: Text(_query.trim()),
                      subtitle: Text(l10n.createTag),
                      onTap: () => _create(_query),
                    ),
                  if (matches.isEmpty && !_canCreate && _toCreate.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(NexSpacing.lg),
                      child: Text(
                        l10n.noTagsYet,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  if (matches.isNotEmpty || _toCreate.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        NexSpacing.lg,
                        NexSpacing.xs,
                        NexSpacing.lg,
                        0,
                      ),
                      // Chips wrap by their own width instead of stacking one
                      // per row — three short tag names or five fit the same
                      // row a single long one takes alone.
                      child: Wrap(
                        spacing: NexSpacing.sm,
                        runSpacing: NexSpacing.sm,
                        children: [
                          for (final tag in matches)
                            _TagOption(
                              tag: tag,
                              alreadyOn: widget.alreadyOn.contains(tag.id),
                              checked: _chosen.contains(tag.id),
                              // Full is full for tags not yet ticked: a
                              // tick is un-tickable whatever the count,
                              // because taking one off is how room is made.
                              disabled:
                                  atLimit ||
                                  (_full && !_chosen.contains(tag.id)),
                              onTap: () => _toggle(tag),
                            ),
                          // A name typed and entered: on the note's card as a
                          // ticked pill of its own, so what Add will do is
                          // all on screen. Its ✕-free removal is a second
                          // tap on it.
                          for (final name in _toCreate)
                            _PendingTagOption(
                              name: name,
                              onTap: () =>
                                  setState(() => _toCreate.remove(name)),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: NexSpacing.md),
          // The one commit: everything ticked, in one press, with the sheet
          // staying open for second thoughts until then. No check icon on
          // the button — the check is what a ticked pill wears, and the
          // button saying it too would read as a state it does not have.
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NexSpacing.lg,
              0,
              NexSpacing.lg,
              NexSpacing.sm,
            ),
            child: FilledButton(
              onPressed: atLimit || picked == 0 ? null : _add,
              child: Text(l10n.addAction),
            ),
          ),
        ],
      ),
    );
  }
}

/// One tag in the wrap: a pill carrying its dot and name, checked off and
/// inert once the note already carries it.
class _TagOption extends StatelessWidget {
  const _TagOption({
    required this.tag,
    required this.alreadyOn,
    required this.checked,
    required this.disabled,
    required this.onTap,
  });

  final Tag tag;
  final bool alreadyOn;
  final bool checked;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dot = nexParseTagColor(tag.color);
    final pill = Material(
      color: alreadyOn || checked
          ? scheme.surfaceContainerHighest
          : scheme.surfaceContainerLowest,
      shape: StadiumBorder(side: BorderSide(color: scheme.outline)),
      child: InkWell(
        onTap: alreadyOn || disabled ? null : onTap,
        customBorder: const StadiumBorder(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: NexSpacing.md,
              vertical: NexSpacing.sm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dot != null)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dot,
                    ),
                  ),
                if (dot != null) const SizedBox(width: NexSpacing.contentGap),
                Text(
                  nexTagLabel(tag, AppLocalizations.of(context)),
                  style: alreadyOn
                      ? theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        )
                      : theme.textTheme.bodyMedium,
                ),
                if (alreadyOn || checked) ...[
                  const SizedBox(width: NexSpacing.contentGap),
                  Icon(Icons.check, size: 16, color: scheme.onSurfaceVariant),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return Semantics(selected: alreadyOn || checked, child: pill);
  }
}

/// A name typed this visit, ticked and waiting for Add: the pill a tag that
/// does not exist yet gets to wear so the whole choice is on screen.
class _PendingTagOption extends StatelessWidget {
  const _PendingTagOption({required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      shape: StadiumBorder(
        side: BorderSide(color: scheme.outline, style: BorderStyle.solid),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: NexSpacing.md,
              vertical: NexSpacing.sm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add, size: 16),
                const SizedBox(width: NexSpacing.contentGap),
                Text(name, style: theme.textTheme.bodyMedium),
                const SizedBox(width: NexSpacing.contentGap),
                Icon(Icons.check, size: 16, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
