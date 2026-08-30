import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/app_lock.dart';
import '../platform/nex_preferences.dart';
import '../widgets/nex_banner.dart';

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
          ],
        ),
      ),
    );
  }
}
