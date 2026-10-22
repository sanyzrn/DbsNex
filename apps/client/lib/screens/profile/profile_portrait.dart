import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../platform/nex_preferences.dart';
import '../../platform/nex_services.dart';
import '../../widgets/nex_banner.dart';

part 'profile_portrait_charts.dart';
part 'profile_portrait_counted.dart';
part 'profile_portrait_motion.dart';
part 'profile_portrait_written.dart';

/// The writing portrait at the foot of the profile (2.1.7).
///
/// Two layers, deliberately. The counted one — when somebody writes, what
/// kind of notes they keep, how often, about what — is arithmetic over the
/// library and needs nothing but the phone, so it is there for everyone once
/// there is enough to count. The written one is a model reading a sample of
/// the notes, and is only ever asked for here, by a button that says what it
/// sends.
///
/// Locked until there is something to read: a ring fills toward
/// [NexWritingStats.minNotes] notes on [NexWritingStats.minDays] days, so
/// the empty state is a goal rather than a blank.
class ProfilePortrait extends StatefulWidget {
  const ProfilePortrait({
    super.key,
    required this.services,
    required this.preferences,
  });

  final NexServices services;
  final NexPreferences preferences;

  @override
  State<ProfilePortrait> createState() => _ProfilePortraitState();
}

