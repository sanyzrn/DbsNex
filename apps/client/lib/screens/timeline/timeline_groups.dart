part of '../timeline_screen.dart';

/// One date run — or, arranged by kind or tag, one shelf (2.7.0): a heading
/// and the notes under it.
class _NoteGroup {
  _NoteGroup({
    required this.key,
    required this.label,
    required this.notes,
    this.shelf,
    this.echoes = const {},
  });

  /// The shelf this group shows, when the home is arranged by kind or tag.
  /// Null for a day.
  final NexShelf? shelf;

  /// Notes already shown under an earlier heading — by tag, a note carrying
  /// two tags sits on both shelves. Only its first appearance is the one a
  /// reveal scrolls to: a [GlobalKey] can be on one widget only.
  final Set<String> echoes;

  /// Whether the heading's count and actions cover the whole group: a shelf
  /// showing its newest few holds more than it shows, and deleting "Photos"
  /// must not quietly mean "these six photos".
  bool get complete => !(shelf?.more ?? false);

  /// The heading's count: everything the shelf holds, not just what it shows.
  int get count => shelf?.total ?? notes.length;

  /// Stable across days, unlike the label. "Last week" holds different notes
  /// tomorrow; the key is what a collapsed state is remembered against.
  final String key;
  final String label;
  final List<Note> notes;
}

/// A row in the flattened list: a heading, a note, or a shelf's "See all".
class _TimelineRow {
  const _TimelineRow.header(this.group)
    : note = null,
      groupKey = null,
      moreOf = null,
      primary = true,
      indexInGroup = 0;
  const _TimelineRow.note(
    this.note,
    this.groupKey,
    this.indexInGroup, {
    this.primary = true,
  }) : group = null,
       moreOf = null;
  const _TimelineRow.more(_NoteGroup this.moreOf, this.indexInGroup)
    : group = null,
      note = null,
      primary = true,
      groupKey = null;

  /// A note's key names its shelf too when the home is arranged — by tag, the
  /// same note can be on two — and stays `note-<id>` by day, as it always was.
  String get key => group != null
      ? 'group-${group!.key}'
      : moreOf != null
      ? 'more-${moreOf!.key}'
      : groupKey?.contains(':') ?? false
      ? 'note-$groupKey-${note!.id}'
      : 'note-${note!.id}';

  final _NoteGroup? group;
  final Note? note;

  /// The shelf whose "See all" this row is.
  final _NoteGroup? moreOf;

  /// Whether this is the note's first appearance — see [_NoteGroup.echoes].
  final bool primary;

  /// Which run this note sits under. Needed only while a group is closing —
  /// see `_closingGroups`.
  final String? groupKey;

  /// Where in its run this note is, which sets its place in the fold's
  /// cascade — see [_FoldingRow.order].
  final int indexInGroup;
}

/// How long a run takes to fold away or open up.
///
/// Long enough for the cascade to read as one movement: each row folds over
/// most of it, a little after the one above — see [_FoldingRow.order].
const _foldDuration = NexMotion.morph;

/// The total vertical room a group heading claims, split 60/40 above and
/// below — see `_GroupHeader`.
const _headerSpace = NexSpacing.lg;

/// One note row, which grows in when its group opens and shrinks out when it
/// closes.
///
/// A `SizeTransition` rather than an `AnimatedSize`, because the two ends are
/// not symmetrical. A row that has just been inserted has to start closed and
/// open itself — that is the expand. A row on its way out is still in the list
/// only because [_TimelineScreenState._toggleGroup] is holding it there for
/// exactly this animation, and it has to reach zero before the fold commits.
///
/// The fade is deliberately faster than the size: content that disappears
/// before the space does reads as leaving, where the two together read as
/// being squashed.
class _FoldingRow extends StatefulWidget {
  const _FoldingRow({
    super.key,
    required this.open,
    required this.animateIn,
    required this.child,
    this.order = 0,
  });

  final bool open;

  /// This row's place in its run. The rows of a run used to fold all at once,
  /// as one block shrinking to nothing; now each starts a beat after the one
  /// above it, so a day opens like a fan and closes back up into its heading,
  /// last row first. Capped, so a long run does not keep the last rows
  /// waiting.
  final int order;

  /// Whether this row is arriving now, or was already here.
  ///
  /// False means "start at full height and stay there". A row that was
  /// already on screen must not animate itself in when its index shifts —
  /// see `_openingGroups`.
  final bool animateIn;

  final Widget child;

  @override
  State<_FoldingRow> createState() => _FoldingRowState();
}

