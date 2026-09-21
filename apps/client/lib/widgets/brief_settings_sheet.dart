import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/ai_provider.dart';
import '../platform/nex_preferences.dart';
import 'choice_cards.dart';
import 'nex_dialog.dart';

/// What the card at the top of the timeline is for — asked rather than
/// assumed.
///
/// The brief had one shape and it was a good one, but it was the answer to a
/// question that has more than one answer. Somebody who wants to be told what
/// is overdue and nothing else, somebody who wants a suggestion about what to
/// do first, and somebody who wants nothing leaving their phone are three
/// different people, and until now the app only agreed with the first.
///
/// A sheet rather than a row inside the intelligence screen, and that is
/// deliberate: one of these five needs no provider at all, and burying it
/// behind a switch somebody has turned off is hiding the option from exactly
/// the person it was written for.
Future<void> showBriefSettings({
  required BuildContext context,
  required NexPreferences preferences,
}) => nexShowSheet<void>(
  context: context,
  builder: (_) => BriefSettingsSheet(preferences: preferences),
);

class BriefSettingsSheet extends StatefulWidget {
  const BriefSettingsSheet({super.key, required this.preferences});

  final NexPreferences preferences;

  @override
  State<BriefSettingsSheet> createState() => _BriefSettingsSheetState();
}

class _BriefSettingsSheetState extends State<BriefSettingsSheet> {
  late final TextEditingController _instruction = TextEditingController(
    text: widget.preferences.briefInstruction,
  );

  @override
  void dispose() {
    _instruction.dispose();
    super.dispose();
  }

  void _saveInstruction(String value) =>
      unawaited(widget.preferences.setBriefInstruction(value));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final prefs = widget.preferences;
    final style = prefs.briefStyle;
    final hasModel =
        prefs.aiEnabled && aiTextAvailableWith(prefs.aiProvider);

