import 'package:flutter/material.dart';
import 'package:nex_data/nex_data.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import 'nex_dialog.dart';

/// What the picker hands back: an existing tag, or a name to create.
class TagChoice {
  const TagChoice.existing(this.tag) : name = null, color = null;
  const TagChoice.create(this.name, {this.color}) : tag = null;

  final Tag? tag;
  final String? name;
  final String? color;
}

/// Choose a tag for a note.
///
/// It offers the tags that actually exist. It used to offer a hardcoded list of
/// five starter names and nothing else — not the tags the user had made, which
/// is the one thing the list needed to contain.
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

  static Future<TagChoice?> show(
    BuildContext context, {
    required List<Tag> tags,
    Set<String> alreadyOn = const {},
  }) => nexShowSheet<TagChoice>(
    context: context,
    builder: (_) => TagPickerSheet(tags: tags, alreadyOn: alreadyOn),
  );

  @override
  State<TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends State<TagPickerSheet> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Tag> get _matches {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.tags;
    return widget.tags
        .where((tag) => tag.name.toLowerCase().contains(query))
        .toList();
  }

  bool get _canCreate {
    final name = _query.trim();
    if (name.isEmpty) return false;
    return !widget.tags.any(
      (tag) => tag.name.toLowerCase() == name.toLowerCase(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final matches = _matches;
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: NexSpacing.lg),
            child: TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: l10n.tagName,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _query = value),
              onSubmitted: (value) {
                if (_canCreate) {
                  Navigator.pop(context, TagChoice.create(value.trim()));
                }
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
                      onTap: () => Navigator.pop(
                        context,
                        TagChoice.create(_query.trim()),
                      ),
                    ),
                  if (matches.isEmpty && !_canCreate)
                    Padding(
                      padding: const EdgeInsets.all(NexSpacing.lg),
                      child: Text(
                        l10n.noTagsYet,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  if (matches.isNotEmpty)
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
                              onTap: () => Navigator.pop(
                                context,
                                TagChoice.existing(tag),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: NexSpacing.md),
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
    required this.onTap,
  });

  final Tag tag;
  final bool alreadyOn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dot = nexParseTagColor(tag.color);
    final pill = Material(
      color: alreadyOn
          ? scheme.surfaceContainerHighest
          : scheme.surfaceContainerLowest,
      shape: StadiumBorder(side: BorderSide(color: scheme.outline)),
      child: InkWell(
        onTap: alreadyOn ? null : onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NexSpacing.md,
            vertical: NexSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dot ?? Colors.transparent,
                  border: dot == null
                      ? Border.all(color: scheme.outline)
                      : null,
                ),
              ),
              const SizedBox(width: NexSpacing.contentGap),
              Text(
                tag.name,
                style: alreadyOn
                    ? theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      )
                    : theme.textTheme.bodyMedium,
              ),
              if (alreadyOn) ...[
                const SizedBox(width: NexSpacing.contentGap),
                Icon(Icons.check, size: 16, color: scheme.onSurfaceVariant),
              ],
            ],
          ),
        ),
      ),
    );
    return alreadyOn ? Semantics(label: tag.name, child: pill) : pill;
  }
}
