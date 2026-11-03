import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/nex_preferences.dart';
import '../widgets/nex_dialog.dart';
import '../widgets/nex_text_field.dart';
import '../widgets/settings_group.dart';

/// The existing manual introduction, behind its own opt-in. No learned state.
class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key, required this.preferences});
  final NexPreferences preferences;

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  late final _introduction = TextEditingController(
    text: widget.preferences.aiUserIntroduction,
  );
  bool _changing = false;

  @override
  void dispose() {
    _introduction.dispose();
    super.dispose();
  }

  Future<void> _setEnabled(bool value) async {
    final prefs = widget.preferences;
    if (_changing || !prefs.aiEnabled) return;
    _changing = true;
    try {
      if (value && !prefs.aiMemoryConsentSeen) {
        final l10n = AppLocalizations.of(context);
        final accepted = await nexShowDialog<bool>(
          context: context,
          builder: (ctx) => NexAlertDialog(
            title: Text(l10n.memoryTitle),
            content: NexDialogBody(
              child: SingleChildScrollView(child: Text(l10n.memoryConsentBody)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.memoryEnable),
              ),
            ],
          ),
        );
        if (!mounted || accepted != true || !prefs.aiEnabled) return;
        await prefs.setAiMemoryConsentSeen();
      }
      if (mounted && prefs.aiEnabled) await prefs.setAiMemoryEnabled(value);
    } finally {
      _changing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = widget.preferences;
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: NexAppBar(title: Text(l10n.memoryTitle)),
      body: AnimatedBuilder(
        animation: prefs,
        builder: (context, _) => ListView(
          padding: EdgeInsets.fromLTRB(
            NexSpacing.md,
            NexSpacing.md,
            NexSpacing.md,
            NexSpacing.lg + nexBottomInset(context),
          ),
          children: [
            NexSettingsGroup(
              title: l10n.memoryTitle,
              children: [
                NexSwitchTile(
                  key: const ValueKey('memory-enabled'),
                  title: Text(l10n.memoryTitle),
                  subtitle: Text(l10n.memorySwitchSubtitle),
                  value: prefs.aiMemoryEnabled,
                  onChanged: prefs.aiEnabled
                      ? (value) => unawaited(_setEnabled(value))
                      : null,
                ),
                if (prefs.aiMemoryEnabled)
                  NexSettingsField(
                    icon: Icons.person_search_outlined,
                    label: l10n.assistantAboutMe,
                    child: NexTextField(
                      key: const ValueKey('memory-introduction'),
                      controller: _introduction,
                      enabled: prefs.aiEnabled,
                      onChanged: (value) =>
                          unawaited(prefs.setAiUserIntroduction(value)),
                      maxLength: NexPreferences.aiUserIntroductionMaxLength,
                      maxLines: 4,
                      minLines: 2,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: l10n.assistantAboutMeHint,
                        filled: true,
                        fillColor: theme.colorScheme.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(NexRadius.md),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
