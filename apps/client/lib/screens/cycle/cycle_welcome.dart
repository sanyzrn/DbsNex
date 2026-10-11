part of '../cycle_screen.dart';

/// The three opening questions, each with "I don't know".
class _Welcome extends StatefulWidget {
  const _Welcome({
    required this.today,
    required this.solar,
    required this.onDone,
  });

  final DateTime today;
  final bool solar;
  final Future<void> Function(DateTime? lastStart, int? period, int? cycle)
  onDone;

  @override
  State<_Welcome> createState() => _WelcomeState();
}

class _WelcomeState extends State<_Welcome> {
  DateTime? _lastStart;
  int _period = 5;
  int _cycle = 28;
  bool _periodKnown = true;
  bool _cycleKnown = true;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    Widget question(String text) => Padding(
      padding: const EdgeInsets.only(top: NexSpacing.lg, bottom: NexSpacing.xs),
      child: Text(text, style: theme.textTheme.titleSmall),
    );
    Widget dontKnow(bool selected, ValueChanged<bool> onChanged) => FilterChip(
      label: Text(l10n.cycleDontKnow),
      selected: selected,
      onSelected: onChanged,
    );
    return ListView(
      padding: const EdgeInsets.all(NexSpacing.lg),
      children: [
        const CycleRise(
          child: Center(child: _Bud(icon: Icons.water_drop_outlined, size: 88)),
        ),
        const SizedBox(height: NexSpacing.md),
        Text(
          l10n.cycleWelcome,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: NexSpacing.sm),
        Text(
          l10n.cycleWelcomeBody,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        question(l10n.cycleAskLastStart),
        Wrap(
          spacing: NexSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('cycle-welcome-date'),
              icon: const Icon(Icons.event_outlined),
              label: Text(
                _lastStart == null
                    ? l10n.cyclePickDate
                    : cycleDayMonth(context, _lastStart!, solar: widget.solar),
              ),
              onPressed: () async {
                final picked = await nexPickDate(
                  context,
                  initial: _lastStart ?? widget.today,
                  first: widget.today.subtract(const Duration(days: 120)),
                  last: widget.today,
                  solar: widget.solar,
                );
                if (picked != null) setState(() => _lastStart = picked);
              },
            ),
            dontKnow(
              _lastStart == null,
              (_) => setState(() => _lastStart = null),
            ),
          ],
        ),
        question(l10n.cycleAskPeriodLength),
        if (_periodKnown)
          CycleStepper(
            label: '',
            value: _period,
            min: 1,
            max: 15,
            onChanged: (v) => setState(() => _period = v),
          ),
        dontKnow(!_periodKnown, (on) => setState(() => _periodKnown = !on)),
        question(l10n.cycleAskCycleLength),
        if (_cycleKnown)
          CycleStepper(
            label: '',
            value: _cycle,
            min: 15,
            max: 60,
            onChanged: (v) => setState(() => _cycle = v),
          ),
        dontKnow(!_cycleKnown, (on) => setState(() => _cycleKnown = !on)),
        const SizedBox(height: NexSpacing.xl),
        CycleBloomButton(
          key: const ValueKey('cycle-welcome-begin'),
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  await widget.onDone(
                    _lastStart,
                    _periodKnown ? _period : null,
                    _cycleKnown ? _cycle : null,
                  );
                  if (mounted) setState(() => _busy = false);
                },
          label: Text(l10n.cycleBegin),
        ),
        const SizedBox(height: NexSpacing.md),
        Text(
          l10n.cycleDisclaimer,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
