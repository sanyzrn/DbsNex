import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/app_lock.dart';
import '../platform/nex_preferences.dart';
import '../widgets/nex_banner.dart';
import '../widgets/nex_shelf.dart';

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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final teal = NexHue.teal.of(theme.brightness);
    final violet = NexHue.violet.of(theme.brightness);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.securityTitle)),
      body: AnimatedBuilder(
        animation: widget.preferences,
        builder: (context, _) {
          final on = widget.preferences.appLockEnabled;
          return ListView(
            padding: EdgeInsets.fromLTRB(
              NexSpacing.md,
              NexSpacing.md,
              NexSpacing.md,
              NexSpacing.lg + nexBottomInset(context),
            ),
            children: [
              // Where the lock stands, before the switches that change it:
              // the page used to open on two toggles and leave the state to
              // be worked out from their positions.
              _LockState(
                on: on,
                biometric: widget.preferences.appLockBiometricOnly,
                detail: on
                    ? _timingLabel(l10n)
                    : l10n.securityDevicePasscodeSubtitle,
              ),
              const SizedBox(height: NexSpacing.md),
              NexPanel(
                padding: const EdgeInsets.symmetric(vertical: NexSpacing.xs),
                child: Column(
                  children: [
                    NexSwitchTile(
                      secondary: NexIconTile(
                        Icons.password_outlined,
                        color: teal,
                      ),
                      title: Text(l10n.securityDevicePasscode),
                      subtitle: Text(l10n.securityDevicePasscodeSubtitle),
                      value: on,
                      onChanged: _busy
                          ? null
                          : (value) => unawaited(_setAppLock(value)),
                    ),
                    const Divider(height: 1, indent: 72),
                    NexSwitchTile(
                      secondary: NexIconTile(Icons.fingerprint, color: violet),
                      title: Text(l10n.securityBiometric),
                      subtitle: Text(l10n.securityBiometricSubtitle),
                      value: widget.preferences.appLockBiometricOnly,
                      onChanged: _busy
                          ? null
                          : (value) => unawaited(_setBiometric(value)),
                    ),
                  ],
                ),
              ),
              // Only under a lock that is actually on. When it is off,
              // "lock immediately" and "lock never" describe the same
              // nothing. In place rather than behind a row that opened a
              // sheet: three choices, each with a line saying what it does,
              // are worth seeing at once.
              if (on) ...[
                const SizedBox(height: NexSpacing.md),
                NexPanel(
                  title: l10n.securityLockWhen,
                  icon: Icons.timer_outlined,
                  child: Column(
                    children: [
                      for (final (value, label, hint) in [
                        (
                          AppLockTiming.immediately,
                          l10n.securityLockImmediately,
                          l10n.securityLockImmediatelyHint,
                        ),
                        (
                          AppLockTiming.after,
                          l10n.securityLockAfterTitle,
                          l10n.securityLockAfterHint,
                        ),
                        (
                          AppLockTiming.manual,
                          l10n.securityLockManual,
                          l10n.securityLockManualHint,
                        ),
                      ])
                        _TimingOption(
                          label: label,
                          hint: hint,
                          selected: widget.preferences.appLockTiming == value,
                          onTap: () => unawaited(
                            widget.preferences.setAppLockTiming(value),
                          ),
                        ),
                      if (widget.preferences.appLockTiming ==
                          AppLockTiming.after) ...[
                        const SizedBox(height: NexSpacing.sm),
                        Wrap(
                          spacing: NexSpacing.sm,
                          runSpacing: NexSpacing.sm,
                          children: [
                            for (final seconds in _graceChoices)
                              ChoiceChip(
                                label: Text(_graceLabel(l10n, seconds)),
                                selected:
                                    widget.preferences.appLockGraceSeconds ==
                                    seconds,
                                onSelected: (_) => unawaited(
                                  widget.preferences.setAppLockGraceSeconds(
                                    seconds,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: NexSpacing.md),
              // Said here because it is a visible consequence of the switch
              // above and not of anything the user did afterwards: someone
              // whose screenshot comes out black deserves to have been told
              // why, on the screen where they turned it on.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: NexSpacing.sm),
                  Expanded(
                    child: Text(
                      '${l10n.securityLocalOnly}\n\n'
                      '${l10n.securityScreenshotBlocked}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The lock as it stands: a closed padlock in the accent when Nex asks before
/// it opens, an open one in grey when it does not.
class _LockState extends StatelessWidget {
  const _LockState({
    required this.on,
    required this.biometric,
    required this.detail,
  });

  final bool on;
  final bool biometric;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(NexSpacing.md),
      decoration: BoxDecoration(
        color: on ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(NexRadius.xl),
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: NexMotion.standard,
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? scheme.primary : scheme.surfaceContainerLow,
            ),
            child: Icon(
              on
                  ? (biometric ? Icons.fingerprint : Icons.lock)
                  : Icons.lock_open_outlined,
              size: 28,
              color: on ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: NexSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  on ? l10n.securityStateOn : l10n.securityStateOff,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: on ? scheme.onPrimaryContainer : scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: on
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One answer to "lock when", with the line saying what it means.
class _TimingOption extends StatelessWidget {
  const _TimingOption({
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: NexSpacing.xs),
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.1)
            : scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NexRadius.md),
          side: BorderSide(
            color: selected ? scheme.primary : Colors.transparent,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Semantics(
            selected: selected,
            button: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NexSpacing.md,
                vertical: NexSpacing.sm + 2,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: theme.textTheme.titleSmall),
                        Text(
                          hint,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedOpacity(
                    opacity: selected ? 1 : 0,
                    duration: NexMotion.fast,
                    child: Icon(Icons.check_circle, color: scheme.primary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
