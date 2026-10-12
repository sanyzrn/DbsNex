import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';
import '../platform/display_date.dart';
import '../l10n/app_localizations.dart';
import '../platform/private_clipboard.dart';
import '../platform/secure_window.dart';
import '../platform/vault_store.dart';
import '../widgets/nex_shelf.dart';

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

  /// How hard the password is to guess, as 0 to 1: its bits of entropy
  /// against 128, which no one is going to brute-force.
  double get _strength {
    final alphabet = symbols ? 90 : 62;
    final bits = length * math.log(alphabet) / math.ln2;
    return (bits / 128).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final slate = NexHue.slate.of(theme.brightness);
    final persian = Localizations.localeOf(context).languageCode == 'fa';
    final strength = _strength;
    final meter = Color.lerp(
      NexHue.amber.of(theme.brightness),
      NexHue.teal.of(theme.brightness),
      strength,
    )!;
    return Scaffold(
      appBar: AppBar(title: Text(l.vaultGenerator)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(NexSpacing.md),
          children: [
            // The password on a card of its own, in a face where every
            // character is a different shape — l, 1 and I are the three
            // anyone copying one by hand gets wrong — with how strong it is
            // drawn under it rather than said.
            Container(
              padding: const EdgeInsets.fromLTRB(
                NexSpacing.md,
                NexSpacing.lg,
                NexSpacing.md,
                NexSpacing.md,
              ),
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  slate.withValues(alpha: 0.1),
                  scheme.surfaceContainerLow,
                ),
                borderRadius: BorderRadius.circular(NexRadius.xl),
                border: Border.all(color: slate.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  NexIconTile(Icons.casino_outlined, color: slate),
                  const SizedBox(height: NexSpacing.md),
                  AnimatedSwitcher(
                    duration: NexMotion.standard,
                    // Not selectable: a copy made by selecting it would skip
                    // the private clipboard and never be wiped.
                    child: Text(
                      password,
                      key: ValueKey(password),
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: NexSpacing.md),
                  Row(
                    children: [
                      for (var i = 0; i < 4; i++) ...[
                        if (i > 0) const SizedBox(width: NexSpacing.xs),
                        Expanded(
                          child: AnimatedContainer(
                            duration: NexMotion.standard,
                            height: 5,
                            decoration: BoxDecoration(
                              color: strength > i / 4
                                  ? meter
                                  : scheme.onSurfaceVariant.withValues(
                                      alpha: 0.18,
                                    ),
                              borderRadius: BorderRadius.circular(NexRadius.xs),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: NexSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
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
                      ),
                      const SizedBox(width: NexSpacing.sm),
                      IconButton.filledTonal(
                        tooltip: l.vaultGenerate,
                        onPressed: generate,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: NexSpacing.md),
            NexPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l.vaultLength,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      Text(
                        nexDigits('$length', persian: persian),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
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
                  const Divider(height: NexSpacing.md),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.vaultSymbols),
                    value: symbols,
                    onChanged: (v) {
                      symbols = v;
                      generate();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
