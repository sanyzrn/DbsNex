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
/// belongs to the provider screen and is already there; and streaming,
/// because nothing here streams.
///
/// The fifth setting — the standing instruction — is a free-text prompt, and
/// the reason it is safe to offer is that it is not spliced in as a rule of
/// the app's own: [AiChatOptions.instruction] is quoted, labelled as the
/// user's preference, and placed above the lines that constrain what the
/// assistant may actually do. Tone is theirs to set; the scope and the action
/// protocol are not.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key, required this.preferences});

  final NexPreferences preferences;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  late final TextEditingController _instruction = TextEditingController(
    text: widget.preferences.aiInstruction,
  );

  @override
  void dispose() {
    _instruction.dispose();
    super.dispose();
  }

  /// Saved as it is typed rather than behind a Save button.
  ///
  /// Every other control on this screen commits on the tap that changes it,
  /// and a lone field that needed confirming would be the one setting people
  /// lose by backing out of the screen. The write is to shared preferences —
  /// cheap enough that a keystroke's worth of it is not worth debouncing.
  void _saveInstruction(String value) =>
      unawaited(widget.preferences.setAiInstruction(value));

  @override
  Widget build(BuildContext context) {
    final preferences = widget.preferences;
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
            Text(l10n.assistantInstruction, style: theme.textTheme.titleSmall),
            const SizedBox(height: NexSpacing.sm),
            TextField(
              controller: _instruction,
              onChanged: _saveInstruction,
              maxLength: NexPreferences.aiInstructionMaxLength,
              maxLines: 3,
              minLines: 1,
              textInputAction: TextInputAction.newline,
              // The instruction is written in whichever language the user
              // thinks in, which is not necessarily the interface's — so the
              // field follows the text rather than the app.
              textDirection: nexDirectionOf(_instruction.text),
              decoration: InputDecoration(
                hintText: l10n.assistantInstructionHint,
                border: const OutlineInputBorder(),
              ),
            ),
            Text(
              l10n.assistantInstructionSubtitle,
              style: theme.textTheme.bodySmall,
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
            // Shown only once a big size is actually chosen. A permanent
            // warning under a control most people leave at 20 is noise; the
            // same sentence at the moment it applies is information.
            if (NexPreferences.aiNotesContextIsSlow(
              preferences.aiNotesContextCount,
            )) ...[
              const SizedBox(height: NexSpacing.sm),
              Text(
                l10n.assistantContextSlow,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
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
