import 'dart:async';

import 'package:flutter/material.dart';
// NoteType arrives through nex_data, which re-exports nex_core — importing
// both is what `unnecessary_import` is for.
import 'package:nex_data/nex_data.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';

/// What the home-screen widget is allowed to show.
///
/// The widget started as "the top of the timeline", which is the right
/// default and the wrong answer for anyone whose timeline is mostly one kind
/// of thing. Somebody keeping a shopping list wants the checklists; somebody
/// filing receipts wants the photos under one tag; and the timeline they want
/// on their home screen is not always the timeline they scroll.
///
/// Two filters, because they compose into every request anyone has actually
/// made: a set of kinds, and one tag. Both empty is the default, and it is
/// the same list the app shows.
class WidgetSettingsScreen extends StatefulWidget {
  const WidgetSettingsScreen({
    super.key,
    required this.preferences,
    required this.services,
  });

  final NexPreferences preferences;
  final NexServices services;

  @override
  State<WidgetSettingsScreen> createState() => _WidgetSettingsScreenState();
}

class _WidgetSettingsScreenState extends State<WidgetSettingsScreen> {
  /// Null until the read comes back, which is not the same as "no tags" —
  /// the same distinction the tag manager draws, and for the same reason.
  List<TagUsage>? _tags;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final tags = await widget.services.tagUsage();
    if (!mounted) return;
    setState(() => _tags = tags);
  }

  /// One tag on or off, leaving the rest alone.
  ///
  /// No "all tags selected means no filter" rule here, unlike the kinds
  /// above: the kinds are a closed set this app defines, so selecting every
  /// one of them is genuinely the same as selecting none. Tags are the user's
  /// own and a new one appears whenever they make it — somebody who has
  /// deliberately ticked all four of their tags has said something different
  /// from "whatever I happen to have".
  Future<void> _toggleTag(Tag tag) async {
    final tags = Map<String, String>.from(widget.preferences.widgetTags);
    if (tags.remove(tag.id) == null) tags[tag.id] = tag.name;
    await widget.preferences.setWidgetTags(tags);
  }

  Future<void> _toggle(NoteType type) async {
    final types = widget.preferences.widgetTypes;
    final wire = type.wireName;
    final next = types.contains(wire)
        ? (types.toSet()..remove(wire))
        : (types.toSet()..add(wire));
    // Every kind selected is the same picture as none selected, and "none"
    // is the encoding that means "no filter" — so the last one being turned
    // on clears the filter rather than storing a list of everything, which
    // would silently stop including a note type added later.
    await widget.preferences.setWidgetTypes(
      next.length == NoteType.values.length ? const {} : next,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.widgetSettingsTitle)),
      body: AnimatedBuilder(
        animation: widget.preferences,
        builder: (context, _) {
          final types = widget.preferences.widgetTypes;
          final tags = widget.preferences.widgetTags;
          return ListView(
            padding: const EdgeInsets.all(NexSpacing.md),
            children: [
              Text(
                l10n.widgetSettingsIntro,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: NexSpacing.md),
              _Heading(l10n.widgetSettingsKinds),
              const SizedBox(height: NexSpacing.sm),
              Wrap(
                spacing: NexSpacing.sm,
                runSpacing: NexSpacing.sm,
                children: [
                  // "Everything" is a chip like the others rather than a
                  // switch above them: it is one of the answers to the same
                  // question, and it is the one most people want.
                  FilterChip(
                    label: Text(l10n.widgetSettingsEverything),
                    selected: types.isEmpty,
                    onSelected: (_) =>
                        unawaited(widget.preferences.setWidgetTypes(const {})),
                  ),
                  for (final type in NoteType.values)
                    FilterChip(
                      label: Text(l10n.noteType(type.wireName)),
                      selected: types.contains(type.wireName),
                      onSelected: (_) => unawaited(_toggle(type)),
                    ),
                ],
              ),
              const SizedBox(height: NexSpacing.lg),
              _Heading(l10n.widgetSettingsTag),
              const SizedBox(height: NexSpacing.sm),
              if (_tags == null)
                const Center(child: CircularProgressIndicator())
              else if (_tags!.isEmpty)
                Text(
                  l10n.widgetSettingsNoTags,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                Wrap(
                  spacing: NexSpacing.sm,
                  runSpacing: NexSpacing.sm,
                  children: [
                    FilterChip(
                      label: Text(l10n.widgetSettingsAnyTag),
                      selected: tags.isEmpty,
                      onSelected: (_) =>
                          unawaited(widget.preferences.setWidgetTags(const {})),
                    ),
                    for (final usage in _tags!)
                      FilterChip(
                        avatar: usage.tag.color == null
                            ? null
                            : CircleAvatar(
                                backgroundColor: nexParseTagColor(
                                  usage.tag.color,
                                ),
                                radius: 6,
                              ),
                        label: Text(usage.tag.name),
                        selected: tags.containsKey(usage.tag.id),
                        // Each chip is its own on and off, the way the kinds
                        // above already are: tapping a chosen tag drops it,
                        // and dropping the last one is the same as "Any".
                        onSelected: (_) => unawaited(_toggleTag(usage.tag)),
                      ),
                  ],
                ),
              const SizedBox(height: NexSpacing.lg),
              NexSwitchTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.push_pin_outlined),
                title: Text(l10n.widgetSettingsPinnedFirst),
                subtitle: Text(l10n.widgetSettingsPinnedFirstHint),
                value: widget.preferences.widgetPinnedFirst,
                onChanged: (value) => unawaited(
                  widget.preferences.setWidgetPinnedFirst(value),
                ),
              ),
              // Only under a lock that is actually on. With no lock there is
              // no state for this to describe, and a switch that cannot mean
              // anything still has to be read before it can be dismissed.
              if (widget.preferences.appLockEnabled) ...[
                const SizedBox(height: NexSpacing.lg),
                NexSwitchTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.lock_outline),
                  title: Text(l10n.widgetSettingsWhenLocked),
                  subtitle: Text(l10n.widgetSettingsWhenLockedHint),
                  value: widget.preferences.widgetShowWhenLocked,
                  onChanged: (value) => unawaited(
                    widget.preferences.setWidgetShowWhenLocked(value),
                  ),
                ),
              ],
              const SizedBox(height: NexSpacing.lg),
              Text(
                l10n.widgetSettingsScanNote,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.titleSmall);
}
