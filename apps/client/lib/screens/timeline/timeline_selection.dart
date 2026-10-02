part of '../timeline_screen.dart';

/// Picking several notes at once (W7.5).
///
/// It starts from a card's hold menu — Select, always the first line — and
/// from then on a tap on a card picks it or puts it back instead of opening
/// it. The dock along the bottom gives way to a bar of what can be done to
/// all of them together: tag, thread, pin, share, copy, delete. Putting the
/// last one back ends it, as does the bar's close button or Back.
///
/// Swiping a card does nothing meanwhile: a swipe acts on one note, and in
/// the middle of picking several that is the wrong note half the time.
extension _TimelineSelection on TimelineScreenState {
  bool get _selecting => _selected.isNotEmpty;

  /// The picked notes, in the order they were picked, less any that have
  /// gone from the timeline since.
  List<Note> get _selectedNotes => [
    for (final id in _selected)
      if (_model.byId(id) case final note?) note,
  ];

  void _toggleSelected(Note note) {
    if (widget.preferences.haptics) HapticFeedback.selectionClick();
    _swipe.closeAll();
    _rebuild(() {
      if (!_selected.remove(note.id)) _selected.add(note.id);
    });
  }

  void _endSelection() {
    if (!_selecting) return;
    _rebuild(_selected.clear);
  }

  Future<void> _tagSelected() async {
    final notes = _selectedNotes;
    if (notes.isEmpty) return;
    final all = await widget.services.listTags();
    if (!mounted) return;
    final onAll = {
      for (final tag in notes.first.tags)
        if (notes.every((n) => n.tags.any((t) => t.id == tag.id))) tag.id,
    };
    final choice = await TagPickerSheet.show(
      context,
      tags: all,
      alreadyOn: onAll,
    );
    if (choice == null || !mounted) return;
    if (widget.preferences.haptics) HapticFeedback.lightImpact();
    for (final note in notes) {
      await widget.services.addTag(
        noteId: note.id,
        name: choice.tag?.name ?? choice.name!,
        color: choice.color,
      );
    }
    await widget.services.refreshTimeline();
    await _model.loadFilterTags();
    if (!mounted) return;
    nexShowBanner(
      context,
      message: AppLocalizations.of(context).selectionTagged(notes.length),
    );
  }

  Future<void> _threadSelected() async {
    final notes = _selectedNotes;
    if (notes.isEmpty) return;
    await showThreadPickerFor(
      context,
      services: widget.services,
      noteIds: [for (final note in notes) note.id],
    );
  }

  /// Pins them all, or — when every one is already pinned — unpins them
  /// all: the same toggle a single card's Pin is.
  Future<void> _pinSelected() async {
    final l10n = AppLocalizations.of(context);
    final notes = _selectedNotes;
    if (notes.isEmpty) return;
    final unpin = notes.every((note) => note.pinnedAt != null);
    var changed = 0;
    var limit = false;
    for (final note in notes) {
      if (unpin) {
        await widget.services.unpinNote(note.id);
        changed++;
      } else if (note.pinnedAt == null) {
        if (!await widget.services.pinNote(note.id)) {
          limit = true;
          break;
        }
        changed++;
      }
    }
    await widget.services.refreshTimeline();
    if (!mounted) return;
    _endSelection();
    nexShowBanner(
      context,
      message: limit
          ? l10n.pinLimitReached
          : unpin
          ? l10n.selectionUnpinned(changed)
          : l10n.selectionPinned(changed),
    );
  }

  Future<void> _shareSelected() async {
    final notes = _selectedNotes;
    if (notes.isEmpty) return;
    if (!await nexShareNotes(notes)) {
      if (mounted) {
        nexShowBanner(
          context,
          message: AppLocalizations.of(context).nothingToCopy,
        );
      }
      return;
    }
    if (mounted) _endSelection();
  }

  Future<void> _copySelected() async {
    final l10n = AppLocalizations.of(context);
    final notes = _selectedNotes;
    final words = [
      for (final note in notes)
        if (await nexCopyTextOf(note) case final text?) text,
    ];
    if (!mounted) return;
    if (words.isEmpty) {
      nexShowBanner(context, message: l10n.nothingToCopy);
      return;
    }
    await Clipboard.setData(ClipboardData(text: words.join('\n\n')));
    if (!mounted) return;
    _endSelection();
    nexShowBanner(context, message: l10n.selectionCopied(words.length));
  }

