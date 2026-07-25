import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;

import '../platform/nex_services.dart';

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key, required this.services});

  final NexServices services;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  String? _status;

  Future<void> _export() async {
    try {
      final file = await widget.services.exportNow();
      setState(() => _status = 'Exported: ${p.basename(file.path)}');
    } catch (e) {
      setState(() => _status = 'Export failed');
    }
  }

  Future<void> _restore() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore backup?'),
        content: const Text(
          'This replaces the current local database with the latest automatic backup.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      widget.services.restoreLatestBackup();
      setState(() => _status = 'Restored. Restart the app to continue.');
    } catch (_) {
      setState(() => _status = 'No backup available');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(NexSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Settings', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: NexSpacing.md),
          ListTile(
            leading: const Icon(Icons.ios_share_outlined),
            title: const Text('Export'),
            subtitle: const Text('JSON + Markdown + media archive'),
            onTap: _export,
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Restore'),
            subtitle: const Text('Recover from latest automatic backup'),
            onTap: _restore,
          ),
          if (_status != null) ...[
            const SizedBox(height: NexSpacing.sm),
            Text(_status!, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: NexSpacing.md),
        ],
      ),
    );
  }
}
