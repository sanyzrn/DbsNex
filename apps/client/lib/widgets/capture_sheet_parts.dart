part of 'capture_sheet.dart';

/// The note type each kind is written as, for its colour and its glyph.
String _wire(CaptureKind kind) => switch (kind) {
  CaptureKind.note => 'text',
  CaptureKind.checklist => 'checklist',
  CaptureKind.voice => 'voice',
  CaptureKind.link => 'link',
};

IconData _kindIcon(CaptureKind kind) => switch (kind) {
  CaptureKind.note => Icons.notes_outlined,
  CaptureKind.voice => Icons.mic_none,
  CaptureKind.checklist => Icons.checklist_rtl_outlined,
  CaptureKind.link => Icons.link_outlined,
};

String _kindLabel(AppLocalizations l10n, CaptureKind kind) => switch (kind) {
  CaptureKind.note => l10n.captureKindNote,
  CaptureKind.voice => l10n.voice,
  CaptureKind.checklist => l10n.checklist,
  CaptureKind.link => l10n.link,
};

/// What is being captured, chosen at the top of the sheet.
///
/// The three ways of using the same text field. Media lives below it.
class _KindBar extends StatelessWidget {
  const _KindBar({
    required this.shown,
    required this.recording,
    required this.onSelect,
  });

  final CaptureKind shown;
  final bool recording;
  final ValueChanged<CaptureKind> onSelect;

  static const _order = [
    CaptureKind.note,
    CaptureKind.checklist,
    CaptureKind.link,
  ];

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    explicitChildNodes: true,
    label: AppLocalizations.of(context).captureKinds,
    // Scrolls rather than overflows: the largest text on the smallest phone
    // still reaches the link.
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final kind in _order)
            _KindChip(
              kind: kind,
              selected: kind == shown,
              // While recording, only the recorder's own buttons decide.
              enabled: !recording,
              onTap: () => onSelect(kind),
            ),
        ],
      ),
    ),
  );
}

