import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';

/// The opaque sheet the lock gate paints over the app.
///
/// Named so a test can find it and check that it is still opaque — which is
/// the whole of the bug it exists for.
@visibleForTesting
const appLockBarrierKey = Key('nex.app-lock-barrier');

/// The gate itself: the padlock, why it is closed, and the way through.
class AppLockGate extends StatelessWidget {
  const AppLockGate({
    super.key,
    required this.busy,
    required this.onUnlock,
    this.error,
    required this.onSettings,
  });
  final String? error;
  final VoidCallback onSettings;

  final bool busy;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // Its own colour, not the theme's scaffold background, and forced opaque.
    //
    // `scaffoldBackgroundColor` is `Colors.transparent` whenever liquid glass
    // or a background pattern is on — deliberately, so the app's backdrop
    // shows through every screen — and a bare `Scaffold` here inherited that.
    // The result was a lock gate you could read the timeline through while it
    // waited for a fingerprint: every note on screen, behind the prompt that
    // was supposedly hiding them.
    //
    // `canvasColor` is the page background with no glass applied, which is the
    // right shade; the alpha is pinned anyway so that no future theme can make
    // this see-through again without failing a test.
    final barrier = theme.canvasColor.withValues(alpha: 1);
    return Scaffold(
      key: appLockBarrierKey,
      backgroundColor: barrier,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(NexSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline,
                size: 56,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: NexSpacing.md),
              Text(
                l10n.securityLockedTitle,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: NexSpacing.sm),
              Text(
                error ?? l10n.securityLockedSubtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: NexSpacing.lg),
              FilledButton.icon(
                onPressed: busy ? null : onUnlock,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.fingerprint),
                label: Text(l10n.securityUnlock),
              ),
              if (error != null)
                TextButton(onPressed: onSettings, child: Text(l10n.settings)),
            ],
          ),
        ),
      ),
    );
  }
}