class _FoldingRowState extends State<_FoldingRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _foldDuration,
      // Closed only when this row is genuinely arriving. Otherwise it starts
      // where it already was, which is the difference between one group
      // opening and every group below it flickering.
      value: widget.animateIn ? 0 : 1,
    );
    if (widget.open) {
      _controller.forward();
    } else {
      // Built already closing: the grid view builds its folding rows only
      // when a day starts to fold, so a row that is born closed has to fold
      // from where it was — full height — rather than sit there until the
      // fold is committed and it vanishes in one frame (2.6.29).
      _controller.reverse();
    }
  }

  @override
  void didUpdateWidget(_FoldingRow old) {
    super.didUpdateWidget(old);
    if (widget.open == old.open) return;
    widget.open ? _controller.forward() : _controller.reverse();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Someone who asked for less motion gets none of this: the row is simply
    // there or not, which is what the setting means.
    if (MediaQuery.disableAnimationsOf(context)) {
      return widget.open ? widget.child : const SizedBox.shrink();
    }
    final start = (widget.order * 0.07).clamp(0.0, 0.35);
    final curved = CurvedAnimation(
      parent: _controller,
      // Every row ends with the fold, and the later ones start later — so
      // opening, the run fans out from the top; closing, every row starts at
      // once and the lower ones, with less time, are gone first. Nothing
      // waits before it moves.
      curve: Interval(start, 1, curve: NexMotion.moveCurve),
    );
    // The size and the look move apart: the space opens on the whole curve,
    // while the card fades and settles in over its second half — drifting
    // down a few pixels and up to full size, rather than being uncovered by
    // a hard edge.
    final settle = curved.drive(CurveTween(curve: const Interval(0.3, 1)));
    // A repaint boundary per folding row (F-04): every mounted row folds
    // at once on a pinch, and without one each row's opacity layer dirties
    // the viewport's layer too — the measured 761ms trigger frame.
    return RepaintBoundary(
      child: SizeTransition(
        sizeFactor: curved,
        alignment: Alignment.topCenter,
        child: AnimatedBuilder(
          animation: settle,
          builder: (context, child) => Opacity(
            opacity: settle.value,
            child: Transform.translate(
              offset: Offset(0, -10 * (1 - settle.value)),
              child: Transform.scale(
                scale: 0.96 + 0.04 * settle.value,
                alignment: Alignment.topCenter,
                child: child,
              ),
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// The heading over a date run: its fold control, and what can be done to the
/// whole run at once.
///
/// The heading itself is the fold target rather than the chevron alone — a
/// 16-pixel caret is a worse thing to aim at than a heading. The menu is
/// deliberately *outside* that target: it is the one other thing on the row,
/// and a three-dot button that also folded the group on the way to opening
/// would be a button that does two things at once.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.label,
    required this.count,
    required this.collapsed,
    required this.onToggle,
    required this.onAsk,
    required this.onDelete,
    this.compact = false,
    this.leading,
    this.alwaysCount = false,
    this.onMoveUp,
    this.onMoveDown,
  });

  /// A shelf's mark before its name (2.7.0): the kind's icon in its colour,
  /// or the tag's own dot.
  final Widget? leading;

  /// A shelf names its count open as well as folded: it shows its newest few
  /// of more, and the number is how many more.
  final bool alwaysCount;

  /// A shelf's place among the others, a step at a time. Null for a day, or
  /// at the end it cannot move past.
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  /// The desktop's: a small label, the count always, no side gutter.
  final bool compact;

  final String label;
  final int count;
  final bool collapsed;
  final VoidCallback onToggle;

  /// Null when there is no provider to answer — a menu entry that can only
  /// say "unavailable" is worse than one that is not there.
  final VoidCallback? onAsk;

  /// Null when the heading's notes are not all on screen — see
  /// [_NoteGroup.complete].
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final persian = Localizations.localeOf(context).languageCode == 'fa';
    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            expanded: !collapsed,
            label: label,
            child: InkWell(
              onTap: onToggle,
              // A heading is not a button, and the stock ripple across a full-width
              // row read as one — a slab of colour flashing under a label. Kept as
              // a hint that the row is live, at a quarter of the weight.
              splashFactory: NoSplash.splashFactory,
              highlightColor: theme.colorScheme.onSurface.withValues(
                alpha: 0.04,
              ),
              hoverColor: theme.colorScheme.onSurface.withValues(alpha: 0.03),
              child: Padding(
                // Level with the cards below it — the same horizontal gutter
                // `nexCardInsets` gives them, so the heading and the run it names
                // start on the same line instead of the heading sitting inside the
                // margin.
                //
                // Vertically it is weighted 60/40 toward the top. A heading belongs
                // to what follows it, and even spacing makes it read as floating
                // between two runs rather than opening one.
                padding: compact
                    ? const EdgeInsetsDirectional.fromSTEB(0, 12, 0, 8)
                    : const EdgeInsetsDirectional.fromSTEB(
                        NexSpacing.md,
                        _headerSpace * 0.6,
                        // Nothing on the trailing side: the menu button beside
                        // this carries its own, and the chevron sits just
                        // inside it rather than out at the screen edge.
                        0,
                        _headerSpace * 0.4,
                      ),
                child: Row(
                  children: [
                    if (leading case final mark?) ...[
                      mark,
                      const SizedBox(width: NexSpacing.sm),
                    ],
                    // A day's name in the page's own ink, a step up from
                    // the small grey label it was: the headings are how a
                    // long timeline is read, and they were the faintest
                    // thing on it.
                    Flexible(
                      child: Text(
                        compact && !persian ? label.toUpperCase() : label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: compact
                            // The desktop's: small, quiet, in capitals where
                            // the script has them (letter-spacing would pull
                            // Persian apart). At the theme's own caption floor —
                            // nothing in the app is smaller (V-18).
                            ? theme.textTheme.labelSmall?.copyWith(
                                fontSize: 12,
                                letterSpacing: persian ? 0 : 0.8,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurfaceVariant,
                              )
                            : theme.textTheme.titleSmall?.copyWith(
                                color: theme.colorScheme.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                      ),
                    ),
                    const SizedBox(width: NexSpacing.sm),
                    // Only when folded. Open, the count is the list itself, and a
                    // number beside a heading you can already read is noise.
                    if (collapsed || compact || alwaysCount)
                      Text(
                        l10n.timelineGroupCount(count),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    const Spacer(),
                    AnimatedRotation(
                      turns: collapsed ? -0.25 : 0,
                      duration: NexMotion.standard,
                      curve: NexMotion.curve,
                      child: Icon(
                        Icons.expand_more,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (onAsk != null ||
            onDelete != null ||
            onMoveUp != null ||
            onMoveDown != null)
          Padding(
            // The same vertical padding the heading carries, so the two glyphs
            // sit on one line. Without it the menu centred itself in the row's
            // full height while the chevron sat inside the heading's 60/40
            // weighting, and the pair read as very slightly crooked — which is
            // the kind of thing you see before you can say what it is.
            padding: compact
                ? const EdgeInsetsDirectional.only(top: 4)
                : const EdgeInsetsDirectional.fromSTEB(
                    NexSpacing.xs,
                    _headerSpace * 0.6,
                    NexSpacing.md,
                    _headerSpace * 0.4,
                  ),
            child: NexPopupMenuButton<_GroupAction>(
              tooltip: l10n.groupActions,
              // Horizontal. A vertical ellipsis beside a chevron is two marks
              // running in two directions; laid flat it reads as a row of
              // controls rather than one control and a stray column of dots.
              icon: Icon(
                Icons.more_horiz,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              // Padding around the icon, not around the menu. The default is
              // large enough to set the height of every date heading in the
              // list; this keeps a tap target the thumb can find without the
              // button deciding how tall the row is.
              padding: const EdgeInsets.all(NexSpacing.sm),
              onSelected: (action) => switch (action) {
                _GroupAction.ask => onAsk?.call(),
                _GroupAction.delete => onDelete?.call(),
                _GroupAction.moveUp => onMoveUp?.call(),
                _GroupAction.moveDown => onMoveDown?.call(),
              },
              itemBuilder: (context) => [
                if (onMoveUp != null)
                  nexMenuItem(
                    value: _GroupAction.moveUp,
                    icon: Icons.arrow_upward_rounded,
                    label: l10n.groupMoveUp,
                  ),
                if (onMoveDown != null)
                  nexMenuItem(
                    value: _GroupAction.moveDown,
                    icon: Icons.arrow_downward_rounded,
                    label: l10n.groupMoveDown,
                  ),
                if (onAsk != null)
                  nexMenuItem(
                    value: _GroupAction.ask,
                    icon: Icons.auto_awesome_outlined,
                    label: l10n.groupAsk,
                  ),
                if (onDelete != null)
                  nexMenuItem(
                    value: _GroupAction.delete,
                    icon: Icons.delete_outline,
                    label: l10n.groupDelete,
                    destructive: true,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// What a date heading's menu can do to the whole run under it.
enum _GroupAction { moveUp, moveDown, ask, delete }
