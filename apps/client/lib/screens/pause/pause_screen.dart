import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart' show nexDigits;
import 'package:nex_ui/nex_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../platform/nex_preferences.dart';
import '../../widgets/settings_group.dart';
import 'pause_art.dart';
import 'pause_patterns.dart';
import 'pause_session.dart';

/// Pause's own page: the three breathing breaks side by side, what each one
/// is for, and the two things a session can do besides move — sound and
/// taps.
///
/// Swipe to a mode and start it, or tap the card in the middle.
class PauseScreen extends StatefulWidget {
  const PauseScreen({super.key, required this.preferences});

  final NexPreferences preferences;

  @override
  State<PauseScreen> createState() => _PauseScreenState();
}

class _PauseScreenState extends State<PauseScreen> {
  late PauseMode _mode = PauseMode.fromId(widget.preferences.pauseMode);
  late final PageController _pages = PageController(
    viewportFraction: 0.58,
    initialPage: _mode.index,
  );

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _select(int index) {
    setState(() => _mode = PauseMode.values[index]);
    unawaited(widget.preferences.setPauseMode(_mode.id));
  }

  Future<void> _start() => Navigator.push(
    context,
    NexPageRoute<void>(
      builder: (_) =>
          PauseSession(mode: _mode, preferences: widget.preferences),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = Localizations.localeOf(context).languageCode == 'fa';
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    return Scaffold(
      appBar: NexAppBar(title: Text(l10n.pauseTitle)),
      body: ListenableBuilder(
        listenable: widget.preferences,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(bottom: NexSpacing.xl),
          children: [
            const SizedBox(height: NexSpacing.lg),
            SizedBox(
              height: 230,
              child: PageView.builder(
                key: const ValueKey('pause-modes'),
                controller: _pages,
                itemCount: PauseMode.values.length,
                onPageChanged: _select,
                itemBuilder: (context, index) {
                  final mode = PauseMode.values[index];
                  final chosen = mode == _mode;
                  return AnimatedScale(
                    scale: chosen ? 1 : 0.86,
                    duration: NexMotion.of(context, NexMotion.standard),
                    curve: NexMotion.curve,
                    child: AnimatedOpacity(
                      opacity: chosen ? 1 : 0.6,
                      duration: NexMotion.of(context, NexMotion.standard),
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: _ModeCard(
                            mode: mode,
                            name: _name(l10n, mode),
                            onTap: () => chosen
                                ? unawaited(_start())
                                : unawaited(
                                    _pages.animateToPage(
                                      index,
                                      duration: NexMotion.of(
                                        context,
                                        NexMotion.standard,
                                      ),
                                      curve: NexMotion.curve,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: NexSpacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: NexSpacing.lg),
              child: AnimatedSwitcher(
                duration: NexMotion.of(context, NexMotion.standard),
                child: Column(
                  key: ValueKey(_mode),
                  children: [
                    Text(
                      _forName(l10n, _mode),
                      style: theme.textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: NexSpacing.xs),
                    Text(
                      l10n.pauseRhythm(
                        nexDigits(_mode.rhythm, persian: persian),
                        nexDigits('${_mode.rounds}', persian: persian),
                        pauseLength(_mode.sessionDuration, persian: persian),
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: NexSpacing.xs),
                    Text(
                      _about(l10n, _mode),
                      style: muted,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: NexSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final mode in PauseMode.values)
                  AnimatedContainer(
                    duration: NexMotion.of(context, NexMotion.standard),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: mode == _mode ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: mode == _mode
                          ? scheme.primary
                          : scheme.onSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(NexRadius.pill),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: NexSpacing.lg),
            Center(
              child: FilledButton.icon(
                key: const ValueKey('pause-start'),
                onPressed: () => unawaited(_start()),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(l10n.pauseStart),
              ),
            ),
            const SizedBox(height: NexSpacing.xl),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: NexSpacing.md),
              child: NexSettingsGroup(
                title: l10n.settings,
                children: [
                  NexSwitchTile(
                    key: const ValueKey('pause-sound-setting'),
                    secondary: const Icon(Icons.music_note_outlined),
                    title: Text(l10n.pauseSound),
                    subtitle: Text(l10n.pauseSoundAbout),
                    value: widget.preferences.pauseSound,
                    onChanged: widget.preferences.setPauseSound,
                  ),
                  NexSwitchTile(
                    key: const ValueKey('pause-haptics-setting'),
                    secondary: const Icon(Icons.vibration),
                    title: Text(l10n.pauseHaptics),
                    subtitle: Text(l10n.pauseHapticsAbout),
                    value: widget.preferences.pauseHaptics,
                    onChanged: widget.preferences.setPauseHaptics,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _name(AppLocalizations l10n, PauseMode mode) => switch (mode) {
  PauseMode.calm => l10n.pauseModeCalm,
  PauseMode.focus => l10n.pauseModeFocus,
  PauseMode.relax => l10n.pauseModeRelax,
};

String _forName(AppLocalizations l10n, PauseMode mode) => switch (mode) {
  PauseMode.calm => l10n.pauseForCalm,
  PauseMode.focus => l10n.pauseForFocus,
  PauseMode.relax => l10n.pauseForRelax,
};

String _about(AppLocalizations l10n, PauseMode mode) => switch (mode) {
  PauseMode.calm => l10n.pauseAboutCalm,
  PauseMode.focus => l10n.pauseAboutFocus,
  PauseMode.relax => l10n.pauseAboutRelax,
};

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.name,
    required this.onTap,
  });

  final PauseMode mode;
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: name,
    excludeSemantics: true,
    child: GestureDetector(
      key: ValueKey('pause-card-${mode.id}'),
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(NexRadius.xl * 1.5),
        child: Stack(
          fit: StackFit.expand,
          children: [
            PauseModeArt(mode: mode),
            PositionedDirectional(
              top: NexSpacing.md,
              start: NexSpacing.md,
              child: Text(
                name,
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
