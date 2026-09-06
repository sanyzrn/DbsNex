import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nex_data/nex_data.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/nex_preferences.dart';
import 'nex_dialog.dart';

/// Picks a tag's accent colour — and, with [defaultColor] set, the app's.
///
/// The shipped swatches are kept because they are tuned to the design system
/// and cover the common cases in one tap. Under them is the whole spectrum,
/// because the point of a tag colour (ADR-021) is that the user encodes
/// *their* meaning — red for urgent, grey for later — and a fixed set of five
/// cannot express a meaning it did not anticipate.
///
/// The spectrum used to be three sliders: hue, saturation, brightness. They
/// were correct and unusable. Nobody picking a colour is making three
/// independent decisions — they know the colour they want and are looking for
/// it, which on sliders means moving one, seeing what happened, and moving the
/// next. A disc lays the same space out so all of it is visible and any point
/// in it is one gesture away. Brightness stays a slider because a flat disc
/// has nowhere to put a third axis.
class TagColorPicker extends StatefulWidget {
  const TagColorPicker({
    super.key,
    this.initial,
    this.title,
    this.preferences,
    this.defaultColor,
  });

  final String? initial;

  /// Overrides the sheet's own heading, normally "Tag color" — the accent
  /// picker in Settings reuses this whole widget rather than duplicating it,
  /// and needs its own heading to say what it is actually choosing.
  final String? title;

  /// Where the recently-used row is read from and written back to. Optional:
  /// a picker with no preferences simply does not offer one, which is what
  /// the widget tests want.
  final NexPreferences? preferences;

  /// What "no colour" actually means here.
  ///
  /// A tag can genuinely have no colour, so the escape hatch is a crossed-out
  /// dot. An app accent cannot — something is always drawing the caret — so
  /// there the same swatch means "back to the shipped default", and was
  /// showing an empty circle labelled "No colour" for a choice that is
  /// neither. Passing the default colour makes it paint that colour and say
  /// so; both still resolve to null, which is what clears the stored value.
  final Color? defaultColor;

  /// Resolves to the chosen `#RRGGBB`, or to null for "no colour" / "the
  /// default". Dismissing resolves to nothing at all, which the caller must
  /// not confuse with clearing the colour.
  static Future<({String? color})?> show(
    BuildContext context, {
    String? initial,
    String? title,
    NexPreferences? preferences,
    Color? defaultColor,
  }) => nexShowSheet<({String? color})>(
    context: context,
    builder: (_) => TagColorPicker(
      initial: initial,
      title: title,
      preferences: preferences,
      defaultColor: defaultColor,
    ),
  );

  @override
  State<TagColorPicker> createState() => _TagColorPickerState();
}

class _TagColorPickerState extends State<TagColorPicker> {
  late double _hue;
  late double _saturation;
  late double _value;
  late String? _selected = widget.initial;
  late final TextEditingController _hexField;
  late final List<String> _recents;

  @override
  void initState() {
    super.initState();
    final start = nexParseTagColor(widget.initial) ?? const Color(0xFF5B9BF0);
    final hsv = HSVColor.fromColor(start);
    _hue = hsv.hue;
    _saturation = hsv.saturation == 0 ? 0.65 : hsv.saturation;
    _value = hsv.value;
    _hexField = TextEditingController(text: _selected ?? '');
    // Read once. The row is a record of what was picked before this sheet
    // opened; having it reshuffle under the finger as colours are tried would
    // make it a moving target.
    _recents = List.of(widget.preferences?.recentColors ?? const []);
  }

  @override
  void dispose() {
    _hexField.dispose();
    super.dispose();
  }

