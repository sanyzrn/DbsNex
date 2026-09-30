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
      child: Material(
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

/// Sync, and whether it is set up at all.
///
/// It used to be a bare "Sync now" button that reported "the operation failed"
/// on every tap, because there is no default server and nowhere in the app to
/// name one. Sync is optional, so the honest row says that, and offers the
/// field that makes it work rather than hiding the reason.
class _SyncRow extends StatefulWidget {
  const _SyncRow({required this.services, required this.preferences});

  final NexServices services;
  final NexPreferences preferences;

  @override
  State<_SyncRow> createState() => _SyncRowState();
}

class _SyncRowState extends State<_SyncRow> {
  bool _busy = false;

  Future<void> _configure() async {
    final l10n = AppLocalizations.of(context);
    final url = TextEditingController(
      text: widget.preferences.syncBaseUrl ?? '',
    );
    final token = TextEditingController(
      text: widget.preferences.syncBearerToken ?? '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.syncServer),
        content: NexDialogBody(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: url,
                selectionWidthStyle: BoxWidthStyle.tight,
                contextMenuBuilder: nexReadingMenu,
                autofocus: true,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: l10n.syncServer,
                  hintText: l10n.syncServerHint,
                ),
              ),
              const SizedBox(height: NexSpacing.md),
              TextField(
                controller: token,
                selectionWidthStyle: BoxWidthStyle.tight,
                contextMenuBuilder: nexReadingMenu,
                autocorrect: false,
                decoration: InputDecoration(labelText: l10n.syncToken),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.preferences.setSyncBaseUrl(url.text.trim());
      await widget.preferences.setSyncBearerToken(token.text.trim());
      if (mounted) setState(() {});
    }
    url.dispose();
    token.dispose();
  }

  Future<void> _syncNow() async {
    final l10n = AppLocalizations.of(context);
    final banner = NexBannerHost.of(context);
    setState(() => _busy = true);
    try {
      final result = await widget.services.syncNow();
      banner?.show(
        message: '${l10n.syncComplete} · ${result.pushed}↑ ${result.pulled}↓',
      );
    } catch (error) {
      // Named, and with the reason. One sentence that says neither which
      // operation failed nor why leaves someone staring at a banner they
      // cannot act on — and this one is transient, so by the time they wonder
      // it is gone. The full text is in the diagnostics file either way.
      banner?.show(
        message: '${l10n.syncFailed} (${NexServices.describeFailure(error)})',
        kind: NexBannerKind.failed,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final server = widget.preferences.syncBaseUrl;
    return _Row(
      icon: Icons.sync,
      title: l10n.sync,
      value: server ?? l10n.syncNotConfigured,
      onTap: _configure,
      trailing: server == null
          ? null
          : TextButton(
              onPressed: _busy ? null : () => unawaited(_syncNow()),
              child: Text(l10n.syncNow),
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
  final saved = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
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
