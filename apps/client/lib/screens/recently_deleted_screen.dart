import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';
import '../l10n/app_localizations.dart';
import 'package:nex_data/nex_data.dart';

class RecentlyDeletedScreen extends StatefulWidget {
  const RecentlyDeletedScreen({super.key, required this.polish});
  final LibraryMaintenance polish;
  @override
  State<RecentlyDeletedScreen> createState() => _RecentlyDeletedScreenState();
}

class _RecentlyDeletedScreenState extends State<RecentlyDeletedScreen> {
  late List<Note> notes;
  @override
  void initState() {
    super.initState();
    widget.polish.purgeDeletedBefore(DateTime.now().subtract(const Duration(days: 30)));
    notes = widget.polish.deletedNotes();
  }
  void reload() => setState(() => notes = widget.polish.deletedNotes());

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.recentlyDeleted)),
      body: notes.isEmpty
        ? Center(child: Text(l10n.recentlyDeletedEmpty))
        : ListView.builder(
            itemCount: notes.length,
            itemBuilder: (context, index) {
              final note = notes[index];
              return ListTile(
                title: Text(note.searchableDerivedText ?? note.type.name, maxLines: 2),
                trailing: TextButton(
                  onPressed: () { widget.polish.repo.undelete(note.id); reload(); },
                  child: Text(l10n.restore),
                ),
              );
            },
          ),
    );
  }
}