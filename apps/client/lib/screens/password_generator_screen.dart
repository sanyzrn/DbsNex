import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';
import '../platform/display_date.dart';
import '../l10n/app_localizations.dart';
import '../platform/private_clipboard.dart';
import '../platform/secure_window.dart';
import '../platform/vault_store.dart';

class PasswordGeneratorScreen extends StatefulWidget {
  const PasswordGeneratorScreen({super.key});
  @override
  State<PasswordGeneratorScreen> createState() => _PasswordGeneratorState();
}

class _PasswordGeneratorState extends State<PasswordGeneratorScreen> {
  int length = 20;
  bool symbols = true, copied = false;
  late String password = generateVaultPassword();

  // A generated password is a secret from the moment it is on screen, and
  // this page is reachable from Tools without the vault's lock. Blocking
  // capture here keeps it out of screenshots and the recents thumbnail
  // whether or not the app lock is on.
  @override
  void initState() {
    super.initState();
    unawaited(NexSecureWindow.acquirePrivateSurface());
  }

  @override
  void dispose() {
    unawaited(NexSecureWindow.releasePrivateSurface());
    super.dispose();
  }

  void generate() => setState(() {
    password = generateVaultPassword(length: length, symbols: symbols);
    copied = false;
  });
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.vaultGenerator)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(NexSpacing.lg),
          children: [
            const Icon(Icons.casino_outlined, size: 48),
            const SizedBox(height: NexSpacing.lg),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(NexSpacing.lg),
                child: Text(
                  password,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ),
            Text(
              '${l.vaultLength}: ${nexDigits('$length', persian: Localizations.localeOf(context).languageCode == 'fa')}',
            ),
            Slider(
              value: length.toDouble(),
              min: 12,
              max: 64,
              divisions: 52,
              onChanged: (v) {
                length = v.round();
                generate();
              },
            ),
            SwitchListTile(
              title: Text(l.vaultSymbols),
              value: symbols,
              onChanged: (v) {
                symbols = v;
                generate();
              },
            ),
            const SizedBox(height: NexSpacing.lg),
            FilledButton.icon(
              onPressed: () async {
                try {
                  await PrivateClipboard.copy(password);
                  if (mounted) setState(() => copied = true);
                } catch (_) {
                  if (mounted) setState(() => copied = false);
                }
              },
              icon: Icon(copied ? Icons.check : Icons.copy),
              label: Text(copied ? l.vaultCopied : l.copy),
            ),
            TextButton.icon(
              onPressed: generate,
              icon: const Icon(Icons.refresh),
              label: Text(l.vaultGenerate),
            ),
          ],
        ),
      ),
    );
  }
}
