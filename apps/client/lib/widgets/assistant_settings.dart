import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/ai_provider.dart';
import '../platform/nex_preferences.dart';
import 'choice_cards.dart';

/// How the assistant behaves, wherever it is being tuned from.
///
/// It was one flat column: five section titles, three rows of choice cards, a
/// text field and a switch, all at the same level with nothing to say which
/// went with which. Read top to bottom it was a list of controls rather than
/// an answer to any question a person actually has, and the two questions
/// people do have — "how does it talk" and "what can it see" — had their
/// answers interleaved.
///
/// So: three groups, in the cards Settings already uses, in that order. Voice
/// first because it is the one people change; reach second because it is the
/// one with a privacy consequence; the standing instruction last because it
/// is the only one that takes typing.
///
/// A body rather than a screen, because it is now opened from two places: the
/// Settings row it has always had, and the chat itself — where the thing you
/// want to change is usually the thing you just watched go wrong.
class AssistantSettingsBody extends StatefulWidget {
  const AssistantSettingsBody({
    super.key,
    required this.preferences,
    this.controller,
    this.padding = const EdgeInsets.fromLTRB(
      NexSpacing.md,
      NexSpacing.md,
      NexSpacing.md,
      NexSpacing.lg,
    ),
    this.shrinkWrap = false,
  });

  final NexPreferences preferences;

  /// The enclosing sheet's scrollable, when there is one — a sheet only
  /// resizes to a drag if the list inside it is the one it handed down.
  final ScrollController? controller;

  final EdgeInsets padding;
  final bool shrinkWrap;

  @override
  State<AssistantSettingsBody> createState() => _AssistantSettingsBodyState();
}

class _AssistantSettingsBodyState extends State<AssistantSettingsBody> {
  late final TextEditingController _name = TextEditingController(
    text: widget.preferences.aiUserName,
  );
  late final TextEditingController _introduction = TextEditingController(
    text: widget.preferences.aiUserIntroduction,
  );
  late final TextEditingController _instruction = TextEditingController(
    text: widget.preferences.aiInstruction,
  );

  @override
  void dispose() {
    _name.dispose();
    _introduction.dispose();
    _instruction.dispose();
    super.dispose();
  }

  /// Saved as it is typed rather than behind a Save button.
  ///
  /// Every other control here commits on the tap that changes it, and a lone
  /// field that needed confirming would be the one setting people lose by
  /// backing out. The write is to shared preferences — cheap enough that a
  /// keystroke's worth of it is not worth debouncing.
  void _saveInstruction(String value) =>
      unawaited(widget.preferences.setAiInstruction(value));

  void _saveName(String value) =>
      unawaited(widget.preferences.setAiUserName(value));

  void _saveIntroduction(String value) =>
      unawaited(widget.preferences.setAiUserIntroduction(value));

