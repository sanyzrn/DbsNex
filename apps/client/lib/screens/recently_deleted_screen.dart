import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_data/nex_data.dart';

import '../l10n/app_localizations.dart';
import '../platform/nex_services.dart';

class RecentlyDeletedScreen extends StatefulWidget {
  const RecentlyDeletedScreen({super.key, required this.services});

  // Takes the service facade, not LibraryMaintenance: maintenance runs inside
  // the database isolate and the UI cannot hold an instance of it.
  final NexServices services;

  @override
  State<RecentlyDeletedScreen> createState() => _RecentlyDeletedScreenState();
}

class _RecentlyDeletedScreenState extends State<RecentlyDeletedScreen> {
  List<Note> notes = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_purgeThenLoad());
  }

  Future<void> _purgeThenLoad() async {
    await widget.services
        .purgeDeletedBefore(DateTime.now().subtract(const Duration(days: 30)));
    await reload();
  }

  Future<void> reload() async {
    final loaded = await widget.services.deletedNotes();
    if (!mounted) return;
    setState(() => notes = loaded);
  }

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
                  onPressed: () async {
                    await widget.services.undelete(note.id);
                    await reload();
                  },
                  child: Text(l10n.restore),
                ),
              );
            },
          ),
    );
  }
}