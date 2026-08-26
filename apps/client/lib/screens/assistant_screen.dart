import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../platform/nex_preferences.dart';
import '../widgets/assistant_settings.dart';

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
class AssistantScreen extends StatelessWidget {
  const AssistantScreen({super.key, required this.preferences});

  final NexPreferences preferences;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(AppLocalizations.of(context).assistant)),
    // The controls themselves live in AssistantSettingsBody, because the chat
    // opens the same ones in a panel of its own — where the thing you want to
    // change is usually the thing you just watched go wrong.
    body: AssistantSettingsBody(preferences: preferences),
  );
}
