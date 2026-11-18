part of '../onboarding_screen.dart';

/// The modules a first run can offer: the ones available on this phone,
/// except Cycle, which asks its own questions when it is added from Tools.
List<NexModule> _onboardingModules() => [
  for (final module in nexModules)
    if (module.available && module.id != 'cycle') module,
];

/// The page that says Nex has small tools beside the notes (2.8.4), and lets
/// someone add any of them on the spot. Each chip saves as it is tapped, the
/// way the setup page's choices do, and each is one tap to remove in Tools.
class _ModulesPage extends StatelessWidget {
  const _ModulesPage({
    required this.active,
    required this.preferences,
    required this.modules,
  });

  final bool active;
  final NexPreferences preferences;
  final List<NexModule> modules;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _StoryPage(
      active: active,
      art: (play) => _ModulesArt(play: play, modules: modules),
      title: l10n.onboardingModulesTitle,
      body: l10n.onboardingModulesBody,
      artShare: 0.3,
      footer: ListenableBuilder(
        listenable: preferences,
        builder: (context, _) => Wrap(
          alignment: WrapAlignment.center,
          spacing: NexSpacing.sm,
          runSpacing: NexSpacing.sm,
          children: [
            for (final module in modules)
              _ModuleChoice(
                module: module,
                on: module.isOn(preferences),
                onChanged: (on) => preferences.setModuleOn(module.id, on),
              ),
          ],
        ),
      ),
    );
  }
}

class _ModuleChoice extends StatelessWidget {
  const _ModuleChoice({
    required this.module,
    required this.on,
    required this.onChanged,
  });

  final NexModule module;
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final color = module.hue.of(theme.brightness);
    return FilterChip(
      key: ValueKey('onboarding-module-${module.id}'),
      avatar: on ? null : Icon(module.icon, size: 18, color: color),
      label: Text(module.title(l10n)),
      tooltip: module.tagline(l10n),
      selected: on,
      selectedColor: color.withValues(alpha: 0.18),
      checkmarkColor: color,
      side: BorderSide(color: color.withValues(alpha: on ? 0.6 : 0.3)),
      onSelected: onChanged,
    );
  }
}

/// Tiles in the modules' own colours settling into a grid around a "+" —
/// the shape of the Tools page, filling in.
class _ModulesArt extends _Art {
  const _ModulesArt({required super.play, required this.modules});

  final List<NexModule> modules;

  @override
  Duration get duration => const Duration(milliseconds: 1800);

  @override
  State<_ModulesArt> createState() => _ModulesArtState();
}

class _ModulesArtState extends _ArtState<_ModulesArt> {
  static const _tile = 58.0;
  static const _gap = 12.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Eight around the middle, in the order Tools lists them.
    final shown = widget.modules.take(8).toList();
    NexModule? at(int i) {
      if (i == 4) return null;
      final k = i < 4 ? i : i - 1;
      return k < shown.length ? shown[k] : null;
    }

    return _Panel(
      child: Padding(
        padding: const EdgeInsets.all(NexSpacing.sm),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => SizedBox(
              width: _tile * 3 + _gap * 2,
              child: Wrap(
                spacing: _gap,
                runSpacing: _gap,
                children: [for (var i = 0; i < 9; i++) _cell(i, at(i), scheme)],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cell(int i, NexModule? module, ColorScheme scheme) {
    final brightness = Theme.of(context).brightness;
    final centre = i == 4;
    // The "+" first, then the tiles one after another around it.
    final order = centre ? 0 : (i < 4 ? i + 1 : i);
    final t = span(order * 0.08, order * 0.08 + 0.36, Curves.easeOutBack);
    final color = module?.hue.of(brightness) ?? scheme.primary;
    final Widget face = centre
        ? Icon(Icons.add_rounded, color: scheme.onPrimary, size: 28)
        : module != null
        ? Icon(module.icon, color: color, size: 26)
        : const SizedBox.shrink();
    return Opacity(
      opacity: t.clamp(0.0, 1.0),
      child: Transform.scale(
        scale: 0.6 + 0.4 * t,
        child: Container(
          width: _tile,
          height: _tile,
          decoration: BoxDecoration(
            color: centre
                ? scheme.primary
                : color.withValues(alpha: module == null ? 0.05 : 0.16),
            borderRadius: BorderRadius.circular(NexRadius.md + 4),
            border: centre
                ? null
                : Border.all(color: color.withValues(alpha: 0.28)),
          ),
          child: Center(child: face),
        ),
      ),
    );
  }
}