class _ProfilePortraitState extends State<ProfilePortrait>
    with SingleTickerProviderStateMixin {
  /// Notes a portrait is written from at most; said on the button.
  static const _sample = 80;

  /// How long the card takes to assemble itself.
  static const _arrival = Duration(milliseconds: 2400);

  NexWritingStats? _stats;
  bool _writing = false;

  /// The clock every section of the card reads ([_Entrance]). It starts when
  /// the card is first on screen, not when it is built: the portrait sits at
  /// the foot of a long page, and an arrival nobody was there to see is not one.
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: _arrival,
  );
  ScrollPosition? _watching;

  @override
  void initState() {
    super.initState();
    unawaited(_count());
  }

  @override
  void dispose() {
    _watching?.removeListener(_arriveIfSeen);
    _enter.dispose();
    super.dispose();
  }

  Future<void> _count() async {
    final notes = await widget.services.portraitNotes();
    if (!mounted) return;
    setState(() => _stats = nexWritingStats(notes));
    WidgetsBinding.instance.addPostFrameCallback((_) => _arrive());
  }

  /// Plays the arrival now if the card is on screen, else when scrolling
  /// brings it there. With reduced motion it is simply there.
  void _arrive() {
    if (!mounted || _enter.value > 0) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _enter.value = 1;
      return;
    }
    if (_onScreen()) {
      unawaited(_enter.forward());
      return;
    }
    final position = Scrollable.maybeOf(context)?.position;
    if (position == null) {
      unawaited(_enter.forward());
      return;
    }
    _watching = position..addListener(_arriveIfSeen);
  }

  void _arriveIfSeen() {
    if (!mounted || !_onScreen()) return;
    _watching?.removeListener(_arriveIfSeen);
    _watching = null;
    unawaited(_enter.forward());
  }

  /// Whether the card's top is inside the window, with a little margin so it
  /// starts as it comes up rather than when it is already fully there.
  bool _onScreen() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached) return false;
    final top = box.localToGlobal(Offset.zero).dy;
    final height = MediaQuery.sizeOf(context).height;
    return top < height * 0.85;
  }

  Future<void> _write() async {
    if (_writing) return;
    setState(() => _writing = true);
    final portrait = await widget.services.writePortrait();
    if (!mounted) return;
    setState(() => _writing = false);
    if (portrait != null) {
      // The new one assembles itself the way the first did.
      if (!MediaQuery.disableAnimationsOf(context)) {
        unawaited(_enter.forward(from: 0));
      }
    } else {
      nexShowBanner(
        context,
        message: AppLocalizations.of(context).portraitFailed,
        kind: NexBannerKind.failed,
        haptics: widget.preferences.haptics,
      );
    }
  }

  Future<void> _needsAi() async {
    nexShowBanner(
      context,
      message: AppLocalizations.of(context).portraitNeedsAi,
      kind: NexBannerKind.ai,
      haptics: widget.preferences.haptics,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final stats = _stats;
    final portrait = widget.preferences.profilePortrait;
    return DecoratedBox(
      key: const ValueKey('profile-portrait'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(NexRadius.xl),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.13),
              scheme.surfaceContainerLow,
            ),
            Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.03),
              scheme.surfaceContainerLow,
            ),
          ],
        ),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(NexSpacing.lg),
        child: _Entrance(
          animation: _enter,
          child: NexAnimatedSize(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(l10n: l10n),
                const SizedBox(height: NexSpacing.lg),
                if (stats == null)
                  const NexSkeleton(height: 72)
                else if (!stats.unlocked && portrait == null)
                  _Locked(stats: stats)
                else ...[
                  if (stats.notes > 0) ...[
                    _Counted(stats: stats),
                    const SizedBox(height: NexSpacing.lg),
                    Divider(color: scheme.primary.withValues(alpha: 0.15)),
                    const SizedBox(height: NexSpacing.md),
                  ],
                  if (_writing)
                    _Writing(label: l10n.portraitWriting)
                  else if (portrait != null)
                    _Written(
                      portrait: portrait,
                      preferences: widget.preferences,
                      // Always offered once there is enough to write from: a
                      // button that is only there with a model set up reads as
                      // missing, not as "set one up". Without a model it says so.
                      onRewrite: stats.unlocked
                          ? () => unawaited(
                              widget.services.portraitWritable
                                  ? _write()
                                  : _needsAi(),
                            )
                          : null,
                    )
                  else if (widget.services.portraitWritable)
                    _Ask(
                      onWrite: () => unawaited(_write()),
                      privacy: l10n.portraitPrivacy(
                        nexDigits('$_sample', persian: l10n.localeName == 'fa'),
                      ),
                    )
                  else
                    Text(
                      l10n.portraitNeedsAi,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: NexSpacing.md),
                  Text(
                    l10n.portraitDisclaimer,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [scheme.primary, scheme.primaryContainer],
            ),
          ),
          child: Icon(Icons.auto_awesome, size: 22, color: scheme.onPrimary),
        ),
        const SizedBox(width: NexSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.portraitTitle, style: theme.textTheme.titleMedium),
              Text(
                l10n.portraitSubtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Not enough to read yet: a ring filling toward the notes needed.
class _Locked extends StatelessWidget {
  const _Locked({required this.stats});

  final NexWritingStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = l10n.localeName == 'fa';
    final progress = (stats.notes / NexWritingStats.minNotes).clamp(0.0, 1.0);
    return Row(
      key: const ValueKey('profile-portrait-locked'),
      children: [
        SizedBox(
          width: 76,
          height: 76,
          child: Stack(
            fit: StackFit.expand,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: progress),
                duration: NexMotion.of(context, NexMotion.slow),
                curve: NexMotion.curve,
                builder: (context, value, _) => CircularProgressIndicator(
                  value: value,
                  strokeWidth: 6,
                  strokeCap: StrokeCap.round,
                  backgroundColor: scheme.primary.withValues(alpha: 0.14),
                ),
              ),
              Center(
                child: Text(
                  nexDigits(
                    '${stats.notes.clamp(0, NexWritingStats.minNotes)}/'
                    '${NexWritingStats.minNotes}',
                    persian: persian,
                  ),
                  textDirection: TextDirection.ltr,
                  style: theme.textTheme.labelLarge,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: NexSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (stats.notesToGo > 0)
                Text(
                  _digits(l10n.portraitLocked(stats.notesToGo), persian),
                  style: theme.textTheme.bodyMedium,
                ),
              if (stats.daysToGo > 0)
                Text(
                  _digits(l10n.portraitLockedDays(stats.daysToGo), persian),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

String _digits(String text, bool persian) => nexDigits(text, persian: persian);

class _Ask extends StatelessWidget {
  const _Ask({required this.onWrite, required this.privacy});

  final VoidCallback onWrite;
  final String privacy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          key: const ValueKey('profile-portrait-write'),
          onPressed: onWrite,
          icon: const Icon(Icons.auto_awesome),
          label: Text(l10n.portraitWrite),
        ),
        const SizedBox(height: NexSpacing.sm),
        Text(
          privacy,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _Writing extends StatelessWidget {
  const _Writing({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: NexSpacing.md),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: NexSpacing.sm),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ],
    ),
  );
}
