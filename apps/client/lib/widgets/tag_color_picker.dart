import 'package:flutter/material.dart';
import 'package:nex_data/nex_data.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';

/// Picks a tag's accent colour.
///
/// The swatches are the ones that ship, kept because they are tuned to the
/// design system and cover the common cases in one tap. Below them is the full
/// spectrum, because the whole point of a tag colour (ADR-021) is that the user
/// encodes *their* meaning — red for urgent, grey for later — and a fixed set
/// of five cannot express a meaning it did not anticipate.
class TagColorPicker extends StatefulWidget {
  const TagColorPicker({super.key, this.initial});

  final String? initial;

  /// Resolves to the chosen `#RRGGBB`, or to null for "no colour". Dismissing
  /// resolves to nothing at all, which the caller must not confuse with
  /// clearing the colour.
  static Future<({String? color})?> show(
    BuildContext context, {
    String? initial,
  }) =>
      showModalBottomSheet<({String? color})>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => TagColorPicker(initial: initial),
      );

  @override
  State<TagColorPicker> createState() => _TagColorPickerState();
}

class _TagColorPickerState extends State<TagColorPicker> {
  late double _hue;
  late double _saturation;
  late double _value;
  late String? _selected = widget.initial;

  @override
  void initState() {
    super.initState();
    final start = nexParseTagColor(widget.initial) ?? const Color(0xFF5B9BF0);
    final hsv = HSVColor.fromColor(start);
    _hue = hsv.hue;
    _saturation = hsv.saturation == 0 ? 0.65 : hsv.saturation;
    _value = hsv.value;
  }

  String get _hex {
    final color = HSVColor.fromAHSV(1, _hue, _saturation, _value).toColor();
    final rgb = color.toARGB32() & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  void _pickSwatch(String hex) {
    final hsv = HSVColor.fromColor(nexParseTagColor(hex)!);
    setState(() {
      _selected = hex;
      _hue = hsv.hue;
      _saturation = hsv.saturation;
      _value = hsv.value;
    });
  }

  void _slide(void Function() apply) {
    setState(() {
      apply();
      _selected = _hex;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final preview = nexParseTagColor(_selected);
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: NexSpacing.lg,
        right: NexSpacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + NexSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(l10n.tagColor, style: theme.textTheme.titleLarge),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: preview ?? Colors.transparent,
                  border: Border.all(color: theme.colorScheme.outline),
                ),
              ),
            ],
          ),
          const SizedBox(height: NexSpacing.lg),
          Wrap(
            spacing: NexSpacing.contentGap,
            runSpacing: NexSpacing.contentGap,
            children: [
              _Swatch(
                color: null,
                selected: _selected == null,
                onTap: () => setState(() => _selected = null),
              ),
              for (final hex in tagAccentPalette)
                _Swatch(
                  color: nexParseTagColor(hex),
                  selected: _selected?.toUpperCase() == hex.toUpperCase(),
                  onTap: () => _pickSwatch(hex),
                ),
            ],
          ),
          const SizedBox(height: NexSpacing.lg),
          Text(l10n.customColor, style: theme.textTheme.bodySmall),
          const SizedBox(height: NexSpacing.sm),
          _HueSlider(
            hue: _hue,
            onChanged: (value) => _slide(() => _hue = value),
          ),
          _LabelledSlider(
            label: l10n.saturation,
            value: _saturation,
            gradient: [
              HSVColor.fromAHSV(1, _hue, 0, _value).toColor(),
              HSVColor.fromAHSV(1, _hue, 1, _value).toColor(),
            ],
            onChanged: (value) => _slide(() => _saturation = value),
          ),
          _LabelledSlider(
            label: l10n.brightness,
            value: _value,
            gradient: [
              Colors.black,
              HSVColor.fromAHSV(1, _hue, _saturation, 1).toColor(),
            ],
            onChanged: (value) => _slide(() => _value = value),
          ),
          const SizedBox(height: NexSpacing.sm),
          Text(
            _selected ?? l10n.noColor,
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: NexSpacing.lg),
          FilledButton(
            onPressed: () => Navigator.pop(context, (color: _selected)),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        // Full minimum tap target even though the dot is smaller.
        child: SizedBox(
          width: nexMinTapTarget,
          height: nexMinTapTarget,
          child: Center(
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color ?? theme.colorScheme.surface,
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.outline,
                  width: selected ? 3 : 1,
                ),
              ),
              child: color == null
                  ? Icon(
                      Icons.block,
                      size: 14,
                      color: theme.colorScheme.secondary,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _HueSlider extends StatelessWidget {
  const _HueSlider({required this.hue, required this.onChanged});

  final double hue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => _GradientSlider(
        value: hue / 360,
        colors: const [
          Color(0xFFFF0000),
          Color(0xFFFFFF00),
          Color(0xFF00FF00),
          Color(0xFF00FFFF),
          Color(0xFF0000FF),
          Color(0xFFFF00FF),
          Color(0xFFFF0000),
        ],
        onChanged: (value) => onChanged(value * 360),
      );
}

class _LabelledSlider extends StatelessWidget {
  const _LabelledSlider({
    required this.label,
    required this.value,
    required this.gradient,
    required this.onChanged,
  });

  final String label;
  final double value;
  final List<Color> gradient;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          _GradientSlider(
            value: value,
            colors: gradient,
            onChanged: onChanged,
          ),
        ],
      );
}

/// A slider whose track shows the values it selects between.
class _GradientSlider extends StatelessWidget {
  const _GradientSlider({
    required this.value,
    required this.colors,
    required this.onChanged,
  });

  final double value;
  final List<Color> colors;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      alignment: Alignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Container(
            height: 12,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              gradient: LinearGradient(colors: colors),
              border: Border.all(color: theme.colorScheme.outline),
            ),
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 12,
            activeTrackColor: Colors.transparent,
            inactiveTrackColor: Colors.transparent,
            thumbColor: Colors.white,
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
          ),
          child: Slider(value: value.clamp(0, 1), onChanged: onChanged),
        ),
      ],
    );
  }
}
