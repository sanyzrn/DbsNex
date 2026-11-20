import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';

/// The language a snippet is written in, as the menu that chooses it.
///
/// One widget for both places it is asked — the capture box and the editor —
/// so the list, its order and its labels cannot drift apart. It is a value
/// menu, not an action menu: the design language leaves the icons off those,
/// the way it does a currency or a repeat.
class NexCodeLanguageButton extends StatelessWidget {
  const NexCodeLanguageButton({
    super.key,
    required this.language,
    required this.onSelected,
    this.rawLanguage,
    this.enabled = true,
  });

  final NexCodeLanguage language;

  /// The info string a fence already carried, when this build does not know
  /// it. Shown instead of a guess, and kept in the note until the person
  /// chooses one of the languages above.
  final String? rawLanguage;

  final ValueChanged<NexCodeLanguage> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = nexCodeLanguageLabel(
      context,
      language,
      rawLanguage: rawLanguage,
    );
    final child = Container(
      constraints: const BoxConstraints(minHeight: nexMinTapTarget),
      padding: const EdgeInsetsDirectional.only(
        start: NexSpacing.sm,
        end: NexSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(NexRadius.md),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.code,
            size: 18,
            color: enabled ? scheme.onSurfaceVariant : scheme.outline,
          ),
          const SizedBox(width: NexSpacing.xs),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                color: enabled ? scheme.onSurface : scheme.outline,
              ),
            ),
          ),
          Icon(
            Icons.arrow_drop_down,
            size: 20,
            color: enabled ? scheme.onSurfaceVariant : scheme.outline,
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      label: '${l10n.codeLanguage}: $label',
      excludeSemantics: true,
      child: NexPopupMenuButton<NexCodeLanguage>(
        enabled: enabled,
        initialValue: language,
        tooltip: l10n.codeLanguage,
        onSelected: onSelected,
        itemBuilder: (_) => [
          for (final item in NexCodeLanguage.selectable)
            nexMenuItem(
              value: item,
              label: nexCodeLanguageLabel(context, item),
            ),
        ],
        child: child,
      ),
    );
  }
}

/// What a language is called where a person reads it.
///
/// The names are proper nouns and stay close to their own spelling; only the
/// one that is a description — plain text — is fully translated. An unknown
/// fence keeps the string it arrived with.
String nexCodeLanguageLabel(
  BuildContext context,
  NexCodeLanguage language, {
  String? rawLanguage,
}) {
  final raw = rawLanguage?.trim() ?? '';
  if (raw.isNotEmpty) return raw;
  final l10n = AppLocalizations.of(context);
  return switch (language) {
    NexCodeLanguage.plainText => l10n.codeLanguagePlainText,
    NexCodeLanguage.dart => l10n.codeLanguageDart,
    NexCodeLanguage.javascript => l10n.codeLanguageJavaScript,
    NexCodeLanguage.python => l10n.codeLanguagePython,
    NexCodeLanguage.json => l10n.codeLanguageJson,
    NexCodeLanguage.html => l10n.codeLanguageHtml,
    NexCodeLanguage.css => l10n.codeLanguageCss,
    NexCodeLanguage.php => l10n.codeLanguagePhp,
  };
}
