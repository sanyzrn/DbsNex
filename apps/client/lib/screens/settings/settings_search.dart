part of '../settings_sheet.dart';

/// One labelled group of preferences, drawn as a card.
///
/// The label lost the icon it used to carry. With every row inside the card
/// now leading with an icon tile of its own, a seventh icon floating above
/// them was the one that meant least and drew the most.
/// A row that is not a [_Row] or [_SwitchRow], with the words Settings
/// search should find it by.
class _Searchable extends StatelessWidget {
  const _Searchable({required this.text, required this.child});

  final String text;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// The words a settings row can be found by (W6.6).
String _searchTextOf(Widget row) => switch (row) {
  _Row(:final title, :final value, :final keywords) =>
    '$title ${value ?? ''} $keywords',
  _SwitchRow(:final title, :final subtitle) => '$title ${subtitle ?? ''}',
  _Searchable(:final text) => text,
  _ => '',
};

/// Case- and space-insensitive, and the same for Persian's two forms of
/// yeh and kaf, so a query typed on either keyboard finds the row.
String _fold(String text) => text
    .toLowerCase()
    .replaceAll('ي', 'ی')
    .replaceAll('ك', 'ک')
    .replaceAll('\u200c', '')
    .replaceAll(RegExp(r'\s+'), ' ');

/// Holds the search field and what is typed in it, so the sheet around it can
/// stay stateless.
class _SettingsSearch extends StatefulWidget {
  const _SettingsSearch({required this.builder});

  final Widget Function(BuildContext context, String query, Widget field)
  builder;

  @override
  State<_SettingsSearch> createState() => _SettingsSearchState();
}

class _SettingsSearchState extends State<_SettingsSearch> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final field = Padding(
      padding: const EdgeInsets.fromLTRB(
        NexSpacing.md,
        0,
        NexSpacing.md,
        NexSpacing.sm,
      ),
      child: NexAutoDirection(
        controller: _controller,
        builder: (context, direction) => TextField(
          controller: _controller,
          focusNode: _focus,
          textDirection: direction,
          textAlign: TextAlign.start,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search),
            hintText: nexLabel(
              context,
              'Search settings',
              'جست‌وجو در تنظیمات',
            ),
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: l10n.closeLabel,
                    icon: const Icon(Icons.close),
                    onPressed: _controller.clear,
                  ),
          ),
        ),
      ),
    );
    // The one field where a touch outside it, while typing, only closes the
    // keyboard (ADR-038): under it is a sheet of switches.
    return NexGuardedField(
      focusNode: _focus,
      child: widget.builder(context, _controller.text.trim(), field),
    );
  }
}
