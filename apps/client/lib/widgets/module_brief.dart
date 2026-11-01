import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../modules/module_registry.dart';
import '../modules/nex_module_store.dart';
import '../modules/nex_stored_module.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';

/// Local module facts are joined only at display time. They never enter an
/// AI request, its cache or its fingerprint.
class NexModuleBrief extends StatefulWidget {
  const NexModuleBrief({
    super.key,
    required this.services,
    required this.preferences,
    required this.builder,
  });
  final NexServices services;
  final NexPreferences preferences;
  final Widget Function(BuildContext, String?) builder;

  @override
  State<NexModuleBrief> createState() => _NexModuleBriefState();
}

class _NexModuleBriefState extends State<NexModuleBrief>
    with WidgetsBindingObserver {
  StreamSubscription<String>? _changes;
  Timer? _midnight;
  String? _line;
  String _enabled = '';
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _attach();
  }

  void _attach() {
    _changes = widget.services.moduleChanges.listen((_) => unawaited(_load()));
    widget.preferences.addListener(_preferencesChanged);
    _enabled =
        '${nexModulesOn(widget.preferences).map((m) => m.id).join(',')}|${widget.preferences.briefHabitsAllowed}';
  }

  void _preferencesChanged() {
    final enabled =
        '${nexModulesOn(widget.preferences).map((m) => m.id).join(',')}|${widget.preferences.briefHabitsAllowed}';
    if (enabled == _enabled) return;
    _enabled = enabled;
    unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(NexModuleBrief oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.services != widget.services ||
        oldWidget.preferences != widget.preferences) {
      unawaited(_changes?.cancel());
      oldWidget.preferences.removeListener(_preferencesChanged);
      _attach();
      unawaited(_load());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final l10n = AppLocalizations.of(context);
    final services = widget.services;
    final modules = nexModulesOn(
      widget.preferences,
    ).whereType<NexStoredModule>().toList();
    final lines = <String>[];
    for (final module in modules) {
      if (module.id == 'habits' && !widget.preferences.briefHabitsAllowed) {
        continue;
      }
      try {
        final line = await module.briefLine(
          NexModuleStore(services, module.id),
          l10n,
        );
        if (line != null && line.isNotEmpty) lines.add(line);
      } catch (_) {
        // A module's unavailable store must not hide the rest of the brief.
      }
    }
    if (!mounted || generation != _generation) return;
    setState(() => _line = lines.isEmpty ? null : lines.join('\n'));
    _midnight?.cancel();
    final now = DateTime.now();
    _midnight = Timer(
      DateTime(now.year, now.month, now.day + 1).difference(now),
      () => unawaited(_load()),
    );
  }

  @override
  void dispose() {
    _generation++;
    _midnight?.cancel();
    unawaited(_changes?.cancel());
    widget.preferences.removeListener(_preferencesChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _line);
}
