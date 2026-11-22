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
  });
  final List<Fields> eligible;
  final int round;
  final bool redraw;
  final NexModuleMonth month;
  final String potText;
  final Future<Fields?> Function(String reason) onDraw;

  @override
  State<_DrawSheet> createState() => _DrawSheetState();
}

class _DrawSheetState extends State<_DrawSheet> {
  final reason = TextEditingController();
  bool busy = false;
  String? error;
  Fields? result;

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
    if (widget.redraw && reason.text.trim().isEmpty) {
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
    setState(() {
      busy = false;
      result = drawn;
      error = drawn == null ? 'saveError' : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = fundStrings;
    final name = winnerName;
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
                widget.redraw ? s(context, 'redraw') : s(context, 'drawSheet'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (result == null) ...[
                const SizedBox(height: NexSpacing.xs),
                Text(
                  s(context, 'drawEligible', {'n': widget.eligible.length}),
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
                      for (final member in widget.eligible)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: const Icon(Icons.person_outline, size: 20),
                          title: Text(nameOf(member)),
                          subtitle: Text(
                            s(context, 'shareCount', {'n': member['shares']}),
                          ),
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
                if (widget.redraw) ...[
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
              ] else ...[
                const SizedBox(height: NexSpacing.md),
                Semantics(
                  liveRegion: true,
                  label: '${s(context, 'drawResult')}: ${name ?? ''}',
                  child: TweenAnimationBuilder<double>(
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
              ],
            ],
          ),
        ),
      ),
    );
  }
}