    return NexSheetBody(
      // Scrollable, which it was not. Five presets with a sentence each, two
      // rows of cards and a text field is taller than a phone, and a bottom
      // sheet gives its content the height it asks for without ever offering
      // to scroll it — so everything below the fold was simply off the
      // screen with no way to reach it.
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.briefTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: NexSpacing.xs),
            Text(
              l10n.briefSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: NexSpacing.lg),
            _Label(l10n.briefStyleLabel),
            for (final entry in _styles(l10n))
              _StyleRow(
                icon: entry.icon,
                label: entry.label,
                about: entry.about,
                selected: style == entry.value,
                onTap: () {
                  unawaited(prefs.setBriefStyle(entry.value));
                  setState(() {});
                },
              ),
            // One line of consequence under the list, never two: what this
            // choice costs or saves, said where the choice is made rather than
            // in a help page nobody opens.
            if (!style.usesModel)
              _Note(text: l10n.briefOffline, icon: Icons.wifi_off_outlined)
            else if (!hasModel)
              _Note(
                text: l10n.briefNeedsAi,
                icon: Icons.info_outline,
                warn: true,
              ),
            if (style == NexBriefStyle.custom) ...[
              const SizedBox(height: NexSpacing.lg),
              _Label(l10n.briefInstructionLabel),
              NexAutoDirection(
                controller: _instruction,
                builder: (context, direction) => TextField(
                  controller: _instruction,
                  onChanged: _saveInstruction,
                  maxLength: NexPreferences.briefInstructionMaxLength,
                  maxLines: 3,
                  minLines: 1,
                  textDirection: direction,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: l10n.briefInstructionHint,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            ],
            // Both dials are about prose, and the plain report has none: there
            // is nothing for a tone to colour and nothing for a length to
            // shorten that is not a fact. Showing them anyway would be two
            // controls that visibly do nothing.
            if (style.usesModel) ...[
              const SizedBox(height: NexSpacing.lg),
              _Label(l10n.briefToneLabel),
              NexChoiceCards<AiResponseStyle>(
                selected: prefs.briefTone,
                onSelected: (value) {
                  unawaited(prefs.setBriefTone(value));
                  setState(() {});
                },
                choices: [
                  NexChoice(
                    value: AiResponseStyle.natural,
                    label: l10n.assistantStyleNatural,
                    preview: const NexScriptSample(icon: Icons.waves),
                  ),
                  NexChoice(
                    value: AiResponseStyle.friendly,
                    label: l10n.assistantStyleFriendly,
                    preview: const NexScriptSample(
                      icon: Icons.sentiment_satisfied_alt,
                    ),
                  ),
                  NexChoice(
                    value: AiResponseStyle.formal,
                    label: l10n.assistantStyleFormal,
                    preview: const NexScriptSample(icon: Icons.work_outline),
                  ),
                  NexChoice(
                    value: AiResponseStyle.serious,
                    label: l10n.assistantStyleSerious,
                    preview: const NexScriptSample(icon: Icons.gavel_outlined),
                  ),
                ],
              ),
            ],
            // The language, here as well as in Intelligence. It is the single
            // most visible thing about a brief and the last place anyone would
            // look for it is three rows below the provider — but it is not the
            // brief's own setting, so it is shown rather than moved, and the
            // line under it says what else it governs.
            const SizedBox(height: NexSpacing.lg),
            _Label(l10n.aiOutputLanguage),
            NexChoiceCards<AiOutputLanguage>(
              selected: prefs.aiOutputLanguage,
              onSelected: (value) {
                unawaited(prefs.setAiOutputLanguage(value));
                setState(() {});
              },
              choices: [
                NexChoice(
                  value: AiOutputLanguage.auto,
                  label: l10n.aiOutputLanguageAuto,
                  preview: const NexScriptSample(icon: Icons.auto_awesome),
                ),
                NexChoice(
                  value: AiOutputLanguage.english,
                  label: l10n.aiOutputLanguageEnglish,
                  preview: const NexScriptSample(sample: 'Aa'),
                ),
                NexChoice(
                  value: AiOutputLanguage.persian,
                  label: l10n.aiOutputLanguagePersian,
                  preview: const NexScriptSample(sample: 'اَ'),
                ),
              ],
            ),
            _Note(text: l10n.briefLanguageShared, icon: Icons.link),
            const SizedBox(height: NexSpacing.lg),
            _Label(l10n.briefLengthLabel),
            NexChoiceCards<NexBriefLength>(
              selected: prefs.briefLength,
              onSelected: (value) {
                unawaited(prefs.setBriefLength(value));
                setState(() {});
              },
              choices: [
                NexChoice(
                  value: NexBriefLength.short,
                  label: l10n.assistantLengthBrief,
                  preview: const NexScriptSample(icon: Icons.short_text),
                ),
                NexChoice(
                  value: NexBriefLength.medium,
                  label: l10n.assistantLengthStandard,
                  preview: const NexScriptSample(icon: Icons.subject),
                ),
                NexChoice(
                  value: NexBriefLength.long,
                  label: l10n.assistantLengthFull,
                  preview: const NexScriptSample(icon: Icons.notes),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<_StyleEntry> _styles(AppLocalizations l10n) => [
    _StyleEntry(
      value: NexBriefStyle.assistant,
      icon: Icons.smart_toy_outlined,
      label: l10n.briefStyleAssistant,
      about: l10n.briefStyleAssistantAbout,
    ),
    _StyleEntry(
      value: NexBriefStyle.blended,
      icon: Icons.auto_awesome_outlined,
      label: l10n.briefStyleBlended,
      about: l10n.briefStyleBlendedAbout,
    ),
    _StyleEntry(
      value: NexBriefStyle.report,
      icon: Icons.checklist_outlined,
      label: l10n.briefStyleReport,
      about: l10n.briefStyleReportAbout,
    ),
    _StyleEntry(
      value: NexBriefStyle.planner,
      icon: Icons.flag_outlined,
      label: l10n.briefStylePlanner,
      about: l10n.briefStylePlannerAbout,
    ),
    _StyleEntry(
      value: NexBriefStyle.custom,
      icon: Icons.tune,
      label: l10n.briefStyleCustom,
      about: l10n.briefStyleCustomAbout,
    ),
  ];
}

class _StyleEntry {
  const _StyleEntry({
    required this.value,
    required this.icon,
    required this.label,
    required this.about,
  });

  final NexBriefStyle value;
  final IconData icon;
  final String label;
  final String about;
}

/// One preset, with the sentence that says what picking it does.
///
/// A row rather than one of the small cards the tone and length use, because
/// these five cannot be told apart by looking at them. "Planner" and
/// "Assistant" are both a model writing a line; what separates them is a
/// sentence, so the sentence is on the control.
class _StyleRow extends StatelessWidget {
  const _StyleRow({
    required this.icon,
    required this.label,
    required this.about,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String about;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: NexSpacing.sm),
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.10)
            : scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NexRadius.lg),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(NexSpacing.cardInset),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: NexSpacing.contentGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: theme.textTheme.titleSmall),
                      const SizedBox(height: NexSpacing.xs),
                      Text(
                        about,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: NexSpacing.sm,
                    ),
                    child: Icon(Icons.check_circle, color: scheme.primary),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: NexSpacing.sm),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note({required this.text, required this.icon, this.warn = false});

  final String text;
  final IconData icon;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = warn
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: NexSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: colour),
          const SizedBox(width: NexSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: colour),
            ),
          ),
        ],
      ),
    );
  }
}
