import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'link_math.dart';
import 'security_strings.dart';

class SecurityLinkScreen extends StatefulWidget {
  const SecurityLinkScreen({super.key});
  @override
  State<SecurityLinkScreen> createState() => _SecurityLinkScreenState();
}

class _SecurityLinkScreenState extends State<SecurityLinkScreen>
    with WidgetsBindingObserver {
  final _url = TextEditingController(), _expected = TextEditingController();
  LinkInspection? _result;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _url.clear();
    _expected.clear();
    _url.dispose();
    _expected.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && mounted) _clear();
  }

  void _clear() {
    _url.clear();
    _expected.clear();
    setState(() {
      _result = null;
      _failed = false;
    });
  }

  void _inspect() {
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      final result = LinkInspection.inspect(
        _url.text,
        expected: _expected.text,
      );
      setState(() {
        _result = result;
        _failed = false;
      });
    } catch (_) {
      setState(() {
        _result = null;
        _failed = true;
      });
    }
  }

  Widget _field(TextEditingController controller, String key, int limit) =>
      Padding(
        padding: const EdgeInsets.only(bottom: NexSpacing.md),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: NexTextField(
            key: ValueKey('security-$key'),
            controller: controller,
            minLines: 1,
            maxLines: 4,
            maxLength: limit,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            decoration: InputDecoration(
              labelText: securityStrings(context, key),
              counterText: '',
            ),
            onChanged: (_) => setState(() {
              _result = null;
              _failed = false;
            }),
          ),
        ),
      );
  @override
  Widget build(BuildContext context) {
    final s = securityStrings, result = _result;
    return Scaffold(
      appBar: NexAppBar(title: Text(s(context, 'linkTool'))),
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
            icon: Icons.link_outlined,
            headline: s(context, 'inspect'),
            caption: s(context, 'urlPrivacy'),
          ),
          const SizedBox(height: NexSpacing.md),
          _field(_url, 'url', 4096),
          _field(_expected, 'expected', 253),
          Text(
            s(context, 'expectedHelp'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: NexSpacing.md),
          FilledButton.icon(
            key: const ValueKey('security-inspect'),
            onPressed: _inspect,
            icon: const Icon(Icons.search),
            label: Text(s(context, 'inspect')),
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
              s(context, 'urlError'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (result != null) ...[
            NexPanel(
              title: s(context, 'host'),
              icon: Icons.dns_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: SelectableText(
                      result.host,
                      key: const ValueKey('security-host'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(height: NexSpacing.sm),
                  if (result.scheme == 'https') Text(s(context, 'httpsFact')),
                  if (result.expectedMatch == true)
                    Text(s(context, 'matching')),
                ],
              ),
            ),
            const SizedBox(height: NexSpacing.md),
            NexPanel(
              title: s(
                context,
                result.findings.length == 1 ? 'findingOne' : 'findings',
                {'n': result.findings.length},
              ),
              icon: Icons.fact_check_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (result.findings.isEmpty) Text(s(context, 'neutral')),
                  for (final finding in result.findings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: NexSpacing.sm),
                      child: Text(s(context, finding.name)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: NexSpacing.md),
            Text(s(context, 'verification')),
          ],
        ],
      ),
    );
  }
}
