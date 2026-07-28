import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_data/nex_data.dart';

import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../widgets/nex_dialog.dart';
import '../platform/nex_services.dart';
import '../widgets/tag_color_picker.dart';

class TagManagerScreen extends StatefulWidget {
  const TagManagerScreen({super.key, required this.services});

  // Takes the service facade, not LibraryMaintenance: maintenance runs inside
  // the database isolate and the UI cannot hold an instance of it.
  final NexServices services;

  @override
  State<TagManagerScreen> createState() => _TagManagerScreenState();
}

class _TagManagerScreenState extends State<TagManagerScreen> {
  List<TagUsage> tags = const [];

  @override
  void initState() {
    super.initState();
    unawaited(reload());
  }

  Future<void> reload() async {
    final loaded = await widget.services.tagUsage();
    if (!mounted) return;
    setState(() => tags = loaded);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tags)),
      // The screen could rename, merge and delete tags but had no way to create
      // one, so a tag could only ever come into existence by tagging a note.
      floatingActionButton: FloatingActionButton(
        onPressed: () => unawaited(_createTag()),
        tooltip: l10n.createTag,
        child: const Icon(Icons.add),
      ),
      body: tags.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.label_outline,
                    size: 40,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.noTagsYet,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: () => unawaited(_createTag()),
                    icon: const Icon(Icons.add),
                    label: Text(l10n.createTag),
                  ),
                ],
              ),
            )
          : ListView.separated(
        padding: EdgeInsets.only(bottom: nexBottomInset(context)),
        itemCount: tags.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final value = tags[index];
          return ListTile(
            minTileHeight: 56,
            leading: _ColorDot(color: value.tag.color),
            title: Text(value.tag.name),
            subtitle: Text(l10n.noteCount(value.count)),
            trailing: PopupMenuButton<String>(
              tooltip: l10n.tagActions,
              onSelected: (action) => act(action, value),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'color', child: Text(l10n.color)),
                PopupMenuItem(value: 'rename', child: Text(l10n.rename)),
                PopupMenuItem(value: 'merge', child: Text(l10n.merge)),
                PopupMenuItem(value: 'delete', child: Text(l10n.delete)),
              ],
            ),
          );
        },
            ),
    );
  }

  Future<void> _createTag() async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.createTag),
        content: NexDialogBody(child: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(hintText: l10n.tagName),
          onSubmitted: (value) => Navigator.pop(ctx, value.trim()),
        )),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l10n.addAction),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    // upsertTag is idempotent on name, so re-adding an existing tag is a no-op
    // rather than a duplicate.
    await widget.services.createTag(name);
    await reload();
  }

  Future<void> act(String action, TagUsage value) async {
    final l10n = AppLocalizations.of(context);
    if (action == 'color') {
      final chosen = await TagColorPicker.show(context, initial: value.tag.color);
      // A dismissal is not a choice; only an explicit Save clears a colour.
      if (chosen != null) {
        await widget.services.setTagColor(
          tagId: value.tag.id,
          color: chosen.color,
        );
      }
    } else if (action == 'rename') {
      final controller = TextEditingController(text: value.tag.name);
      final name = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.renameTag),
          content: NexDialogBody(child: TextField(controller: controller, autofocus: true)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
            TextButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(l10n.rename)),
          ],
        ),
      );
      controller.dispose();
      if (name != null) await widget.services.renameTag(value.tag.id, name);
    } else if (action == 'merge') {
      final target = await showModalBottomSheet<TagUsage>(
        context: context,
        builder: (context) => ListView(
          shrinkWrap: true,
          children: [for (final item in tags.where((item) => item.tag.id != value.tag.id))
            ListTile(title: Text(item.tag.name), onTap: () => Navigator.pop(context, item))],
        ),
      );
      if (target != null) {
        await widget.services
            .mergeTag(sourceId: value.tag.id, targetId: target.tag.id);
      }
    } else if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.deleteTag),
          content: NexDialogBody(child: Text(l10n.deleteTagBody)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
            TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.delete)),
          ],
        ),
      );
      if (ok == true) await widget.services.deleteTag(value.tag.id);
    }
    await reload();
  }
}
/// The tag's accent, or an empty ring when it has none.
class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color});

  final String? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolved = nexParseTagColor(color);
    return SizedBox(
      width: 24,
      height: 24,
      child: Center(
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: resolved ?? Colors.transparent,
            border: resolved == null
                ? Border.all(color: theme.colorScheme.outline)
                : null,
          ),
        ),
      ),
    );
  }
}
