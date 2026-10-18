part of '../settings_sheet.dart';

/// The name, above the settings rather than among them.
///
/// It had a section of its own — a labelled card holding one field — which is
/// both more furniture than one text input needs and, being a section, put it
/// somewhere in the middle of the run. As a header it reads as whose settings
/// these are, which is what a name at the top of a settings screen means
/// everywhere else.
///
/// Stateful for the same reason the row it replaces was: the sheet does not
/// rebuild itself on a name change from the dialog it opens.
class _ProfileCard extends StatefulWidget {
  const _ProfileCard({required this.services, required this.preferences});

  final NexServices services;
  final NexPreferences preferences;

  @override
  State<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<_ProfileCard> {
  Future<void> _edit() async {
    await Navigator.push(
      context,
      NexPageRoute<void>(
        builder: (_) => ProfileScreen(
          services: widget.services,
          preferences: widget.preferences,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final name = widget.preferences.displayName;
    final photo = resolveProfilePhoto(
      widget.services.mediaDir,
      widget.preferences.profilePhotoPath,
    );
    final hasPhoto = photo != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: NexSpacing.lg),
      child: NexSurface(
        key: const ValueKey('settings-profile-surface'),
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(NexRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => unawaited(_edit()),
          child: Padding(
            padding: const EdgeInsets.all(NexSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.surfaceContainerHigh,
                  ),
                  foregroundDecoration: hasPhoto
                      ? BoxDecoration(
                          shape: BoxShape.circle,
                          image: DecorationImage(
                            image: FileImage(photo),
                            fit: BoxFit.cover,
                            // A picture just replaced: the old file is gone
                            // a frame before this card learns the new one.
                            onError: (_, _) {},
                          ),
                        )
                      : null,
                  child: name == null && !hasPhoto
                      // No name is not a blank circle: the placeholder says
                      // what tapping would do.
                      ? Icon(
                          Icons.person_outline,
                          color: theme.colorScheme.onSurfaceVariant,
                        )
                      : hasPhoto
                      ? null
                      : Text(
                          // `characters` rather than `[0]`: a Persian name's
                          // first letter, and any emoji, is more than one code
                          // unit, and slicing one in half renders as a box.
                          name!.characters.first.toUpperCase(),
                          style: theme.textTheme.titleLarge,
                        ),
                ),
                const SizedBox(width: NexSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name ?? l10n.yourName,
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.preferences.profileBio.trim().isEmpty
                            ? l10n.profileOpenHint
                            : widget.preferences.profileBio,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.edit_outlined,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks for the name the app greets you by, and stores it.
///
/// Returns whether anything was saved, so a caller that draws the name can
/// repaint. Shared rather than private to the profile card: onboarding asks
/// the same question, and asking it twice in two different dialogs is how the
/// two drift apart.
Future<bool> editDisplayName(
  BuildContext context,
  NexPreferences preferences,
) async {
  final l10n = AppLocalizations.of(context);
  final controller = TextEditingController(text: preferences.displayName ?? '');
  final saved = await nexShowDialog<String>(
    context: context,
    builder: (context) => NexAlertDialog(
      title: Text(l10n.yourName),
      content: NexDialogBody(
        child: NexAutoDirection(
          controller: controller,
          builder: (context, direction) => TextField(
            controller: controller,
            selectionWidthStyle: BoxWidthStyle.tight,
            contextMenuBuilder: nexReadingMenu,
            textDirection: direction,
            textAlign: TextAlign.start,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(hintText: l10n.yourNamePlaceholder),
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: Text(l10n.save),
        ),
      ],
    ),
  );
  controller.dispose();
  if (saved == null) return false;
  await preferences.setDisplayName(saved);
  return true;
}