class _KindChip extends StatelessWidget {
  const _KindChip({
    required this.kind,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final CaptureKind kind;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tint = nexNoteTypeTint(_wire(kind), scheme);
    final label = _kindLabel(AppLocalizations.of(context), kind);
    return Semantics(
      selected: selected,
      button: true,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: enabled ? onTap : null,
          customBorder: const StadiumBorder(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: nexMinTapTarget,
              minHeight: nexMinTapTarget,
            ),
            child: Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: selected ? 1 : 0),
                duration: NexMotion.of(context, NexMotion.morph),
                curve: NexMotion.moveCurve,
                builder: (context, t, _) {
                  final glyph = Color.lerp(
                    scheme.onSurfaceVariant,
                    tint,
                    t,
                  )!.withValues(alpha: enabled ? 1 : 0.38);
                  return Container(
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: NexSpacing.sm + NexSpacing.xs,
                      vertical: NexSpacing.sm,
                    ),
                    decoration: ShapeDecoration(
                      shape: const StadiumBorder(),
                      color: tint.withValues(alpha: 0.16 * t),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_kindIcon(kind), size: 20, color: glyph),
                        const SizedBox(width: NexSpacing.xs),
                        ExcludeSemantics(
                          child: Text(
                            label,
                            maxLines: 1,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: scheme.onSurface.withValues(
                                alpha: enabled ? 1 : 0.38,
                              ),
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The box the words are written in, in the colour of what they will be.
///
/// It changes colour as the kind does, and when the microphone is chosen
/// the field inside it gives way to the recorder — the box itself is what
/// turns into one, rather than a sheet rising over it.
class _ComposerBox extends StatelessWidget {
  const _ComposerBox({required this.kind, required this.child});

  final CaptureKind kind;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = nexNoteTypeTint(_wire(kind), scheme);
    final dark = scheme.brightness == Brightness.dark;
    final morph = NexMotion.of(context, NexMotion.morph);
    return AnimatedContainer(
      duration: morph,
      curve: NexMotion.moveCurve,
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: NexSpacing.md,
        vertical: NexSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: dark ? 0.12 : 0.07),
        borderRadius: BorderRadius.circular(NexRadius.lg),
        border: Border.all(color: tint.withValues(alpha: 0.3)),
      ),
      child: AnimatedSize(
        duration: morph,
        curve: NexMotion.moveCurve,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: morph,
          switchInCurve: NexMotion.curve,
          switchOutCurve: NexMotion.exitCurve,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.94, end: 1).animate(animation),
              child: child,
            ),
          ),
          // Sized by what is arriving; what is leaving fades over it,
          // clipped, rather than holding the box at the larger of the two.
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topCenter,
            children: [
              for (final leaving in previous)
                Positioned(left: 0, right: 0, top: 0, child: leaving),
              ?current,
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The recorder the box turns into: the time, the pulse, and the voice as
/// it is heard.
class _ComposerRecorder extends StatefulWidget {
  const _ComposerRecorder({
    super.key,
    required this.recorder,
    required this.watch,
    required this.color,
  });

  /// Null while the microphone is still being asked for.
  final AudioRecorder? recorder;
  final Stopwatch watch;
  final Color color;

  @override
  State<_ComposerRecorder> createState() => _ComposerRecorderState();
}

class _ComposerRecorderState extends State<_ComposerRecorder> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _elapsed(BuildContext context) {
    final elapsed = widget.watch.elapsed;
    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return nexDigits(
      '$minutes:$seconds',
      persian: Localizations.localeOf(context).languageCode == 'fa',
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final elapsed = _elapsed(context);
    final recorder = widget.recorder;
    return SizedBox(
      height: 112,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: NexSpacing.sm),
          Row(
            children: [
              const NexRecordingDot(),
              const SizedBox(width: NexSpacing.sm),
              Semantics(
                liveRegion: true,
                label: l10n.recordingElapsed(elapsed),
                child: ExcludeSemantics(
                  child: Text(
                    elapsed,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Text(
                l10n.captureRecording,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: NexSpacing.sm),
          Expanded(
            child: recorder == null
                // Asking for the microphone: the line the voice will rise
                // from, not an empty box.
                ? Center(
                    child: Container(
                      height: 2,
                      decoration: BoxDecoration(
                        color: widget.color.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(NexRadius.xs),
                      ),
                    ),
                  )
                : NexLiveWaveform(recorder: recorder, color: widget.color),
          ),
          const SizedBox(height: NexSpacing.sm),
        ],
      ),
    );
  }
}

/// The line under the box: what the words will become, in so many words.
///
/// The count of a list's items; for a link, the site it will open — or that
/// it is not a link yet, or a Paste button while the box is empty; for a
/// note, the hint that holding Send schedules it.
class _ComposerFootnote extends StatelessWidget {
  const _ComposerFootnote({
    required this.kind,
    required this.text,
    required this.scheduleHint,
    required this.onPaste,
  });

  final CaptureKind kind;
  final String text;
  final bool scheduleHint;
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final quiet = theme.textTheme.labelMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final tint = nexNoteTypeTint(_wire(kind), scheme);
    final trimmed = text.trim();
    final (String, Widget)? line = switch (kind) {
      CaptureKind.note when scheduleHint => (
        'hint',
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Text(
            l10n.scheduleHint,
            key: const ValueKey('schedule-hint'),
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
      CaptureKind.checklist when parseChecklist(text).isNotEmpty => (
        'items',
        Row(
          children: [
            Icon(Icons.checklist_rtl_outlined, size: 16, color: tint),
            const SizedBox(width: NexSpacing.xs),
            Text(
              l10n.checklistItemCount(parseChecklist(text).length),
              style: quiet,
            ),
          ],
        ),
      ),
      CaptureKind.link when trimmed.isEmpty => (
        'paste',
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: onPaste,
            icon: const Icon(Icons.content_paste, size: 18),
            label: Text(MaterialLocalizations.of(context).pasteButtonLabel),
          ),
        ),
      ),
      CaptureKind.link => switch (writtenLink(trimmed)) {
        final link? => (
          'host',
          Row(
            children: [
              Icon(Icons.public, size: 16, color: tint),
              const SizedBox(width: NexSpacing.xs),
              Flexible(
                child: Text(
                  [?urlHost(link.url), ?link.words].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: quiet,
                ),
              ),
            ],
          ),
        ),
        null => (
          'invalid',
          Text(
            l10n.linkNotValid,
            style: theme.textTheme.labelMedium?.copyWith(color: scheme.error),
          ),
        ),
      },
      _ => null,
    };
    final standard = NexMotion.of(context, NexMotion.standard);
    return AnimatedSize(
      duration: standard,
      curve: NexMotion.curve,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: standard,
        child: line == null
            ? const SizedBox(width: double.infinity)
            : Padding(
                key: ValueKey(line.$1),
                padding: const EdgeInsetsDirectional.only(
                  top: NexSpacing.xs,
                  start: NexSpacing.sm,
                ),
                child: line.$2,
              ),
      ),
    );
  }
}

/// Media actions, each in the same type colour used in Settings.
class _Tool extends StatelessWidget {
  const _Tool({
    required this.icon,
    required this.label,
    required this.type,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final String type;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: IconButton(
      tooltip: label,
      constraints: const BoxConstraints.tightFor(
        width: nexMinTapTarget,
        height: nexMinTapTarget,
      ),
      onPressed: onTap,
      style: IconButton.styleFrom(
        foregroundColor: nexNoteTypeTint(type, Theme.of(context).colorScheme),
        backgroundColor: selected
            ? nexNoteTypeTint(
                type,
                Theme.of(context).colorScheme,
              ).withValues(alpha: 0.16)
            : null,
      ),
      icon: Icon(icon, size: 22),
    ),
  );
}

/// Beside Send: the reminder while writing, the bin while recording.
class _SideAction extends StatelessWidget {
  const _SideAction({
    required this.recording,
    required this.canRemind,
    required this.hasReminder,
    required this.onRemind,
    required this.onDiscard,
  });

  final bool recording;
  final bool canRemind;
  final bool hasReminder;
  final VoidCallback onRemind;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    const tight = BoxConstraints.tightFor(
      width: nexMinTapTarget,
      height: nexMinTapTarget,
    );
    return AnimatedSwitcher(
      duration: NexMotion.of(context, NexMotion.pop),
      switchInCurve: NexMotion.popCurve,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: animation, child: child),
      ),
      child: recording
          ? IconButton(
              key: const ValueKey('capture-discard'),
              constraints: tight,
              onPressed: onDiscard,
              tooltip: l10n.discard,
              icon: Icon(Icons.delete_outline, size: 22, color: scheme.error),
            )
          : IconButton(
              key: const ValueKey('capture-remind'),
              constraints: tight,
              onPressed: canRemind ? onRemind : null,
              tooltip: l10n.remind,
              icon: Icon(
                hasReminder ? Icons.alarm_on : Icons.alarm_add_outlined,
                size: 20,
                color: hasReminder ? scheme.primary : null,
              ),
            ),
    );
  }
}

/// Send — or, while recording, Stop, which keeps the recording. Held in a
/// note, it schedules.
class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.kind,
    required this.closing,
    required this.onSend,
    required this.onSchedule,
  });