  /// Deletes them all at once, with one Undo that brings them all back.
  Future<void> _deleteSelected() async {
    final l10n = AppLocalizations.of(context);
    final notes = _selectedNotes;
    if (notes.isEmpty) return;
    if (widget.preferences.haptics) HapticFeedback.mediumImpact();
    for (final note in notes) {
      await widget.services.deleteNote(note.id);
    }
    await widget.services.refreshTimeline();
    if (!mounted) return;
    _endSelection();
    nexShowBanner(
      context,
      message: notes.length == 1
          ? l10n.noteDeleted
          : l10n.groupDeleted(notes.length),
      haptics: widget.preferences.haptics,
      actionLabel: l10n.undo,
      onAction: () async {
        _tick();
        for (final note in notes) {
          await widget.services.undelete(note.id);
        }
        await widget.services.refreshTimeline();
      },
    );
  }

  /// What takes the dock's place while notes are picked: how many, and
  /// what can be done to them.
  Widget _selectionBar(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final viewport = MediaQuery.sizeOf(context).width;
    // Seven 48dp targets need 352dp with the end caps; a 360dp phone's
    // margins left 328 and the last button hung past the capsule (UX-02).
    // As on the navigation dock, the outer margin gives way before any
    // target does, and only a phone narrower still scrolls the row.
    final actions = nexCanShare ? 7 : 6;
    final needed = actions * nexMinTapTarget + NexSpacing.sm * 2;
    final width = math.min(
      math.max((viewport - NexSpacing.md * 2).clamp(0.0, 420.0), needed),
      viewport - NexSpacing.xs * 2,
    );
    final fits = width >= needed;
    const height = NexNavigationDock.height;
    final radius = BorderRadius.circular(height / 2);
    Widget action(
      IconData icon,
      String tooltip,
      Future<void> Function() run, {
      Color? color,
    }) => IconButton(
      tooltip: tooltip,
      color: color,
      onPressed: () => unawaited(run()),
      icon: Icon(icon),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          key: const ValueKey('selection-count'),
          padding: const EdgeInsets.symmetric(
            horizontal: NexSpacing.md,
            vertical: NexSpacing.xs + 2,
          ),
          margin: const EdgeInsets.only(bottom: NexSpacing.sm),
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(NexRadius.pill),
          ),
          child: Text(
            nexDigits(
              l10n.selectionCount(_selected.length),
              persian: Localizations.localeOf(context).languageCode == 'fa',
            ),
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.onPrimary,
            ),
          ),
        ),
        SizedBox(
          key: const ValueKey('selection-bar'),
          width: width,
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: context.nexVisualStyle.liquidGlass
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.10),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
            ),
            child: NexGlassSurface(
              borderRadius: radius,
              fallbackColor: scheme.surfaceContainerLowest,
              child: Material(
                type: MaterialType.transparency,
                child: _SelectionRow(
                  fits: fits,
                  children: [
                    action(
                      Icons.close,
                      l10n.selectionClose,
                      () async => _endSelection(),
                    ),
                    action(Icons.label_outline, l10n.addTag, _tagSelected),
                    action(
                      Icons.timeline_outlined,
                      l10n.threads,
                      _threadSelected,
                    ),
                    action(
                      _selectedNotes.every((n) => n.pinnedAt != null)
                          ? Icons.push_pin
                          : Icons.push_pin_outlined,
                      _selectedNotes.every((n) => n.pinnedAt != null)
                          ? l10n.unpin
                          : l10n.pin,
                      _pinSelected,
                    ),
                    if (nexCanShare)
                      action(Icons.ios_share, l10n.share, _shareSelected),
                    action(Icons.copy_outlined, l10n.copy, _copySelected),
                    action(
                      Icons.delete_outline,
                      l10n.delete,
                      _deleteSelected,
                      color: scheme.error,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The selection bar's buttons: spread evenly when they fit, scrolled
/// sideways on a phone too narrow for all of them.
class _SelectionRow extends StatelessWidget {
  const _SelectionRow({required this.fits, required this.children});

  final bool fits;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (fits) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: children,
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: NexSpacing.sm),
      child: Row(children: children),
    );
  }
}
