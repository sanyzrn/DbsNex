import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/app_lock.dart';
import '../platform/nex_preferences.dart';
import '../widgets/nex_banner.dart';
import '../widgets/nex_dialog.dart';

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key, required this.preferences});

  final NexPreferences preferences;

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  final _lock = AppLockService();
  bool _busy = false;

  Future<bool> _authenticate({required bool biometricOnly}) async {
    final l10n = AppLocalizations.of(context);
    final supported = biometricOnly
        ? await _lock.supportsBiometrics()
        : await _lock.supportsDeviceAuthentication();
    if (!mounted) return false;
    if (!supported) {
      nexShowBanner(
        context,
        message: biometricOnly
            ? l10n.securityBiometricUnavailable
            : l10n.securityPasscodeUnavailable,
        kind: NexBannerKind.failed,
      );
      return false;
    }
    return _lock.authenticate(
      reason: l10n.securityAuthenticateReason,
      biometricOnly: biometricOnly,
    );
  }

  Future<void> _setAppLock(bool value) async {
    setState(() => _busy = true);
    final authenticated = await _authenticate(
      biometricOnly: value ? false : widget.preferences.appLockBiometricOnly,
    );
    if (authenticated) await widget.preferences.setAppLockEnabled(value);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _setBiometric(bool value) async {
    setState(() => _busy = true);
    final authenticated = await _authenticate(
      biometricOnly: value || widget.preferences.appLockBiometricOnly,
    );
    if (authenticated) {
      await widget.preferences.setAppLockBiometricOnly(value);
    }
    if (mounted) setState(() => _busy = false);
  }

  /// The delays offered for [AppLockTiming.after].
  ///
  /// A list rather than a free-text field: the useful range is narrow, every
  /// value in it has an obvious name, and a box that accepts "0" or "99999"
  /// is a way to turn the lock off by accident.
  static const _graceChoices = [15, 30, 60, 120, 300, 900, 1800, 3600];

  String _timingLabel(AppLocalizations l10n) =>
      switch (widget.preferences.appLockTiming) {
        AppLockTiming.immediately => l10n.securityLockImmediately,
        AppLockTiming.after => l10n.securityLockAfter(
          _graceLabel(l10n, widget.preferences.appLockGraceSeconds),
        ),
        AppLockTiming.manual => l10n.securityLockManual,
      };

  String _graceLabel(AppLocalizations l10n, int seconds) => seconds < 60
      ? l10n.securityLockSeconds(seconds)
      : seconds < 3600
      ? l10n.securityLockMinutes(seconds ~/ 60)
      : l10n.securityLockHours(seconds ~/ 3600);

  Future<void> _pickTiming() async {
    final l10n = AppLocalizations.of(context);
    final picked = await nexShowSheet<AppLockTiming>(
      context: context,
      builder: (sheetContext) => _OptionSheet<AppLockTiming>(
        title: l10n.securityLockWhen,
        selected: widget.preferences.appLockTiming,
        options: [
          (AppLockTiming.immediately, l10n.securityLockImmediately,
              l10n.securityLockImmediatelyHint),
          (AppLockTiming.after, l10n.securityLockAfterTitle,
              l10n.securityLockAfterHint),
          (AppLockTiming.manual, l10n.securityLockManual,
              l10n.securityLockManualHint),
        ],
        onPicked: (value) => Navigator.pop(sheetContext, value),
      ),
    );
    if (picked == null) return;
    await widget.preferences.setAppLockTiming(picked);
  }

  Future<void> _pickGrace() async {
    final l10n = AppLocalizations.of(context);
    final picked = await nexShowSheet<int>(
      context: context,
      builder: (sheetContext) => _OptionSheet<int>(
        title: l10n.securityLockAfterTitle,
        selected: widget.preferences.appLockGraceSeconds,
        options: [
          for (final seconds in _graceChoices)
            (seconds, _graceLabel(l10n, seconds), null),
        ],
        onPicked: (value) => Navigator.pop(sheetContext, value),
      ),
    );
    if (picked == null) return;
    await widget.preferences.setAppLockGraceSeconds(picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.securityTitle)),
      body: AnimatedBuilder(
        animation: widget.preferences,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(NexSpacing.md),
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  NexSwitchTile(
                    secondary: const Icon(Icons.password_outlined),
                    title: Text(l10n.securityDevicePasscode),
                    subtitle: Text(l10n.securityDevicePasscodeSubtitle),
                    value: widget.preferences.appLockEnabled,
                    onChanged: _busy
                        ? null
                        : (value) => unawaited(_setAppLock(value)),
                  ),
                  const Divider(height: 1),
                  NexSwitchTile(
                    secondary: const Icon(Icons.fingerprint),
                    title: Text(l10n.securityBiometric),
                    subtitle: Text(l10n.securityBiometricSubtitle),
                    value: widget.preferences.appLockBiometricOnly,
                    onChanged: _busy
                        ? null
                        : (value) => unawaited(_setBiometric(value)),
                  ),
                  // Only under a lock that is actually on. When it is off,
                  // "lock immediately" and "lock never" describe the same
                  // nothing, and a row that cannot mean anything is a row
                  // that has to be read before it can be dismissed.
                  if (widget.preferences.appLockEnabled) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.timer_outlined),
                      title: Text(l10n.securityLockWhen),
                      subtitle: Text(_timingLabel(l10n)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => unawaited(_pickTiming()),
                    ),
                    if (widget.preferences.appLockTiming ==
                        AppLockTiming.after) ...[
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.hourglass_empty),
                        title: Text(l10n.securityLockAfterTitle),
                        subtitle: Text(
                          _graceLabel(
                            l10n,
                            widget.preferences.appLockGraceSeconds,
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => unawaited(_pickGrace()),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            const SizedBox(height: NexSpacing.md),
            Text(
              l10n.securityLocalOnly,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: NexSpacing.sm),
            // Said here because it is a visible consequence of the switch
            // above and not of anything the user did afterwards: someone whose
            // screenshot comes out black deserves to have been told why, on
            // the screen where they turned it on.
            Text(
              l10n.securityScreenshotBlocked,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A titled list of radio rows, for the two choices this screen makes.
///
/// Not [NexChoiceCards], which the settings sheet uses: those cards carry a
/// preview of what the option looks like, and neither of these has anything
/// to show — one is a sentence about when, the other is a number of minutes.
class _OptionSheet<T> extends StatelessWidget {
  const _OptionSheet({
    required this.title,
    required this.selected,
    required this.options,
    required this.onPicked,
  });

  final String title;
  final T selected;

  /// Value, what it is called, and — where it needs one — a line saying what
  /// it actually does.
  final List<(T, String, String?)> options;
  final ValueChanged<T> onPicked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NexSheetBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: NexSpacing.sm),
            child: Text(title, style: theme.textTheme.titleMedium),
          ),
          // ListTile with a tick rather than RadioListTile: the radio's
          // `groupValue`/`onChanged` pair is on its way out of Flutter in
          // favour of RadioGroup, and this row needs neither of them to say
          // "this one is chosen".
          for (final (value, label, hint) in options)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(label),
              subtitle: hint == null ? null : Text(hint),
              trailing: value == selected
                  ? Icon(Icons.check, color: theme.colorScheme.primary)
                  : null,
              selected: value == selected,
              onTap: () => onPicked(value),
            ),
        ],
      ),
    );
  }
}
