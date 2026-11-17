import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'secret_math.dart';
import 'security_strings.dart';

class SecurityGenerator extends StatefulWidget {
  const SecurityGenerator({super.key, this.randomSource = Random.secure});
  final Random Function() randomSource;
  @override
  State<SecurityGenerator> createState() => _SecurityGeneratorState();
}

class _SecurityGeneratorState extends State<SecurityGenerator>
    with WidgetsBindingObserver {
  bool _phrase = false, _upper = true, _lower = true, _digits = true;
  bool _symbols = true,
      _exclude = true,
      _reveal = false,
      _details = false,
      _copying = false;
  int _length = 24, _words = 6;
  String? _secret, _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A generated password is a secret from the moment it is on screen:
    // no screenshots, no recording, no app-switcher preview while this page
    // is open (SEC-02, carried over from the Tools generator this replaces
    // in 2.8.1).
    unawaited(NexSecureWindow.acquirePrivateSurface());
  }

  @override
  void dispose() {
    unawaited(NexSecureWindow.releasePrivateSurface());
    WidgetsBinding.instance.removeObserver(this);
    _secret = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && mounted) {
      setState(() {
        _secret = null;
        _reveal = false;
      });
    }
  }

  void _change(VoidCallback action) => setState(() {
    action();
    _secret = null;
    _error = null;
    _reveal = false;
  });
  void _generate() {
    _change(() {});
    final options = SecretOptions(
      length: _length,
      upper: _upper,
      lower: _lower,
      digits: _digits,
      symbols: _symbols,
      excludeAmbiguous: _exclude,
    );
    if (!_phrase && options.groups.isEmpty) {
      setState(() => _error = securityStrings(context, 'poolError'));
      return;
    }
    try {
      final random = widget.randomSource();
      final next = _phrase
          ? makePassphrase(_words, random.nextInt)
          : makePassword(options, random.nextInt);
      setState(() => _secret = next);
    } catch (_) {
      setState(() => _error = securityStrings(context, 'generationError'));
    }
  }

  Future<void> _copy() async {
    final secret = _secret;
    if (secret == null || _copying) return;
    setState(() => _copying = true);
    try {
      await nexModuleCopyText(secret);
      if (mounted) {
        nexShowBanner(context, message: securityStrings(context, 'copied'));
      }
    } catch (_) {
      if (mounted) {
        nexShowBanner(
          context,
          message: securityStrings(context, 'copyError'),
          kind: NexBannerKind.failed,
        );
      }
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  Widget _option(String key, bool value, ValueChanged<bool> change) =>
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(securityStrings(context, key)),
        value: value,
        onChanged: _copying ? null : (v) => _change(() => change(v)),
      );
  @override
  Widget build(BuildContext context) {
    final s = securityStrings;
    return Scaffold(
      appBar: NexAppBar(title: Text(s(context, 'generator'))),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          NexSpacing.md,
          NexSpacing.md,
          NexSpacing.md,
          NexSpacing.xl + nexBottomInset(context),
        ),
        children: [
          NexModuleHero(
            moduleId: 'security_tools',
            icon: Icons.key_outlined,
            headline: _phrase
                ? s(context, 'wordCount', {'n': _words})
                : s(context, 'characters', {'n': _length}),
            caption: s(context, 'generatorPrivacy'),
          ),
          const SizedBox(height: NexSpacing.md),
          NexAdaptiveSegments<bool>(
            segments: [
              ButtonSegment(value: false, label: Text(s(context, 'password'))),
              ButtonSegment(value: true, label: Text(s(context, 'passphrase'))),
            ],
            selected: {_phrase},
            onSelectionChanged: _copying
                ? null
                : (v) => _change(() => _phrase = v.first),
          ),
          const SizedBox(height: NexSpacing.md),
          Wrap(
            spacing: NexSpacing.sm,
            runSpacing: NexSpacing.sm,
            children: [
              for (final n in _phrase ? [6, 7, 8] : [16, 24, 32, 48, 64])
                ChoiceChip(
                  label: Text(
                    s(context, _phrase ? 'wordCount' : 'characters', {'n': n}),
                  ),
                  selected: (_phrase ? _words : _length) == n,
                  onSelected: _copying
                      ? null
                      : (_) => _change(() {
                          if (_phrase) {
                            _words = n;
                          } else {
                            _length = n;
                          }
                        }),
                ),
            ],
          ),
          const SizedBox(height: NexSpacing.md),
          if (!_phrase)
            NexMoreDetails(
              open: _details,
              onChanged: (v) => setState(() => _details = v),
              title: s(context, 'compatibility'),
              child: Column(
                children: [
                  Text(s(context, 'groupNote')),
                  _option('upper', _upper, (v) => _upper = v),
                  _option('lower', _lower, (v) => _lower = v),
                  _option('digits', _digits, (v) => _digits = v),
                  _option('symbols', _symbols, (v) => _symbols = v),
                  _option('exclude', _exclude, (v) => _exclude = v),
                ],
              ),
            ),
          if (_phrase) ...[
            Text(s(context, 'phraseNote')),
            TextButton(
              onPressed: () => nexShowDialog<void>(
                context: context,
                builder: (c) => NexAlertDialog(
                  title: Text(s(c, 'wordAbout')),
                  content: NexDialogBody(
                    child: SelectableText(s(c, 'wordLicense')),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: Text(AppLocalizations.of(c).closeLabel),
                    ),
                  ],
                ),
              ),
              child: Text(s(context, 'wordCredit')),
            ),
          ],
          const SizedBox(height: NexSpacing.md),
          FilledButton.icon(
            key: const ValueKey('security-generate'),
            onPressed: _copying ? null : _generate,
            icon: const Icon(Icons.refresh),
            label: Text(s(context, 'generate')),
          ),
          const SizedBox(height: NexSpacing.md),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          NexPanel(
            icon: Icons.lock_outline,
            title: s(
              context,
              _secret == null
                  ? 'noSecret'
                  : _reveal
                  ? 'secretReady'
                  : 'hidden',
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_secret != null) ...[
                  if (_reveal)
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        _secret!,
                        key: const ValueKey('security-output'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  Wrap(
                    spacing: NexSpacing.sm,
                    runSpacing: NexSpacing.sm,
                    children: [
                      TextButton.icon(
                        key: const ValueKey('security-reveal'),
                        onPressed: () => setState(() => _reveal = !_reveal),
                        icon: Icon(
                          _reveal
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        label: Text(s(context, _reveal ? 'hide' : 'show')),
                      ),
                      TextButton.icon(
                        key: const ValueKey('security-copy'),
                        onPressed: _copying ? null : _copy,
                        icon: const Icon(Icons.copy_outlined),
                        label: Text(s(context, 'copy')),
                      ),
                      TextButton(
                        onPressed: () => _change(() {}),
                        child: Text(s(context, 'clear')),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
