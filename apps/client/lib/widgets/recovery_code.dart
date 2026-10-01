import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/private_clipboard.dart';

/// A recovery code shown so it can be kept: tap it, or its copy icon, and
/// it is on the clipboard — marked private the way the vault's values are,
/// so the system does not preview it.
///
/// It was selectable text, which on a phone meant a long-press, dragging
/// two handles across 44 characters and finding Copy in a menu — for the
/// one string that, lost, makes the backup unreadable.
class NexRecoveryCode extends StatefulWidget {
  const NexRecoveryCode(this.code, {super.key});

  final String code;

  @override
  State<NexRecoveryCode> createState() => _NexRecoveryCodeState();
}

class _NexRecoveryCodeState extends State<NexRecoveryCode> {
  bool _copied = false;
  Timer? _reset;

  Future<void> _copy() async {
    await PrivateClipboard.copy(widget.code);
    if (!mounted) return;
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      label: l10n.recoveryCodeCopy,
      excludeSemantics: true,
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(NexRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('recovery-code'),
          onTap: () => unawaited(_copy()),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              NexSpacing.md,
              NexSpacing.sm,
              NexSpacing.xs,
              NexSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.code,
                    textDirection: TextDirection.ltr,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: NexSpacing.xs),
                AnimatedSwitcher(
                  duration: NexMotion.standard,
                  child: Icon(
                    _copied ? Icons.check : Icons.copy_outlined,
                    key: ValueKey(_copied),
                    color: _copied ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: NexSpacing.sm),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
