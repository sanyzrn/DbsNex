part of 'detail.dart';

/// The draw, in one place: who is eligible, one clear button, and a result
/// that stays on screen. The first draw and a redraw share the sheet; a
/// redraw asks for its written reason before it can run.
///
/// The randomness is decided once, on the phone, and the result is written
/// before it is shown — the animation is only how it arrives, never a
/// second draw.
class _DrawSheet extends StatefulWidget {
  const _DrawSheet({
    required this.eligible,
    required this.round,
    required this.redraw,
    required this.month,
    required this.potText,
    required this.onDraw,
    required this.remaining,
    required this.onHistory,
  });
  final List<Fields> eligible;
  final int round;
  final bool redraw;
  final NexModuleMonth month;
  final String potText;
  final Future<Fields?> Function(String reason) onDraw;
  final List<Fields> Function() remaining;
  final Future<void> Function() onHistory;

  @override
  State<_DrawSheet> createState() => _DrawSheetState();
}

class _DrawSheetState extends State<_DrawSheet> {
  final reason = TextEditingController();
  bool busy = false;
  bool editingRedraw = false;
  late List<Fields> eligible = widget.eligible;
  String? error;
  Fields? result;
  bool get redraw => widget.redraw || result != null;

  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  String? get winnerName {
    final draw = result;
    if (draw == null) return null;
    final found = rows(draw['eligible'])
        .where((e) => e['id'] == draw['winner'])
        .firstOrNull;
    return found == null ? null : nameOf(found);
  }

  Future<void> draw() async {
    if (busy) return;
    if (redraw && reason.text.trim().isEmpty) {
      setState(() => error = 'invalidReason');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    final drawn = await widget.onDraw(reason.text.trim());
    if (!mounted) return;
    if (drawn != null) reason.clear();
    setState(() {
      busy = false;
      error = drawn == null ? 'saveError' : null;
      if (drawn != null) {
        result = drawn;
        eligible = widget.remaining();
        editingRedraw = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = fundStrings;
    final name = winnerName;
    final showForm = result == null || editingRedraw;
    return PopScope<void>(
      canPop: !busy,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(NexSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                showForm && redraw
                    ? s(context, 'redraw')
                    : s(context, 'drawSheet'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (showForm) ...[
                if (name != null) ...[
                  const SizedBox(height: NexSpacing.xs),
                  Text(s(context, 'winner', {'name': name})),
                ],
                const SizedBox(height: NexSpacing.xs),
                Text(
                  s(context, 'drawEligible', {'n': eligible.length}),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: NexSpacing.md),
                NexPanel(
                  title: s(context, 'pool', {'n': widget.round}),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final member in eligible)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: const Icon(Icons.person_outline, size: 20),
                          title: Text(nameOf(member)),
                          subtitle: member['shares'] is int
                              ? Text(
                                  s(context, 'shareCount', {
                                    'n': member['shares'],
                                  }),
                                )
                              : null,
                        ),
                      const SizedBox(height: NexSpacing.xs),
                      Text(
                        fundLabeled(context, s(context, 'pot'), widget.potText),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: NexSpacing.sm),
                Text(
                  s(context, 'drawPolicy'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (redraw) ...[
                  const SizedBox(height: NexSpacing.md),
                  Text(s(context, 'redrawHint')),
                  const SizedBox(height: NexSpacing.xs),
                  NexTextField(
                    controller: reason,
                    minLines: 2,
                    maxLines: 3,
                    maxLength: 120,
                    decoration: InputDecoration(
                      labelText: s(context, 'reason'),
                    ),
                  ),
                ],
                if (error != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      top: NexSpacing.xs,
                    ),
                    child: Text(
                      s(context, error!),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: NexSpacing.md),
                FilledButton.icon(
                  key: const ValueKey('draw-confirm'),
                  onPressed: busy ? null : draw,
                  icon: const Icon(Icons.casino_outlined),
                  label: Text(s(context, busy ? 'drawing' : 'drawNow')),
                ),
                if (editingRedraw)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                            editingRedraw = false;
                            error = null;
                            reason.clear();
                          }),
                    child: Text(s(context, 'cancel')),
                  ),
              ] else ...[
                const SizedBox(height: NexSpacing.md),
                Semantics(
                  liveRegion: true,
                  label: '${s(context, 'drawResult')}: ${name ?? ''}',
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey(result!['id']),
                    tween: Tween(begin: 0.92, end: 1),
                    duration: NexMotion.of(context, NexMotion.pop),
                    curve: NexMotion.popCurve,
                    builder: (context, scale, child) =>
                        Transform.scale(scale: scale, child: child),
                    child: NexPanel(
                      child: Column(
                        children: [
                          Icon(
                            Icons.emoji_events_outlined,
                            size: 48,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: NexSpacing.sm),
                          Text(
                            s(context, 'drawResult'),
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          Text(
                            name ?? s(context, 'none'),
                            style: Theme.of(context).textTheme.headlineSmall,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: NexSpacing.xs),
                          Text(
                            [
                              widget.month.title(context),
                              s(context, 'round', {'n': widget.round}),
                            ].join(fundSep(context)),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: NexSpacing.xs),
                          Text(
                            s(context, 'drawSaved'),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: NexSpacing.md),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(s(context, 'done')),
                ),
                if (eligible.isNotEmpty)
                  TextButton(
                    key: const ValueKey('draw-again-in-sheet'),
                    onPressed: () => setState(() => editingRedraw = true),
                    child: Text(s(context, 'redraw')),
                  ),
                TextButton(
                  onPressed: () => unawaited(widget.onHistory()),
                  child: Text(s(context, 'drawHistory')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
