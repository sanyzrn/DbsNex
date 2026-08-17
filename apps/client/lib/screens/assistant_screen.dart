import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/ai_provider.dart';
import '../platform/nex_preferences.dart';
import '../widgets/choice_cards.dart';

/// How the assistant behaves, as opposed to which provider answers it.
///
/// Replaces the on-device chat screen that used to live behind this row. That
/// screen talked to `ChatAdapterBinding`, which only the `ai` flavour's entry
/// point binds — so on every build that ships, it answered "unavailable" to
/// everything. There is one chat in the app now, reached by holding the
/// capture button, and this is where it is tuned.
///
/// Four settings, chosen from what the assistant surfaces in ChatGPT, Claude
/// and Gemini actually expose to people rather than to developers. What is
/// deliberately not here: top-p and penalties, which no user can predict the
/// effect of and which interact badly with temperature; a model picker, which
/// belongs to the provider screen and is already there; streaming, because
/// nothing here streams; and a free-text system prompt, which is a good idea
/// held back for its own release rather than smuggled in as a text field.
class AssistantScreen extends StatelessWidget {
  const AssistantScreen({super.key, required this.preferences});

  final NexPreferences preferences;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: preferences,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(l10n.assistant)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(
            NexSpacing.lg,
            NexSpacing.md,
            NexSpacing.lg,
            NexSpacing.lg,
          ),
          children: [
            Text(l10n.assistantCreativity, style: theme.textTheme.titleSmall),
            const SizedBox(height: NexSpacing.sm),
            NexChoiceCards<AiCreativity>(
              selected: preferences.aiCreativity,
              onSelected: (value) =>
                  unawaited(preferences.setAiCreativity(value)),
              choices: [
                NexChoice(
                  value: AiCreativity.precise,
                  label: l10n.assistantCreativityPrecise,
                  preview: const NexScriptSample(icon: Icons.straighten),
                ),
                NexChoice(
                  value: AiCreativity.balanced,
                  label: l10n.assistantCreativityBalanced,
                  preview: const NexScriptSample(icon: Icons.balance),
                ),
                NexChoice(
                  value: AiCreativity.inventive,
                  label: l10n.assistantCreativityInventive,
                  preview: const NexScriptSample(icon: Icons.auto_awesome),
                ),
              ],
            ),
            const SizedBox(height: NexSpacing.lg),
            Text(l10n.assistantLength, style: theme.textTheme.titleSmall),
            const SizedBox(height: NexSpacing.sm),
            NexChoiceCards<AiAnswerLength>(
              selected: preferences.aiAnswerLength,
              onSelected: (value) =>
                  unawaited(preferences.setAiAnswerLength(value)),
              choices: [
                NexChoice(
                  value: AiAnswerLength.brief,
                  label: l10n.assistantLengthBrief,
                  preview: const NexScriptSample(icon: Icons.short_text),
                ),
                NexChoice(
                  value: AiAnswerLength.standard,
                  label: l10n.assistantLengthStandard,
                  preview: const NexScriptSample(icon: Icons.subject),
                ),
                NexChoice(
                  value: AiAnswerLength.full,
                  label: l10n.assistantLengthFull,
                  preview: const NexScriptSample(icon: Icons.notes),
                ),
              ],
            ),
            const SizedBox(height: NexSpacing.lg),
            Text(l10n.assistantContext, style: theme.textTheme.titleSmall),
            const SizedBox(height: NexSpacing.sm),
            NexChoiceCards<int>(
              selected: preferences.aiNotesContextCount,
              onSelected: (value) =>
                  unawaited(preferences.setAiNotesContextCount(value)),
              choices: [
                for (final count in NexPreferences.aiNotesContextChoices)
                  NexChoice(
                    value: count,
                    label: count == 0
                        ? l10n.assistantContextNone
                        : l10n.assistantContextCount(count),
                    preview: NexScriptSample(
                      sample: count == 0 ? '—' : '$count',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: NexSpacing.md),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: preferences.aiNotesOnly,
              onChanged: (value) =>
                  unawaited(preferences.setAiNotesOnly(value)),
              title: Text(l10n.assistantScope),
              subtitle: Text(l10n.assistantScopeSubtitle),
            ),
          ],
        ),
      ),
    );
  }
}