  String get _hex {
    final color = HSVColor.fromAHSV(1, _hue, _saturation, _value).toColor();
    final rgb = color.toARGB32() & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  /// [syncField] is false only when the change came *from* the field:
  /// rewriting the text someone is in the middle of typing sends the caret
  /// back to the start after every character.
  void _pickColor(String hex, {bool syncField = true}) {
    final hsv = HSVColor.fromColor(nexParseTagColor(hex)!);
    setState(() {
      _selected = hex;
      _hue = hsv.hue;
      _saturation = hsv.saturation;
      _value = hsv.value;
      if (syncField) _hexField.text = hex;
    });
  }

  void _clear() => setState(() {
    _selected = null;
    _hexField.text = '';
  });

  void _slide(void Function() apply) {
    setState(() {
      apply();
      _selected = _hex;
      _hexField.text = _selected!;
    });
  }

  /// Accepts what someone actually pastes: with or without the `#`, in any
  /// case.
  ///
  /// Applied as it is typed, so the disc and the slider follow the sixth
  /// character rather than waiting for a keyboard someone may just dismiss.
  /// A half-typed value is simply not a colour yet and changes nothing — the
  /// sheet keeps what it had rather than blanking on the way to a value.
  String? _parseHex(String raw) {
    final trimmed = raw.trim();
    final hex = trimmed.startsWith('#') ? trimmed : '#$trimmed';
    return isTagAccent(hex) ? hex.toUpperCase() : null;
  }

  void _typedHex(String raw) {
    final hex = _parseHex(raw);
    if (hex != null) _pickColor(hex, syncField: false);
  }

  /// Committing puts the field back in step with the colour: a stray
  /// character or an abandoned edit should not leave the text saying one
  /// thing and the swatch another.
  void _submitHex(String raw) {
    final hex = _parseHex(raw);
    if (hex == null) {
      _hexField.text = _selected ?? '';
      return;
    }
    _pickColor(hex);
  }

  Future<void> _save() async {
    final chosen = _selected;
    if (chosen != null) await widget.preferences?.rememberColor(chosen);
    if (!mounted) return;
    Navigator.pop(context, (color: chosen));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final preview = nexParseTagColor(_selected) ?? widget.defaultColor;
    // The recents worth showing are the ones the swatch row does not already
    // offer — a second copy of the same five teaches nothing.
    final recents = _recents
        .where(
          (hex) => !tagAccentPalette.any(
            (shipped) => shipped.toUpperCase() == hex.toUpperCase(),
          ),
        )
        .toList();
    // The disc is square and a phone is not: on a narrow screen it takes the
    // width it is given rather than overflowing it.
    final wheel = math.min(
      240.0,
      MediaQuery.sizeOf(context).width - NexSpacing.lg * 2,
    );
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: NexSpacing.lg,
        right: NexSpacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + NexSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.title ?? l10n.tagColor,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: NexSpacing.lg),
          Center(
            child: NexColorWheel(
              hue: _hue,
              saturation: _saturation,
              value: _value,
              diameter: wheel,
              semanticLabel: l10n.customColor,
              onChanged: (hue, saturation) => _slide(() {
                _hue = hue;
                _saturation = saturation;
              }),
            ),
          ),
          const SizedBox(height: NexSpacing.lg),
          _HexRow(
            controller: _hexField,
            preview: preview,
            onChanged: _typedHex,
            onSubmitted: _submitHex,
          ),
          const SizedBox(height: NexSpacing.md),
          Row(
            children: [
              // A glyph rather than the word it replaced: the track already
              // runs black to the chosen colour, which says what it does
              // better than "Brightness" did, and a label above every control
              // is what made the old three-slider stack read as a form.
              Icon(
                Icons.brightness_6_outlined,
                size: 20,
                color: theme.colorScheme.secondary,
                semanticLabel: l10n.brightness,
              ),
              Expanded(
                child: NexBrightnessSlider(
                  hue: _hue,
                  saturation: _saturation,
                  value: _value,
                  onChanged: (value) => _slide(() => _value = value),
                ),
              ),
            ],
          ),
          const SizedBox(height: NexSpacing.md),
          Wrap(
            spacing: NexSpacing.contentGap,
            runSpacing: NexSpacing.contentGap,
            children: [
              NexColorSwatch(
                color: widget.defaultColor,
                selected: _selected == null,
                // A tag with no colour has nothing to draw, so the dot says
                // so with a glyph. The app accent always has a colour, so its
                // swatch shows the one it would go back to.
                icon: widget.defaultColor == null ? Icons.block : null,
                semanticLabel: widget.defaultColor == null
                    ? l10n.noColor
                    : l10n.defaultColor,
                onTap: _clear,
              ),
              for (final hex in tagAccentPalette)
                NexColorSwatch(
                  color: nexParseTagColor(hex),
                  selected: _selected?.toUpperCase() == hex.toUpperCase(),
                  onTap: () => _pickColor(hex),
                ),
            ],
          ),
          if (recents.isNotEmpty) ...[
            const SizedBox(height: NexSpacing.lg),
            Text(l10n.recentColors, style: theme.textTheme.bodySmall),
            const SizedBox(height: NexSpacing.sm),
            Wrap(
              spacing: NexSpacing.contentGap,
              runSpacing: NexSpacing.contentGap,
              children: [
                for (final hex in recents)
                  NexColorSwatch(
                    color: nexParseTagColor(hex),
                    selected: _selected?.toUpperCase() == hex.toUpperCase(),
                    onTap: () => _pickColor(hex),
                  ),
              ],
            ),
          ],
          const SizedBox(height: NexSpacing.lg),
          FilledButton(onPressed: _save, child: Text(l10n.save)),
        ],
      ),
    );
  }
}

/// The chosen colour, as a swatch and as the six characters someone can copy
/// out or paste in.
///
/// Typed rather than only shown: a colour that has to match something outside
/// Nex — a brand, another app, a note somewhere — is known by its hex, and
/// hunting for it on a disc is guessing at a value you already have.
class _HexRow extends StatelessWidget {
  const _HexRow({
    required this.controller,
    required this.preview,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final Color? preview;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: preview ?? Colors.transparent,
            border: Border.all(color: theme.colorScheme.outline),
          ),
        ),
        const SizedBox(width: NexSpacing.contentGap),
        Expanded(
          child: TextField(
            controller: controller,
            // Always latin, whatever the interface language: a hex code is
            // not a word, and Persian digits are not one either.
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.center,
            textInputAction: TextInputAction.done,
            style: theme.textTheme.titleMedium,
            inputFormatters: [
              LengthLimitingTextInputFormatter(7),
              FilteringTextInputFormatter.allow(RegExp('[#0-9a-fA-F]')),
            ],
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(NexRadius.md),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: onChanged,
            onSubmitted: onSubmitted,
          ),
        ),
      ],
    );
  }
}
