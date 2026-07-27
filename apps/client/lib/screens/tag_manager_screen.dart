import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_data/nex_data.dart';

import '../l10n/app_localizations.dart';
import '../platform/nex_services.dart';

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
      body: ListView.separated(
        itemCount: tags.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final value = tags[index];
          return ListTile(
            minTileHeight: 56,
            title: Text(value.tag.name),
            subtitle: Text(l10n.noteCount(value.count)),
            trailing: PopupMenuButton<String>(
              tooltip: l10n.tagActions,
              onSelected: (action) => act(action, value),
              itemBuilder: (_) => [
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

  Future<void> act(String action, TagUsage value) async {
    final l10n = AppLocalizations.of(context);
    if (action == 'rename') {
      final controller = TextEditingController(text: value.tag.name);
      final name = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.renameTag),
          content: TextField(controller: controller, autofocus: true),
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
          content: Text(l10n.deleteTagBody),
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