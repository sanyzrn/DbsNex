import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_version.dart';
import '../l10n/app_localizations.dart';
import '../platform/nex_services.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key, required this.services});
  final NexServices services;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.about)),
      body: ListView(children: [
        const ListTile(title: Text('Nex'), subtitle: Text(nexAppVersion)),
        ListTile(
          leading: const Icon(Icons.business_outlined),
          title: Text(l10n.madeBy),
          subtitle: const Text('DbsStudio'),
        ),
        ListTile(
          leading: const Icon(Icons.link),
          title: Text(l10n.website),
          subtitle: const Text('SaeedZarrini.ir'),
          trailing: IconButton(
            tooltip: l10n.copy,
            onPressed: () => Clipboard.setData(
                const ClipboardData(text: 'https://SaeedZarrini.ir')),
            icon: const Icon(Icons.copy),
          ),
        ),
        ListTile(
          title: Text(l10n.localFirstTitle),
          subtitle: Text(l10n.localFirstBody(services.dbPath)),
          trailing: IconButton(
            tooltip: l10n.copyPath,
            onPressed: () => Clipboard.setData(ClipboardData(text: services.dbPath)),
            icon: const Icon(Icons.copy),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.notifications_off_outlined),
          title: Text(l10n.silenceTitle),
          subtitle: Text(l10n.silenceBody),
        ),
        ListTile(title: Text(l10n.privacy), subtitle: Text(l10n.privacyBody)),
        ListTile(
          title: Text(l10n.openSourceLicenses),
          onTap: () => showLicensePage(
            context: context,
            applicationName: 'Nex',
            applicationVersion: nexAppVersion,
          ),
        ),
      ]),
    );
  }
}