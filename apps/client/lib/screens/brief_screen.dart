import 'dart:async';
import 'dart:ui' show BoxWidthStyle;

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/ai_provider.dart';
import '../platform/nex_preferences.dart';
import '../widgets/choice_cards.dart';
import '../widgets/settings_group.dart';

/// What the card at the top of the timeline is for — asked rather than
/// assumed.
///
/// The brief had one shape and it was a good one, but it was the answer to a
/// question that has more than one answer. Somebody who wants to be told what
/// is overdue and nothing else, somebody who wants a suggestion about what to
/// do first, and somebody who wants nothing leaving their phone are three
/// different people, and the app only ever agreed with the first.
///
/// A pushed screen, like the assistant's and the provider's beside it
/// in the same section of Settings. It was a bottom sheet first, and that was
/// the mistake: a sheet among pushed pages closes differently, scrolls
/// differently and sits at a different height, so the one page in that group
/// that behaved unlike the rest was the newest one. It is built out of the
/// same [NexSettingsGroup] and [NexSettingsField] they are, which is what
/// makes it the same rather than similar.
class BriefScreen extends StatefulWidget {
  const BriefScreen({super.key, required this.preferences});

  final NexPreferences preferences;

  @override
  State<BriefScreen> createState() => _BriefScreenState();
}

class _BriefScreenState extends State<BriefScreen> {
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
    return Scaffold(
      appBar: AppBar(title: Text(l10n.briefTitle)),
      // Rebuilt from the preferences themselves rather than from `setState`
      // after each write, the same way the assistant's settings are: every
      // control here writes through `preferences`, which notifies, and a
      // screen that listens cannot show a stale answer to a choice somebody
      // just made.
      body: AnimatedBuilder(
        animation: widget.preferences,
        builder: (context, _) => _body(context, l10n),
      ),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final prefs = widget.preferences;
    final style = prefs.briefStyle;
    final hasModel = prefs.aiEnabled && aiTextAvailableWith(prefs.aiProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        NexSpacing.md,
        NexSpacing.md,
        NexSpacing.md,
        NexSpacing.lg,
      ),
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: NexSpacing.sm,
            bottom: NexSpacing.lg,
          ),
          child: Text(
            l10n.briefSubtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        // The five presets, outside a card rather than inside one. They are
        // the choice this screen exists for and they carry a sentence each;
        // stacked inside a grouped card with dividers between them they read
        // as a list of settings rather than as five answers to one question.
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: NexSpacing.sm,
            bottom: NexSpacing.sm,
          ),
          child: Text(
            l10n.briefStyleLabel,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.3,
            ),
          ),
        ),
        for (final entry in _styles(l10n))
          _StyleRow(
            icon: entry.icon,
            label: entry.label,
            about: entry.about,
            selected: style == entry.value,
            onTap: () => unawaited(prefs.setBriefStyle(entry.value)),
          ),
        // One line of consequence under the list, never two: what this choice
        // costs or saves, said where the choice is made rather than in a help
        // page nobody opens.
        if (!style.usesModel)
          _Note(text: l10n.briefOffline, icon: Icons.wifi_off_outlined)
        else if (!hasModel)
          _Note(text: l10n.briefNeedsAi, icon: Icons.info_outline, warn: true),
        const SizedBox(height: NexSpacing.lg),
        NexSettingsGroup(
          title: l10n.briefTitle,
          children: [
            if (style == NexBriefStyle.custom)
              NexSettingsField(
                icon: Icons.format_quote_outlined,
                label: l10n.briefInstructionLabel,
                child: NexAutoDirection(
                  controller: _instruction,
                  builder: (context, direction) => TextField(
                    controller: _instruction,
                    selectionWidthStyle: BoxWidthStyle.tight,
                    onChanged: _saveInstruction,
                    maxLength: NexPreferences.briefInstructionMaxLength,
                    maxLines: 3,
                    minLines: 1,
                    textDirection: direction,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: l10n.briefInstructionHint,
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(NexRadius.md),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
            // Tone is about prose, and the plain report has none: there is
            // nothing for it to colour that is not a fact. A control that
            // visibly does nothing is worse than a control that is absent.
            if (style.usesModel)
              NexSettingsField(
                icon: Icons.record_voice_over_outlined,
                label: l10n.briefToneLabel,
                child: NexChoiceCards<AiResponseStyle>(
                  selected: prefs.briefTone,
                  onSelected: (value) =>
                      unawaited(prefs.setBriefTone(value)),
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
                      preview: const NexScriptSample(
                        icon: Icons.gavel_outlined,
                      ),
                    ),
                  ],
                ),
              ),
            NexSettingsField(
              icon: Icons.notes_outlined,
              label: l10n.briefLengthLabel,
              child: NexChoiceCards<NexBriefLength>(
                selected: prefs.briefLength,
                onSelected: (value) => unawaited(prefs.setBriefLength(value)),
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
            ),
            // The language, here rather than in a row of its own three
            // sections up. It is the most visible thing about a brief and
            // that was the last place anybody looked for it — but it is not
            // the brief's own setting, which is what the note says.
            NexSettingsField(
              icon: Icons.g_translate_outlined,
              label: l10n.aiOutputLanguage,
              note: l10n.briefLanguageShared,
              child: NexChoiceCards<AiOutputLanguage>(
                selected: prefs.aiOutputLanguage,
                onSelected: (value) =>
                    unawaited(prefs.setAiOutputLanguage(value)),
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
            ),
          ],
        ),
      ],
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
            : scheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NexRadius.lg),
          side: BorderSide(
            color: selected ? scheme.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(NexSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: NexSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: theme.textTheme.bodyMedium),
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
                    child: Icon(
                      Icons.check_circle,
                      size: 20,
                      color: scheme.primary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
      padding: const EdgeInsets.symmetric(horizontal: NexSpacing.sm),
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
