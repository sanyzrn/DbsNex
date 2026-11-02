import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../modules/module_registry.dart';
import '../../platform/nex_preferences.dart';
import '../../platform/nex_services.dart';
import '../../widgets/nex_shelf.dart';
import '../../widgets/vault_open_builder.dart';
import '../tools_screen.dart' show nexToggleToolPin;
import 'pinned_module_summary.dart';
import 'tool_catalog.dart';

/// Pinned modules show two small local facts in the title's existing space.
/// Private tools keep their name and lock; no vault records are read here.
class PinnedTools extends StatefulWidget {
  const PinnedTools({
    super.key,
    required this.services,
    required this.preferences,
    this.hidden = false,
  });

  final NexServices services;
  final NexPreferences preferences;
  final bool hidden;

  @override
  State<PinnedTools> createState() => _PinnedToolsState();
}

class _PinnedToolsState extends State<PinnedTools> with WidgetsBindingObserver {
  StreamSubscription<String>? _modules;
  StreamSubscription<void>? _cycle;
  Timer? _day;
  Map<String, NexPinnedSummary> _facts = const {};
  String _signature = '';
  int _generation = 0;
  bool _queued = false;
  bool _foreground = true;

  String get _currentSignature {
    final p = widget.preferences;
    return '${p.pinnedTools.join(',')}|'
        '${nexModulesOn(p).map((m) => m.id).join(',')}|${p.pauseMode}|'
        '${p.cycleSetUp}|${p.cycleMode}|${p.cycleTypicalLength}|'
        '${p.cycleTypicalPeriod}|${p.cyclePregnancyStart}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _attach();
  }

  void _attach() {
    _signature = _currentSignature;
    widget.preferences.addListener(_preferencesChanged);
    _modules = widget.services.moduleChanges.listen((id) {
      if (widget.preferences.pinnedTools.contains('module.$id')) _queueLoad();
    });
    _cycle = widget.services.cycleChanges.listen((_) {
      if (widget.preferences.pinnedTools.contains('module.cycle')) _queueLoad();
    });
  }

  void _preferencesChanged() {
    final next = _currentSignature;
    if (next == _signature) return;
    _signature = next;
    _queueLoad();
  }

  void _queueLoad() {
    if (_queued || !mounted || !_foreground) return;
    _queued = true;
    scheduleMicrotask(() {
      _queued = false;
      if (mounted && _foreground) unawaited(_load());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _queueLoad();
  }

  @override
  void didUpdateWidget(PinnedTools old) {
    super.didUpdateWidget(old);
    if (old.services != widget.services ||
        old.preferences != widget.preferences) {
      unawaited(_modules?.cancel());
      unawaited(_cycle?.cancel());
      old.preferences.removeListener(_preferencesChanged);
      _facts = const {};
      _attach();
    }
    if (old.hidden != widget.hidden ||
        old.services != widget.services ||
        old.preferences != widget.preferences) {
      _generation++;
      _queueLoad();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _queueLoad();
    } else {
      _day?.cancel();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    _day?.cancel();
    final tools = widget.hidden
        ? const <NexTool>[]
        : nexPinnedTools(
            context,
            services: widget.services,
            preferences: widget.preferences,
          );
    final ids = tools
        .where((t) => t.id.startsWith('module.'))
        .map((t) => t.id.substring('module.'.length))
        .toList();
    if (ids.isEmpty) {
      if (_facts.isNotEmpty) setState(() => _facts = const {});
      return;
    }
    final l = AppLocalizations.of(context);
    final now = DateTime.now();
    final results = await Future.wait(
      ids.map((id) async {
        try {
          return MapEntry(
            id,
            await nexPinnedModuleSummary(
              id: id,
              services: widget.services,
              preferences: widget.preferences,
              l10n: l,
              now: now,
            ),
          );
        } catch (_) {
          return MapEntry(id, NexPinnedSummary(l.pinModuleUnavailable));
        }
      }),
    );
    if (!mounted || generation != _generation || widget.hidden) return;
    setState(
      () => _facts = {
        for (final result in results)
          if (result.value != null) result.key: result.value!,
      },
    );
    if (_foreground) {
      _day = Timer(
        DateTime(now.year, now.month, now.day + 1).difference(DateTime.now()),
        _queueLoad,
      );
    }
  }

  @override
  void dispose() {
    _generation++;
    _day?.cancel();
    unawaited(_modules?.cancel());
    unawaited(_cycle?.cancel());
    widget.preferences.removeListener(_preferencesChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.preferences,
    builder: (context, _) {
      final tools = widget.hidden
          ? const <NexTool>[]
          : nexPinnedTools(
              context,
              services: widget.services,
              preferences: widget.preferences,
            );
      final l = AppLocalizations.of(context);
      return AnimatedSize(
        duration: NexMotion.of(context, NexMotion.standard),
        curve: NexMotion.curve,
        alignment: Alignment.topCenter,
        child: tools.isEmpty
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.fromLTRB(
                  NexSpacing.md,
                  NexSpacing.xs,
                  NexSpacing.md,
                  NexSpacing.sm,
                ),
                child: nexShelfPairs([
                  for (final tool in tools)
                    VaultOpenBuilder(
                      key: ValueKey('pinned-tool-${tool.id}'),
                      builder: (context, open) => NexShelfTile(
                        compact: true,
                        title: tool.title,
                        subtitle: tool.subtitle,
                        icon: tool.icon,
                        hue: tool.hue,
                        compactContent: tool.id.startsWith('module.')
                            ? _PinnedFacts(
                                facts:
                                    _facts[tool.id.substring(
                                      'module.'.length,
                                    )] ??
                                    NexPinnedSummary(l.pinModuleLoading),
                              )
                            : null,
                        badge: tool.locked ? nexLockBadge(open: open) : null,
                        onTap: () => unawaited(tool.push(context)),
                        onLongPress: () => unawaited(
                          nexToggleToolPin(context, widget.preferences, tool),
                        ),
                        longPressLabel: l.unpinFromHome,
                      ),
                    ),
                ]),
              ),
      );
    },
  );
}

class _PinnedFacts extends StatelessWidget {
  const _PinnedFacts({required this.facts});
  final NexPinnedSummary facts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          facts.primary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textDirection: nexDirectionOf(facts.primary),
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1.15,
          ),
        ),
        if (facts.secondary case final text?)
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textDirection: nexDirectionOf(text),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.15,
            ),
          ),
      ],
    );
  }
}
