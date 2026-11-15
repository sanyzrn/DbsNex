import 'dart:async';
import 'dart:math' as math;

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

/// The tools pinned to the home screen, as one row of small live tiles —
/// see [NexGlanceRail].
///
/// Pinned modules show two small local facts in the title's existing space,
/// and a ring round their mark when the module counts toward something.
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
                padding: const EdgeInsets.only(
                  top: NexSpacing.xs,
                  bottom: NexSpacing.sm,
                ),
                child: NexGlanceRail(
                  tiles: [
                    for (final tool in tools)
                      VaultOpenBuilder(
                        key: ValueKey('pinned-tool-${tool.id}'),
                        builder: (context, open) {
                          final facts = tool.id.startsWith('module.')
                              ? _facts[tool.id.substring('module.'.length)] ??
                                    NexPinnedSummary(l.pinModuleLoading)
                              : null;
                          return NexShelfTile(
                            compact: true,
                            title: tool.title,
                            subtitle: tool.subtitle,
                            icon: tool.icon,
                            hue: tool.hue,
                            progress: facts?.progress,
                            compactContent: facts == null
                                ? null
                                : _PinnedFacts(facts: facts),
                            badge: tool.locked
                                ? nexLockBadge(open: open)
                                : null,
                            onTap: () => unawaited(tool.push(context)),
                            onLongPress: () => unawaited(
                              nexToggleToolPin(
                                context,
                                widget.preferences,
                                tool,
                              ),
                            ),
                            longPressLabel: l.unpinFromHome,
                          );
                        },
                      ),
                  ],
                ),
              ),
      );
    },
  );
}

/// The pinned tools as one row across the home screen (2.8.0): each a small
/// live tile, the row scrolling sideways once there are more than fit.
///
/// They used to be a grid two to a row, which gave three modules two rows of
/// the first screen — and a whole row to whichever was the odd one out — on
/// a screen whose subject is the notes below. One or two tiles share the
/// width between them; from three on, two and the edge of the next show, so
/// the row says for itself that there is more to the side.
class NexGlanceRail extends StatelessWidget {
  const NexGlanceRail({super.key, required this.tiles});

  final List<Widget> tiles;

  /// The room between two tiles.
  static const _gap = NexSpacing.sm + NexSpacing.xs;

  /// As wide as a tile gets, so two tiles in a wide window stay tiles.
  static const _widest = 280.0;

  /// As narrow as a tile gets in a scrolling row, so its facts stay readable.
  static const _narrowest = 148.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final inner = constraints.maxWidth - NexSpacing.md * 2;
      final count = tiles.length;
      final width = count <= 2
          ? math.min(_widest, (inner - _gap * (count - 1)) / count)
          : ((inner - _gap * 2) / 2.3).clamp(_narrowest, _widest);
      return SingleChildScrollView(
        key: const ValueKey('glance-rail'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: NexSpacing.md),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, tile) in tiles.indexed) ...[
                if (i > 0) const SizedBox(width: _gap),
                SizedBox(width: math.max(0, width), child: tile),
              ],
            ],
          ),
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
          // With nothing under it the first fact has both rows: "Add your
          // first word" reads whole instead of being cut at the tile's edge.
          maxLines: facts.secondary == null ? 2 : 1,
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
