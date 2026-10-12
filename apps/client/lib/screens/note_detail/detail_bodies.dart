part of '../note_detail_sheet.dart';

/// A checklist, where ticking is the point.
///
/// Rows in their stored order here, unlike the card, which floats what is
/// still to do to the top: on the card you want the next thing, in the sheet
/// you want the list you wrote.
/// A checklist's lines, ticked with a touch.
///
/// The touch that ticks the last open line is marked: the list glows once in
/// the accent and settles, and the progress line says it is all done. Only
/// on that touch — not when a finished list is opened, nor while ticking
/// lines back and forth.
class _ChecklistBody extends StatefulWidget {
  const _ChecklistBody({required this.items, required this.onToggle});

  final List<ChecklistItem> items;
  final ValueChanged<int> onToggle;

  @override
  State<_ChecklistBody> createState() => _ChecklistBodyState();
}

class _ChecklistBodyState extends State<_ChecklistBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: NexMotion.receipt,
  );

  static bool _finished(List<ChecklistItem> items) =>
      items.isNotEmpty && items.every((item) => item.done);

  @override
  void didUpdateWidget(_ChecklistBody old) {
    super.didUpdateWidget(old);
    // Same list, one more tick, and now nothing left open.
    if (old.items.length == widget.items.length &&
        !_finished(old.items) &&
        _finished(widget.items)) {
      _glow.duration = NexMotion.of(context, NexMotion.receipt);
      unawaited(_glow.forward(from: 0));
    }
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AnimatedBuilder(
      animation: _glow,
      builder: (context, child) {
        // Up quickly, down slowly: a breath, not a flash.
        final t = _glow.value;
        final strength = t < 0.3
            ? Curves.easeOut.transform(t / 0.3)
            : 1 - Curves.easeInOut.transform((t - 0.3) / 0.7);
        if (strength <= 0) return child!;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.10 * strength),
            borderRadius: BorderRadius.circular(NexRadius.md),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.22 * strength),
                blurRadius: 18 * strength,
              ),
            ],
          ),
          child: child,
        );
      },
      child: _lines(context),
    );
  }

  Widget _lines(BuildContext context) {
    final items = widget.items;
    final onToggle = widget.onToggle;
    final theme = Theme.of(context);
    final progress = checklistProgress(items);
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (progress.total > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: NexSpacing.sm),
            child: Text(
              progress.done == progress.total
                  ? '${l10n.checklistAllDone} · '
                        '${l10n.checklistProgress(progress.done, progress.total)}'
                  : l10n.checklistProgress(progress.done, progress.total),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (var i = 0; i < items.length; i++)
          InkWell(
            onTap: () => onToggle(i),
            borderRadius: BorderRadius.circular(NexRadius.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: NexSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // A real checkbox, sized to the text beside it. The whole row
                  // is the target, so this is the mark rather than the control.
                  Icon(
                    items[i].done
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    size: 22,
                    color: items[i].done
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: NexSpacing.sm),
                  Expanded(
                    child: NexTextSurface(
                      items[i].text,
                      // Not selectable, unlike the note body above. The whole
                      // row is the tick target, and a `SelectionArea` sits
                      // deeper than the `InkWell` around it — so the tap that
                      // ticks the item would be claimed by the text instead.
                      // Ticking is the point of this list; copying one line of
                      // it is not.
                      style: theme.textTheme.bodyLarge?.copyWith(
                        decoration: items[i].done
                            ? TextDecoration.lineThrough
                            : null,
                        color: items[i].done
                            ? theme.colorScheme.onSurfaceVariant
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A link note: the page's description if one was read, then the address
/// itself as the row that opens it.
class _LinkBody extends StatelessWidget {
  const _LinkBody({required this.note, required this.onOpen});

  final Note note;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = note.linkUrl ?? '';
    final host = urlHost(url);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (note.linkExcerpt != null) ...[
          NexTextSurface(
            note.linkExcerpt!,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
            selectable: true,
          ),
          const SizedBox(height: NexSpacing.md),
        ],
        InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(NexRadius.md),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(NexSpacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(NexRadius.md),
            ),
            child: Row(
              children: [
                Icon(Icons.public, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: NexSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (host != null)
                        Text(host, style: theme.textTheme.titleSmall),
                      // The full address under the host, so it is possible to
                      // see where a link actually goes before following it.
                      Text(
                        url,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.open_in_new,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Everything a file note can show beyond its own name.
///
/// A file note stores a filename and a path, and for most of this app's life
/// that was all the sheet did with one: print the name, hand the path to the
/// operating system. Markdown was the single exception, rendered by a widget
/// wired to that one format by a predicate that could answer exactly one
/// question.
///
/// This is the generalisation. [NexFileKind] answers what the file is; this
/// answers what to do about it. A kind it has no answer for renders nothing
/// and leaves the row above untouched — which is the old behaviour, and the
/// right one for a format nobody here can draw.
class _FileBody extends StatelessWidget {
  const _FileBody({
    required this.path,
    required this.kind,
    required this.player,
    required this.onOpen,
  });

  final String path;
  final NexFileKind kind;

  /// Hands the file to the operating system — the same thing the row above
  /// does when tapped. A preview is a picture of the file, and tapping the
  /// picture should do what tapping its name does.
  final VoidCallback onOpen;

  /// Non-null once the sheet has loaded this file into the audio player.
  ///
  /// Owned by the sheet rather than created here: the player outlives any one
  /// rebuild, and a second one on the same note would play the file twice.
  final NexSteadyPosition? player;

  @override
  Widget build(BuildContext context) {
    if (kind.isText) return _FileTextBody(path: path, kind: kind);
    if (kind == NexFileKind.document) {
      // The two document formats this app can show anything of, and they are
      // shown in opposite ways: a `.docx` is converted to text, a `.pdf` is a
      // picture of a page. Anything else is named and left alone.
      return switch (NexFileKinds.extensionOf(path)) {
        'docx' => _DocumentBody(path: path),
        'pdf' => _PdfBody(path: path, onOpen: onOpen),
        _ => const SizedBox.shrink(),
      };
    }
    if (kind == NexFileKind.image) return _ImageFileBody(path: path);
    if (kind == NexFileKind.video) {
      return _VideoBody(path: path, onOpen: onOpen);
    }
    if (kind == NexFileKind.audio) {
      return Padding(
        padding: const EdgeInsets.only(top: NexSpacing.sm),
        child: NexVoicePlayer(path: path, steady: player),
      );
    }
    return const SizedBox.shrink();
  }
}

/// Reads a file off disk and shows it as what it is.
///
/// The words are not in the note. A file note stores its filename and a path,
/// so this is the one place in the app that reads a note's media back as text.
///
/// The read is synchronous, and in [initState] rather than in `build`. Both
/// halves are deliberate. Synchronous because [maxBytes] bounds it: half a
/// megabyte off local storage costs a fraction of a frame, and the sheet
/// around it already calls `existsSync` and `lengthSync` to print the file's
/// size. In `initState` because this sheet rebuilds on every action taken in
/// it — captioning, tagging, pinning — and re-reading the file each time would
/// turn a cheap read into a repeated one. A table is parsed there too, for the
/// same reason.
///
/// Three outcomes, all of them said out loud. A file too large is named but
/// not rendered, and says why. A file that cannot be read reports the
/// runtime's own words: a preview that silently shows nothing is
/// indistinguishable from a file that genuinely has nothing in it, and this
/// project has paid for that confusion before.
class _FileTextBody extends StatefulWidget {
  const _FileTextBody({required this.path, required this.kind});

  final String path;

  /// One of the four [NexFileKind.isText] kinds. Each is read the same way and
  /// drawn differently — and the difference matters: a `.txt` must not go
  /// through a Markdown parser, or a shopping list whose line starts with `#`
  /// acquires a heading nobody typed.
  final NexFileKind kind;

  /// Past this, the file is named but not rendered. Generous for prose —
  /// roughly a quarter of a million characters — and small enough that both
  /// reading it and building it stay inside a frame.
  static const maxBytes = 512 * 1024;

  /// Past this many rows a table is drawn short and says so. The byte cap
  /// alone does not bound the widget count: half a megabyte of two-column CSV
  /// is tens of thousands of rows, and every one of them would be built.
  static const maxRows = 200;

  @override
  State<_FileTextBody> createState() => _FileTextBodyState();
}

class _FileTextBodyState extends State<_FileTextBody> {
  String? _text;
  String? _error;
  bool _tooLarge = false;
  List<List<String>> _rows = const [];
  int _omittedRows = 0;

  /// Whether the file is drawn only once the sheet has finished rising.
  ///
  /// A long document read and laid out in the sheet's first frame took that
  /// frame past the whole opening animation, so the sheet appeared at once
  /// instead of rising (it did so for nothing shorter). A long file now
  /// rises as an empty sheet of its final height and its text fades in when
  /// the movement is done. A short one is cheap and is drawn straight away.
  bool _deferred = false;

  /// Past this many bytes a file waits for the opening animation.
  static const _deferAbove = 8 * 1024;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(_FileTextBody old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path || old.kind != widget.kind) _start();
  }

  void _start() {
    var size = 0;
    try {
      size = File(widget.path).lengthSync();
    } catch (_) {
      // Missing or unreadable: [_load] says which.
    }
    if (size <= _deferAbove) {
      _deferred = false;
      _load();
      return;
    }
    _deferred = true;
    _text = null;
    final path = widget.path;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await nexRouteOpened(context);
      if (!mounted || widget.path != path) return;
      setState(() {
        _deferred = false;
        _load();
      });
    });
  }

  void _load() {
    _text = null;
    _error = null;
    _tooLarge = false;
    _rows = const [];
    _omittedRows = 0;
    try {
      final file = File(widget.path);
      if (!file.existsSync()) return;
      if (file.lengthSync() > _FileTextBody.maxBytes) {
        _tooLarge = true;
        return;
      }
      _text = file.readAsStringSync();
    } catch (error) {
      // Reached by a file that is not UTF-8 as much as by one that cannot be
      // opened — `readAsStringSync` decodes, and a mislabelled binary lands
      // here rather than rendering as mojibake.
      _error = '$error';
      return;
    }
    if (widget.kind != NexFileKind.table) return;
    final parsed = NexDelimitedText.parse(
      _text!,
      delimiter: NexDelimitedText.delimiterFor(
        NexFileKinds.extensionOf(widget.path),
      ),
    );
    if (parsed.length > _FileTextBody.maxRows) {
      _omittedRows = parsed.length - _FileTextBody.maxRows;
      _rows = parsed.sublist(0, _FileTextBody.maxRows);
    } else {
      _rows = parsed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final quiet = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    if (_deferred) {
      // The height the text will take, more or less: a long file fills the
      // sheet, so the sheet rises at the size it will stay.
      return SizedBox(height: MediaQuery.sizeOf(context).height);
    }
    if (_tooLarge) {
      return Padding(
        padding: const EdgeInsets.only(top: NexSpacing.sm),
        child: Text(l10n.filePreviewTooLarge, style: quiet),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.only(top: NexSpacing.sm),
        child: Text(l10n.filePreviewUnreadable(_error!), style: quiet),
      );
    }
    final text = _text?.trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return _FadeIn(
      child: Padding(
        padding: const EdgeInsets.only(top: NexSpacing.sm),
        child: switch (widget.kind) {
          NexFileKind.markdown => SelectionArea(
            contextMenuBuilder: nexSelectionMenu,
            child: NexMarkdown(
              text,
              selectable: false,
              onTapLink: _openHref,
              onCopyCode: (code) => unawaited(_copyCodeSpan(context, code)),
            ),
          ),
          // The same leading as a text note's body in this same sheet: a plain
          // file someone shared and a note someone typed are both prose, and
          // there is no reason to read them at two different densities.
          NexFileKind.plainText => NexTextSurface(
            text,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.62),
            // As selectable as the markdown branch beside it. A shared file is
            // read here and nowhere else, so this is the only place its words
            // can be taken from.
            selectable: true,
          ),
          NexFileKind.table when _rows.isNotEmpty => _DelimitedTable(
            rows: _rows,
            omitted: _omittedRows,
          ),
          // A table whose parse produced nothing is still a text file, and
          // showing its source beats showing an empty frame.
          NexFileKind.table || NexFileKind.code => _CodeBlock(text),
          _ => const SizedBox.shrink(),
        },
      ),
    );
  }
}

/// Completes once the route [context] sits in has finished its opening
/// animation — at once if it already has, or if there is none.
Future<void> nexRouteOpened(BuildContext context) {
  final animation = ModalRoute.of(context)?.animation;
  if (animation == null || !animation.isAnimating) return Future.value();
  final done = Completer<void>();
  late final AnimationStatusListener listener;
  listener = (status) {
    if (status == AnimationStatus.forward) return;
    animation.removeStatusListener(listener);
    if (!done.isCompleted) done.complete();
  };
  animation.addStatusListener(listener);
  return done.future;
}

/// A short fade, so text that arrives after the sheet has opened eases in
/// rather than appearing in a single frame.
class _FadeIn extends StatelessWidget {
  const _FadeIn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: NexMotion.standard,
    curve: NexMotion.curve,
    builder: (context, value, child) => Opacity(opacity: value, child: child),
    child: child,
  );
}

/// Copies a tapped `code` span and says so.
///
/// Silently would not do: a tap that copied and a tap that missed look exactly
/// the same, and the second is the more likely of the two on a span two
/// characters wide.
Future<void> _copyCodeSpan(BuildContext context, String code) async {
  final message = AppLocalizations.of(context).copied;
  await Clipboard.setData(ClipboardData(text: code));
  if (!context.mounted) return;
  nexShowBanner(context, message: message);
}

/// The schemes a tapped link in a note may hand to the system.
@visibleForTesting
const nexFollowableLinkSchemes = {'http', 'https', 'mailto', 'tel'};

/// Follows a link out of rendered Markdown — a note's own body, or a file
/// shown inside one.
///
/// A schemeless href is ignored rather than guessed at: `[x](notes/plan.md)`
/// is a relative path in somebody's repository, and handing it to the OS as a
/// URL opens nothing at best.
///
/// Only web, mail and phone links are followed (SEC-05) — the rule the
/// sponsor card already keeps for remote content. A note's text can arrive
/// from a share, a fetched page or a converted file, and an `intent://` or
/// app deep link dressed as `[a website](…)` launches an installed app, not
/// a page.
Future<void> _openHref(String href) async {
  final uri = Uri.tryParse(href);
  if (uri == null || !nexFollowableLinkSchemes.contains(uri.scheme)) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // No handler for this scheme on this device. The link stays a link.
  }
}
