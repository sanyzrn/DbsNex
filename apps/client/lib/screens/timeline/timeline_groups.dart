part of '../timeline_screen.dart';

/// One date run: a heading and the notes under it.
class _NoteGroup {
  _NoteGroup({required this.key, required this.label, required this.notes});

  /// Stable across days, unlike the label. "Last week" holds different notes
  /// tomorrow; the key is what a collapsed state is remembered against.
  final String key;
  final String label;
  final List<Note> notes;
}

/// A row in the flattened list: either a heading or a note, never both.
class _TimelineRow {
  const _TimelineRow.header(this.group) : note = null, groupKey = null;
  const _TimelineRow.note(this.note, this.groupKey) : group = null;

  final _NoteGroup? group;
  final Note? note;

  /// Which run this note sits under. Needed only while a group is closing —
  /// see `_closingGroups`.
  final String? groupKey;
}

/// How long a run takes to fold away or open up.
const _foldDuration = Duration(milliseconds: 220);

/// The total vertical room a group heading claims, split 60/40 above and
/// below — see `_GroupHeader`.
const _headerSpace = NexSpacing.lg + NexSpacing.sm;

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
  });

  final bool open;

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
    if (widget.open) _controller.forward();
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
    final curved = CurvedAnimation(
      parent: _controller,
      curve: NexMotion.curve,
      reverseCurve: NexMotion.curve.flipped,
    );
    return SizeTransition(
      sizeFactor: curved,
      child: FadeTransition(
        opacity: curved.drive(CurveTween(curve: const Interval(0.25, 1))),
        child: widget.child,
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
  });

  final String label;
  final int count;
  final bool collapsed;
  final VoidCallback onToggle;

  /// Null when there is no provider to answer — a menu entry that can only
  /// say "unavailable" is worse than one that is not there.
  final VoidCallback? onAsk;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
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
                padding: const EdgeInsetsDirectional.fromSTEB(
                  NexSpacing.md,
                  _headerSpace * 0.6,
                  // Nothing on the trailing side: the menu button beside this
                  // carries its own, and the chevron sits just inside it rather
                  // than out at the screen edge on its own.
                  0,
                  _headerSpace * 0.4,
                ),
                child: Row(
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: NexSpacing.sm),
                    // Only when folded. Open, the count is the list itself, and a
                    // number beside a heading you can already read is noise.
                    if (collapsed)
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
        Padding(
          // The same vertical padding the heading carries, so the two glyphs
          // sit on one line. Without it the menu centred itself in the row's
          // full height while the chevron sat inside the heading's 60/40
          // weighting, and the pair read as very slightly crooked — which is
          // the kind of thing you see before you can say what it is.
          padding: const EdgeInsetsDirectional.fromSTEB(
            NexSpacing.xs,
            _headerSpace * 0.6,
            NexSpacing.md,
            _headerSpace * 0.4,
          ),
          child: PopupMenuButton<_GroupAction>(
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
            // Rounded, on a raised surface, sitting under the button rather
            // than over it.
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(NexRadius.lg),
            ),
            color: theme.colorScheme.surfaceContainerHigh,
            elevation: 3,
            popUpAnimationStyle: AnimationStyle(
              duration: NexMotion.standard,
              curve: NexMotion.curve,
            ),
            onSelected: (action) => switch (action) {
              _GroupAction.ask => onAsk?.call(),
              _GroupAction.delete => onDelete(),
            },
            itemBuilder: (context) => [
              if (onAsk != null)
                PopupMenuItem(
                  value: _GroupAction.ask,
                  child: _GroupMenuRow(
                    icon: Icons.auto_awesome_outlined,
                    label: l10n.groupAsk,
                  ),
                ),
              PopupMenuItem(
                value: _GroupAction.delete,
                child: _GroupMenuRow(
                  icon: Icons.delete_outline,
                  label: l10n.groupDelete,
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One line of the date heading's menu.
///
/// A plain row rather than a `ListTile`: a ListTile inside a PopupMenuItem is
/// two sets of vertical padding and two minimum heights fighting each other,
/// and the result was a menu whose rows were taller than they looked and
/// whose text sat off-centre against its own icon.
class _GroupMenuRow extends StatelessWidget {
  const _GroupMenuRow({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color ?? theme.colorScheme.onSurface;
    return Row(
      children: [
        Icon(icon, size: 20, color: tint),
        const SizedBox(width: NexSpacing.md),
        // Flexible, and so allowed to wrap. A popup menu is at most 280
        // logical pixels wide, and "Delete this group" beside an icon and a
        // gap does not fit that in every language — the ListTile this
        // replaced was quietly handling it, and a bare Row is not. The item
        // grows to a second line rather than clipping the label, because
        // `PopupMenuItem`'s height is a minimum.
        Flexible(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(color: tint),
          ),
        ),
      ],
    );
  }
}

/// What a date heading's menu can do to the whole run under it.
enum _GroupAction { ask, delete }
