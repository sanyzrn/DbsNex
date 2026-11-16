import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'security_strings.dart';

class SecurityIncidentScreen extends StatefulWidget {
  const SecurityIncidentScreen({super.key});
  @override
  State<SecurityIncidentScreen> createState() => _SecurityIncidentScreenState();
}

class _SecurityIncidentScreenState extends State<SecurityIncidentScreen> {
  String _case = 'sharedPassword';
  @override
  Widget build(BuildContext context) {
    final s = securityStrings;
    final steps = [
      'trustedRoute',
      if (_case == 'sharedPassword') 'changeExposed',
      if (_case != 'openedOnly') 'revoke',
      if (_case == 'openedOnly') 'downloads',
      'contact',
    ];
    return Scaffold(
      appBar: NexAppBar(title: Text(s(context, 'incident'))),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          NexSpacing.md,
          NexSpacing.md,
          NexSpacing.md,
          NexSpacing.xl + nexBottomInset(context),
        ),
        children: [
          Text(s(context, 'incidentIntro')),
          const SizedBox(height: NexSpacing.md),
          Wrap(
            spacing: NexSpacing.sm,
            runSpacing: NexSpacing.sm,
            children: [
              for (final key in ['sharedPassword', 'sharedCode', 'openedOnly'])
                ChoiceChip(
                  label: Text(s(context, key)),
                  selected: _case == key,
                  onSelected: (_) => setState(() => _case = key),
                ),
            ],
          ),
          const SizedBox(height: NexSpacing.md),
          for (final (i, key) in steps.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: NexSpacing.md),
              child: NexPanel(
                title:
                    '${nexDigits('${i + 1}', persian: NexModuleStrings.persian(context))}. ${s(context, key)}',
                icon: Icons.arrow_forward_outlined,
                child: Text(
                  s(
                    context,
                    key == 'trustedRoute' ? 'trustedRouteBody' : '${key}Body',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
