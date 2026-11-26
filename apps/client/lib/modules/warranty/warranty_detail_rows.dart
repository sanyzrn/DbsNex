part of 'warranty_detail.dart';

/// The purchase page's field rows: one icon, one label, one value — and
/// the copy action a value that is dictated over a phone gets.
extension _WarrantyDetailRows on _WarrantyDetailPageState {
  /// A label above a value, with the icon the field has everywhere else in
  /// the module, so a row is recognised before it is read.
  Widget _row(
    BuildContext context,
    IconData icon,
    String label,
    Widget value, {
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NexSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: NexSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                value,
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  /// The copy action a dictated value gets: the serial, the card number
  /// and the invoice are read out over a phone, so each is one tap from
  /// the clipboard — the support line already had one.
  Widget _copyValue(BuildContext context, String key, String value) {
    final l10n = AppLocalizations.of(context);
    return IconButton(
      key: ValueKey(key),
      tooltip: l10n.copy,
      icon: const Icon(Icons.copy_outlined),
      onPressed: () => unawaited(_copyValueToClipboard(value)),
    );
  }

  Future<void> _copyValueToClipboard(String value) async {
    await nexModuleCopyText(value);
    if (!mounted) return;
    nexShowBanner(context, message: warrantyStrings(context, 'valueCopied'));
  }
}
