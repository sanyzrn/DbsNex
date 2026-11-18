import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../platform/nex_preferences.dart';
import 'nex_tips.dart';
import 'tip_schedule.dart';

/// The home screen's tip, when the schedule has one (2.8.4): one small card
/// above the notes, in the tip's own colour, with a button when the tip
/// leads somewhere and a close. Nothing at all the rest of the time.
///
/// The catalogue is [nexTips]; when one appears is [NexTipSchedule].
class NexHomeTip extends StatefulWidget {
  const NexHomeTip({
    super.key,
    required this.preferences,
    required this.notes,
    required this.onOpen,
    this.hidden = false,
    this.tips,
    this.clock,
  });

  final NexPreferences preferences;

  /// The home screen's notes, for the tips that only fit some libraries.
  final List<Note> notes;

  /// Takes the person where a tip's button points.
  final void Function(NexTipTarget target) onOpen;

  /// While a search is running: tips are about the home screen.
  final bool hidden;

  /// For tests: another catalogue, another clock.
  final List<NexTip>? tips;
  final DateTime Function()? clock;

  @override
  State<NexHomeTip> createState() => _NexHomeTipState();
}

class _NexHomeTipState extends State<NexHomeTip> {
  NexTip? _tip;
  late NexTipState _state = NexTipState.parse(widget.preferences.tipState);

  DateTime get _now => widget.clock?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    widget.preferences.addListener(_evaluate);
    _evaluate(rebuild: false);
  }

  @override
  void didUpdateWidget(NexHomeTip oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Already building: the new answer is simply what this build shows.
    if (!identical(oldWidget.notes, widget.notes)) _evaluate(rebuild: false);
  }

  @override
  void dispose() {
    widget.preferences.removeListener(_evaluate);
    super.dispose();
  }

  void _evaluate({bool rebuild = true}) {
    final NexTip? tip;
    if (!widget.preferences.showTips) {
      tip = null;
    } else {
      final (picked, state) = NexTipSchedule.pick(
        tips: widget.tips ?? nexTips,
        state: _state,
        context: NexTipContext(
          notes: widget.notes,
          preferences: widget.preferences,
        ),
        now: _now,
      );
      tip = picked;
      _save(state);
    }
    if (tip?.id == _tip?.id) return;
    if (rebuild && mounted) {
      setState(() => _tip = tip);
    } else {
      _tip = tip;
    }
  }

  void _save(NexTipState state) {
    final json = state.toJson();
    _state = state;
    if (json != widget.preferences.tipState) {
      unawaited(widget.preferences.setTipState(json));
    }
  }

  void _close({bool acted = false}) {
    final tip = _tip;
    if (tip == null) return;
    _save(
      NexTipSchedule.closed(
        _state,
        now: _now,
        notes: widget.notes.length,
        acted: acted,
      ),
    );
    setState(() => _tip = null);
    if (acted) {
      if (tip.target case final target?) widget.onOpen(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tip = widget.hidden ? null : _tip;
    return AnimatedSize(
      duration: NexMotion.of(context, NexMotion.standard),
      curve: NexMotion.curve,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: NexMotion.of(context, NexMotion.standard),
        child: tip == null
            ? const SizedBox(width: double.infinity)
            : _TipCard(
                key: ValueKey('home-tip-${tip.id}'),
                tip: tip,
                // Someone who keeps closing them is offered a way out.
                offerOff: _state.ignored >= 2,
                onClose: () => _close(),
                onAction: tip.target == null ? null : () => _close(acted: true),
                onTurnOff: () {
                  _close();
                  unawaited(widget.preferences.setShowTips(false));
                },
              ),
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard({
    super.key,
    required this.tip,
    required this.offerOff,
    required this.onClose,
    required this.onAction,
    required this.onTurnOff,
  });

  final NexTip tip;
  final bool offerOff;
  final VoidCallback onClose;
  final VoidCallback? onAction;
  final VoidCallback onTurnOff;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final color = tip.hue.of(theme.brightness);
    final action = tip.action;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NexSpacing.md,
        NexSpacing.xs,
        NexSpacing.md,
        NexSpacing.sm,
      ),
      child: Semantics(
        container: true,
        label: l10n.tipLabel,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(NexRadius.lg),
            border: Border.all(color: color.withValues(alpha: 0.28)),
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              NexSpacing.md,
              NexSpacing.sm,
              NexSpacing.xs,
              NexSpacing.sm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: NexSpacing.xs),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(NexRadius.md),
                    ),
                    child: Icon(tip.icon, size: 20, color: color),
                  ),
                ),
                const SizedBox(width: NexSpacing.md),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: NexSpacing.xs),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tip.title(l10n),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          tip.body(l10n),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.45,
                          ),
                        ),
                        if (onAction != null || offerOff)
                          Wrap(
                            spacing: NexSpacing.xs,
                            children: [
                              if (action != null && onAction != null)
                                TextButton(
                                  key: const ValueKey('home-tip-action'),
                                  onPressed: onAction,
                                  style: TextButton.styleFrom(
                                    foregroundColor: color,
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(0, 40),
                                  ),
                                  child: Text(action(l10n)),
                                ),
                              if (offerOff)
                                TextButton(
                                  key: const ValueKey('home-tip-off'),
                                  onPressed: onTurnOff,
                                  style: TextButton.styleFrom(
                                    foregroundColor: scheme.onSurfaceVariant,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: NexSpacing.sm,
                                    ),
                                    minimumSize: const Size(0, 40),
                                  ),
                                  child: Text(l10n.tipTurnOff),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('home-tip-close'),
                  tooltip: l10n.tipClose,
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, size: 20),
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
