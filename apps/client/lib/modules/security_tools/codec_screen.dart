import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'codec_math.dart';
import 'security_strings.dart';

class SecurityCodecScreen extends StatefulWidget {
  const SecurityCodecScreen({super.key});
  @override
  State<SecurityCodecScreen> createState() => _SecurityCodecScreenState();
}

class _SecurityCodecScreenState extends State<SecurityCodecScreen>
    with WidgetsBindingObserver {
  final _input = TextEditingController();
  TextCodec _mode = TextCodec.base64;
  bool _decode = false, _failed = false;
  String? _result;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _result = null;
    _input.clear();
    _input.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && mounted) _clear();
  }

  void _clear() {
    _input.clear();
    setState(() {
      _result = null;
      _failed = false;
    });
  }

  void _run() {
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      final text = TextConversion.run(_input.text, _mode, decode: _decode);
      setState(() {
        _result = text;
        _failed = false;
      });
    } catch (_) {
      setState(() {
        _result = null;
        _failed = true;
      });
    }
  }

  Future<void> _copy() async {
    final text = _result;
    if (text == null) return;
    try {
      await nexModuleCopyText(text);
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
    }
  }

  void _swap() {
    final text = _result;
    if (text == null) return;
    // Round-trip only when the full output fits; never silently truncate it.
    try {
      TextConversion.run(text, _mode, decode: !_decode);
      _input.text = text;
      setState(() {
        _decode = !_decode;
        _result = null;
        _failed = false;
      });
    } catch (_) {
      nexShowBanner(
        context,
        message: securityStrings(context, 'codecSwapError'),
        kind: NexBannerKind.failed,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = securityStrings;
    return Scaffold(
      appBar: NexAppBar(title: Text(s(context, 'codecTitle'))),
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
            icon: Icons.transform,
            headline: s(context, 'codecTitle'),
            caption: s(context, 'codecPrivacy'),
          ),
          const SizedBox(height: NexSpacing.md),
          Wrap(
            spacing: NexSpacing.sm,
            runSpacing: NexSpacing.sm,
            children: [
              for (final mode in TextCodec.values)
                ChoiceChip(
                  label: Text(s(context, 'codecFormat_${mode.name}')),
                  selected: mode == _mode,
                  onSelected: (_) => setState(() {
                    _mode = mode;
                    _result = null;
                    _failed = false;
                  }),
                ),
            ],
          ),
          const SizedBox(height: NexSpacing.sm),
          Text(s(context, 'codecHelp_${_mode.name}')),
          const SizedBox(height: NexSpacing.md),
          Wrap(
            spacing: NexSpacing.sm,
            runSpacing: NexSpacing.sm,
            children: [
              for (final decode in [false, true])
                ChoiceChip(
                  label: Text(
                    s(context, decode ? 'codecDecode' : 'codecEncode'),
                  ),
                  selected: decode == _decode,
                  onSelected: (_) => setState(() {
                    _decode = decode;
                    _result = null;
                    _failed = false;
                  }),
                ),
            ],
          ),
          const SizedBox(height: NexSpacing.md),
          NexTextField(
            key: const ValueKey('security-codec-input'),
            controller: _input,
            minLines: 3,
            maxLines: 6,
            maxLength: TextConversion.maxBytes,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            decoration: InputDecoration(
              labelText: s(context, 'codecInput'),
              counterText: '',
            ),
            onChanged: (_) => setState(() {
              _result = null;
              _failed = false;
            }),
          ),
          const SizedBox(height: NexSpacing.sm),
          Text(
            s(context, 'codecLimit', {'n': TextConversion.maxBytes}),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: NexSpacing.md),
          FilledButton.icon(
            key: const ValueKey('security-codec-run'),
            onPressed: _run,
            icon: const Icon(Icons.transform),
            label: Text(s(context, 'codecRun')),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: _clear,
              child: Text(s(context, 'clear')),
            ),
          ),
          if (_failed)
            Text(
              s(context, 'codecError'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_result != null)
            NexPanel(
              title: s(context, 'codecOutput'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: SelectableText(
                      _result!,
                      key: const ValueKey('security-codec-output'),
                    ),
                  ),
                  Wrap(
                    spacing: NexSpacing.sm,
                    children: [
                      TextButton.icon(
                        onPressed: _copy,
                        icon: const Icon(Icons.copy_outlined),
                        label: Text(s(context, 'copy')),
                      ),
                      TextButton.icon(
                        onPressed: _swap,
                        icon: const Icon(Icons.swap_vert),
                        label: Text(s(context, 'codecSwap')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
