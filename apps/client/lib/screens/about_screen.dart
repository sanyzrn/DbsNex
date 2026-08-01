import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nex_ui/nex_ui.dart';
import '../app_version.dart';
import '../l10n/app_localizations.dart';
import '../platform/crash_reporter.dart';
import '../platform/nex_services.dart';
import '../platform/sharing.dart';
import 'update_sheet.dart';

const _websiteUrl = 'https://SaeedZarrini.ir';
const _repositoryUrl = 'https://github.com/sanyzrn/DbsNex';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key, required this.services});

  final NexServices services;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.about)),
      body: ListView(
        padding: EdgeInsets.only(
          bottom: NexSpacing.xl + nexBottomInset(context),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NexSpacing.lg,
              NexSpacing.lg,
              NexSpacing.lg,
              NexSpacing.md,
            ),
            child: Column(
              children: [
                Image.asset(
                  theme.brightness == Brightness.dark
                      ? 'assets/branding/text_logo_dark.png'
                      : 'assets/branding/text_logo_light.png',
                  width: 200,
                  semanticLabel: 'Nex',
                ),
                const SizedBox(height: NexSpacing.xs),
                Text(
                  '${l10n.version} $nexAppVersion',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: NexSpacing.md),
                Text(
                  l10n.emptyPromise,
                  style: theme.textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: NexSpacing.lg),
            child: OutlinedButton.icon(
              onPressed: () => UpdateSheet.show(context),
              icon: const Icon(Icons.system_update_outlined),
              label: Text(l10n.checkForUpdate),
            ),
          ),
          const SizedBox(height: NexSpacing.md),
          const Divider(),
          _Heading(l10n.capabilities),
          _Bullet(icon: Icons.bolt_outlined, text: l10n.capabilityCapture),
          _Bullet(icon: Icons.search, text: l10n.capabilitySearch),
          _Bullet(icon: Icons.wifi_off_outlined, text: l10n.capabilityOffline),
          _Bullet(icon: Icons.ios_share_outlined, text: l10n.capabilityExport),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.business_outlined),
            title: Text(l10n.madeBy),
            subtitle: const Text('DbsStudio'),
          ),
          _LinkTile(
            icon: Icons.language,
            title: l10n.website,
            subtitle: 'SaeedZarrini.ir',
            url: _websiteUrl,
            copiedLabel: l10n.copied,
            copyTooltip: l10n.copy,
          ),
          _LinkTile(
            icon: Icons.code,
            title: l10n.sourceCode,
            subtitle: 'github.com/sanyzrn/DbsNex',
            url: _repositoryUrl,
            copiedLabel: l10n.copied,
            copyTooltip: l10n.copy,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(l10n.localFirstTitle),
            subtitle: Text(l10n.localFirstBody(services.dbPath)),
            trailing: IconButton(
              tooltip: l10n.copyPath,
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: services.dbPath)),
              icon: const Icon(Icons.copy),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_off_outlined),
            title: Text(l10n.silenceTitle),
            subtitle: Text(l10n.silenceBody),
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: Text(l10n.privacy),
            subtitle: Text(l10n.privacyBody),
          ),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: Text(l10n.shareDiagnostics),
            subtitle: Text(l10n.shareDiagnosticsBody),
            onTap: () async {
              final log = await NexCrashLog.open();
              if (!log.file.existsSync()) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(content: Text(l10n.noDiagnosticsYet)),
                  );
                return;
              }
              await nexSendFileOut(
                log.file.path,
                suggestedName: 'nex-diagnostics.txt',
                mimeType: 'text/plain',
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.article_outlined),
            title: Text(l10n.openSourceLicenses),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'Nex',
              applicationVersion: nexAppVersion,
            ),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      NexSpacing.md,
      NexSpacing.md,
      NexSpacing.md,
      NexSpacing.xs,
    ),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall),
  );
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NexSpacing.md,
        vertical: NexSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.secondary),
          const SizedBox(width: NexSpacing.contentGap),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// A link the user can copy.
///
/// Deliberately not a launcher: opening a browser is the one thing this app
/// does not need a network permission for, and copying works identically on
/// every target Nex ships to.
class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.url,
    required this.copiedLabel,
    required this.copyTooltip,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String url;
  final String copiedLabel;
  final String copyTooltip;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: IconButton(
      tooltip: copyTooltip,
      icon: const Icon(Icons.copy),
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: url));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(copiedLabel)));
      },
    ),
    onTap: () async {
      await Clipboard.setData(ClipboardData(text: url));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(copiedLabel)));
    },
  );
}