  final CaptureKind kind;
  final bool closing;
  final VoidCallback? onSend;
  final VoidCallback? onSchedule;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final voice = kind == CaptureKind.voice;
    // Tap sends; hold schedules. The tooltip keeps its label for screen
    // readers and tests but no longer claims the hold, which belongs to
    // scheduling.
    return Semantics(
      onLongPressHint: onSchedule == null ? null : l10n.scheduleTitle,
      child: GestureDetector(
        key: const ValueKey('capture-send'),
        onLongPress: onSchedule,
        child: TooltipTheme(
          data: const TooltipThemeData(triggerMode: TooltipTriggerMode.manual),
          child: IconButton.filled(
            // The primary action stays anchored at the end of the row; the
            // quieter actions keep a full 48px touch target beside it.
            constraints: const BoxConstraints.tightFor(width: 60, height: 60),
            onPressed: onSend,
            tooltip: voice ? l10n.stopRecording : l10n.capture,
            icon: closing
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : AnimatedSwitcher(
                    duration: NexMotion.of(context, NexMotion.pop),
                    switchInCurve: NexMotion.popCurve,
                    transitionBuilder: (child, animation) => RotationTransition(
                      turns: Tween<double>(
                        begin: -0.25,
                        end: 0,
                      ).animate(animation),
                      child: ScaleTransition(scale: animation, child: child),
                    ),
                    child: Icon(
                      voice ? Icons.stop_rounded : Icons.arrow_upward,
                      key: ValueKey(voice),
                      size: 32,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
