import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

/// One option in a [NexChoiceCards] row.
class NexChoice<T> {
  const NexChoice({
    required this.value,
    required this.label,
    required this.preview,
  });

  final T value;
  final String label;

  /// A small visual that shows what the option *is*, not what it is called.
  /// A colour scheme is easier to recognise than the word "Dark", and a
  /// language is easier to recognise in its own script than in English.
  final Widget preview;
}

/// A row of cards, one of which is selected.
///
/// This replaces the dropdown menus that used to live in Settings. A dropdown
/// hides every option but one behind a tap, gives no sense of what choosing
/// does, and — for something like a language, where the whole point is to
/// recognise your own — is exactly the wrong control. Cards show all of the
/// choices at once and let each one show itself.
class NexChoiceCards<T> extends StatelessWidget {
  const NexChoiceCards({
    super.key,
    required this.choices,
    required this.selected,
    required this.onSelected,
  });

  final List<NexChoice<T>> choices;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => choices.length <= 3
      ? _row()
      : LayoutBuilder(
          builder: (context, constraints) {
            final columns = choices.length == 4 ? 2 : 3;
            final width =
                (constraints.maxWidth - NexSpacing.sm * (columns - 1)) /
                columns;
            return Wrap(
              spacing: NexSpacing.sm,
              runSpacing: NexSpacing.sm,
              children: [
                for (var i = 0; i < choices.length; i++)
                  SizedBox(width: width, child: _card(i)),
              ],
            );
          },
        );

  Widget _row() => IntrinsicHeight(
    // The cards have to be the same height whatever their labels wrap to,
    // and this row lives inside a scroll view, so "stretch" alone would ask
    // for infinite height.
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < choices.length; i++) ...[
          if (i > 0) const SizedBox(width: NexSpacing.sm),
          Expanded(child: _card(i)),
        ],
      ],
    ),
  );

  Widget _card(int index) => _Card<T>(
    choice: choices[index],
    isSelected: choices[index].value == selected,
    onTap: () {
      if (choices[index].value == selected) return;
      nexTick();
      onSelected(choices[index].value);
    },
  );
}

class _Card<T> extends StatelessWidget {
  const _Card({
    required this.choice,
    required this.isSelected,
    required this.onTap,
  });

  final NexChoice<T> choice;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Semantics(
      button: true,
      selected: isSelected,
      label: choice.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(NexRadius.lg),
        child: AnimatedContainer(
          duration: NexMotion.standard,
          curve: NexMotion.curve,
          padding: const EdgeInsets.symmetric(
            vertical: NexSpacing.contentGap,
            horizontal: NexSpacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(NexRadius.lg),
            color: isSelected
                ? accent.withValues(alpha: 0.06)
                : theme.colorScheme.surface,
            border: Border.all(
              color: isSelected ? accent : theme.colorScheme.outline,
              width: isSelected ? 1.6 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              choice.preview,
              const SizedBox(height: NexSpacing.sm),
              Text(
                choice.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isSelected ? accent : theme.colorScheme.secondary,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A miniature of what a theme actually looks like.
///
/// Two bars on a background, in that theme's own colours — the same trick the
/// system theme pickers use, and the reason it reads instantly.
class NexThemeSwatch extends StatelessWidget {
  const NexThemeSwatch({super.key, required this.mode, required this.comfort});

  final ThemeMode mode;
  final bool comfort;

  @override
  Widget build(BuildContext context) {
    final system = MediaQuery.platformBrightnessOf(context);
    final dark = switch (mode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => system == Brightness.dark,
    };
    final scheme =
        (dark
                ? nexDarkTheme(comfortMode: comfort)
                : nexLightTheme(comfortMode: comfort))
            .colorScheme;
    Widget bar(double width, double opacity) => Container(
      width: width,
      height: 3,
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(2),
      ),
    );
    final preview = Container(
      width: 46,
      height: 34,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: scheme.outline),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [bar(24, 0.85), const SizedBox(height: 4), bar(16, 0.4)],
      ),
    );
    if (mode != ThemeMode.system) return preview;
    // "System" is neither one nor the other, so it shows both: the light half
    // is drawn over the dark one and clipped down the diagonal.
    return SizedBox(
      width: 46,
      height: 34,
      child: Stack(
        children: [
          preview,
          ClipPath(
            clipper: _DiagonalClipper(),
            child: Container(
              width: 46,
              height: 34,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color:
                    (dark
                            ? nexLightTheme(comfortMode: comfort)
                            : nexDarkTheme(comfortMode: comfort))
                        .colorScheme
                        .surface,
                borderRadius: BorderRadius.circular(9),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagonalClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..moveTo(size.width, 0)
    ..lineTo(size.width, size.height)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// A language shown in its own script.
///
/// "Persian" written in English tells a Persian speaker nothing they need; the
/// glyph does. The circle keeps the three cards the same shape whether the
/// sample is one letter or two.
class NexScriptSample extends StatelessWidget {
  const NexScriptSample({super.key, this.sample, this.icon});

  final String? sample;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: icon != null
          ? Icon(icon, size: 20, color: theme.colorScheme.onSurface)
          : Text(
              sample!,
              style: theme.textTheme.titleMedium?.copyWith(height: 1),
            ),
    );
  }
}