  @override
  Widget build(BuildContext context) {
    final preferences = widget.preferences;
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: preferences,
      builder: (context, _) => ListView(
        controller: widget.controller,
        shrinkWrap: widget.shrinkWrap,
        padding: widget.padding,
        children: [
          _Group(
            title: l10n.assistantAboutYouGroup,
            children: [
              _Field(
                icon: Icons.badge_outlined,
                label: l10n.assistantCallMe,
                child: NexAutoDirection(
                  controller: _name,
                  builder: (context, direction) => TextField(
                    controller: _name,
                    onChanged: _saveName,
                    maxLength: NexPreferences.aiUserNameMaxLength,
                    textDirection: direction,
                    textCapitalization: TextCapitalization.words,
                    decoration: _inputDecoration(
                      theme,
                      l10n.assistantCallMeHint,
                    ),
                  ),
                ),
              ),
              _Field(
                icon: Icons.person_search_outlined,
                label: l10n.assistantAboutMe,
                child: NexAutoDirection(
                  controller: _introduction,
                  builder: (context, direction) => TextField(
                    controller: _introduction,
                    onChanged: _saveIntroduction,
                    maxLength: NexPreferences.aiUserIntroductionMaxLength,
                    maxLines: 4,
                    minLines: 2,
                    textDirection: direction,
                    textInputAction: TextInputAction.newline,
                    decoration: _inputDecoration(
                      theme,
                      l10n.assistantAboutMeHint,
                    ),
                  ),
                ),
              ),
            ],
          ),
          _Group(
            title: l10n.assistantVoiceGroup,
            children: [
              _Field(
                icon: Icons.record_voice_over_outlined,
                label: l10n.assistantResponseStyle,
                child: NexChoiceCards<AiResponseStyle>(
                  selected: preferences.aiResponseStyle,
                  onSelected: (value) =>
                      unawaited(preferences.setAiResponseStyle(value)),
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
                    NexChoice(
                      value: AiResponseStyle.romantic,
                      label: l10n.assistantStyleRomantic,
                      preview: const NexScriptSample(
                        icon: Icons.favorite_outline,
                      ),
                    ),
                    NexChoice(
                      value: AiResponseStyle.custom,
                      label: l10n.assistantStyleCustom,
                      preview: const NexScriptSample(
                        icon: Icons.edit_outlined,
                      ),
                    ),
                  ],
                ),
              ),
              // The instruction, and only under Custom. These were two
              // sections — five preset tones, and a free-text note about tone
              // — which is two controls for one thing: pick "Formal", write
              // "be witty and sarcastic", and nothing says which one the
              // assistant should follow. Custom is simply the sixth preset,
              // the one you write yourself.
              if (preferences.aiResponseStyle == AiResponseStyle.custom)
                _Field(
                  icon: Icons.format_quote_outlined,
                  label: l10n.assistantInstructionSubtitle,
                  child: NexAutoDirection(
                    controller: _instruction,
                    builder: (context, direction) => TextField(
                      controller: _instruction,
                      onChanged: _saveInstruction,
                      maxLength: NexPreferences.aiInstructionMaxLength,
                      maxLines: 3,
                      minLines: 1,
                      textInputAction: TextInputAction.newline,
                      // Written in whichever language the user thinks in,
                      // which is not necessarily the interface's — so the
                      // field follows the text rather than the app.
                      textDirection: direction,
                      decoration: _inputDecoration(
                        theme,
                        l10n.assistantInstructionHint,
                      ),
                    ),
                  ),
                ),
              _Field(
                icon: Icons.tune,
                label: l10n.assistantCreativity,
                child: NexChoiceCards<AiCreativity>(
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
              ),
              _Field(
                icon: Icons.notes_outlined,
                label: l10n.assistantLength,
                child: NexChoiceCards<AiAnswerLength>(
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
              ),
            ],
          ),
          _Group(
            title: l10n.assistantReachGroup,
            children: [
              _Field(
                icon: Icons.layers_outlined,
                label: l10n.assistantContext,
                // Shown only once a big size is actually chosen. A permanent
                // warning under a control most people leave at 20 is noise;
                // the same sentence at the moment it applies is information.
                note:
                    NexPreferences.aiNotesContextIsSlow(
                      preferences.aiNotesContextCount,
                    )
                    ? l10n.assistantContextSlow
                    : null,
                child: NexChoiceCards<int>(
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
              ),
              NexSwitchTile(
                secondary: const Icon(Icons.fence_outlined),
                value: preferences.aiNotesOnly,
                onChanged: (value) =>
                    unawaited(preferences.setAiNotesOnly(value)),
                title: Text(l10n.assistantScope),
                subtitle: Text(l10n.assistantScopeSubtitle),
              ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(ThemeData theme, String hint) =>
      InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: theme.colorScheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NexRadius.md),
          borderSide: BorderSide.none,
        ),
      );
}

/// One labelled card, the same shape Settings uses for its groups.
class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: NexSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: NexSpacing.sm,
              bottom: NexSpacing.sm,
            ),
            child: Text(
              title,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.3,
              ),
            ),
          ),
          Material(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(NexRadius.lg),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: NexSpacing.md,
                      endIndent: NexSpacing.md,
                      color: theme.colorScheme.outlineVariant,
                    ),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled control inside a card: icon and name on one line, the control
/// itself under them at full width.
///
/// The choice cards need the whole width to stay readable, so this is not a
/// `ListTile` with a trailing widget — the label row is the ListTile's look
/// without its layout.
class _Field extends StatelessWidget {
  const _Field({
    required this.icon,
    required this.label,
    required this.child,
    this.note,
  });

  final IconData icon;
  final String label;
  final Widget child;

  /// A line under the control that only appears when it has something to say.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NexSpacing.md,
        NexSpacing.md,
        NexSpacing.md,
        NexSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: NexSpacing.sm),
              Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            ],
          ),
          const SizedBox(height: NexSpacing.sm),
          child,
          if (note case final text?) ...[
            const SizedBox(height: NexSpacing.sm),
            Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
