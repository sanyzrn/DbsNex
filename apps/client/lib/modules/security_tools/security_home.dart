import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'account_editor.dart';
import 'codec_screen.dart';
import 'account_model.dart';
import 'account_repository.dart';
import 'incident_screen.dart';
import 'link_screen.dart';
import 'secret_screen.dart';
import 'security_strings.dart';

class SecurityHome extends StatefulWidget {
  const SecurityHome({super.key, required this.store});
  final NexModuleStore store;
  @override
  State<SecurityHome> createState() => _SecurityHomeState();
}

class _SecurityHomeState extends State<SecurityHome> {
  late final _repo = AccountRepository(widget.store);
  StreamSubscription<void>? _changes;
  VoidCallback? _hideUndo;
  List<SecurityAccount> _accounts = [];
  bool _loading = true, _failed = false, _busy = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _changes = widget.store.changes.listen((_) => unawaited(_load()));
    unawaited(_load());
  }

  @override
  void dispose() {
    _hideUndo?.call();
    unawaited(_changes?.cancel());
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      final rows = await widget.store.list('account');
      if (!mounted || generation != _generation) return;
      setState(() {
        _accounts = rows.map(SecurityAccount.fromRecord).toList();
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _open(Widget page) =>
      Navigator.of(context).push<void>(NexPageRoute(builder: (_) => page));
  Future<void> _edit([SecurityAccount? a]) =>
      _open(SecurityAccountEditor(repo: _repo, account: a));
  Future<void> _write(Future<void> Function() action) async {
    if (_busy || !mounted) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        nexShowBanner(
          context,
          message: securityStrings(
            context,
            e is SecurityConflict ? 'conflict' : 'saveError',
          ),
          kind: NexBannerKind.failed,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(SecurityAccount a) async {
    final yes = await nexShowDialog<bool>(
      context: context,
      builder: (c) => NexAlertDialog(
        title: Text(securityStrings(c, 'deleteAsk')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(AppLocalizations.of(c).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(securityStrings(c, 'delete')),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await _write(() async {
      final raw = await _repo.delete(a);
      if (!mounted) return;
      final handle = nexShowBanner(
        context,
        message: securityStrings(context, 'deleted'),
        actionLabel: securityStrings(context, 'undo'),
        onAction: () => unawaited(_write(() => _repo.undo(a.id, raw))),
      );
      _hideUndo = handle?.hide;
    });
  }

  Widget _tool(String title, String about, IconData icon, Widget page) =>
      Padding(
        padding: const EdgeInsets.only(bottom: NexSpacing.sm),
        child: NexPanel(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(icon),
            title: Text(securityStrings(context, title)),
            subtitle: Text(securityStrings(context, about)),
            onTap: () => _open(page),
          ),
        ),
      );
  @override
  Widget build(BuildContext context) {
    final s = securityStrings;
    final done = _accounts
        .where((a) => a.valid)
        .fold<int>(0, (sum, a) => sum + a.done);
    return Scaffold(
      appBar: NexAppBar(title: Text(s(context, 'title'))),
      floatingActionButton: _loading || _failed
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('security-add'),
              onPressed: _busy ? null : () => _edit(),
              icon: const Icon(Icons.add),
              label: Text(s(context, 'addAccount')),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
          ? NexEmptyState(
              icon: Icons.refresh,
              message: s(context, 'loadError'),
              action: TextButton(
                onPressed: _load,
                child: Text(s(context, 'retry')),
              ),
            )
          : ListView(
              padding: EdgeInsets.fromLTRB(
                NexSpacing.md,
                NexSpacing.md,
                NexSpacing.md,
                NexSpacing.xl * 4 + nexBottomInset(context),
              ),
              children: [
                NexModuleHero(
                  moduleId: 'security_tools',
                  icon: Icons.shield_outlined,
                  headline: s(
                    context,
                    done == 1 ? 'confirmedOne' : 'confirmed',
                    {'n': done},
                  ),
                  caption: s(context, 'selfReport'),
                ),
                const SizedBox(height: NexSpacing.md),
                _tool(
                  'codecTitle',
                  'codecAbout',
                  Icons.transform,
                  const SecurityCodecScreen(),
                ),
                _tool(
                  'generator',
                  'generatorAbout',
                  Icons.key_outlined,
                  const SecurityGenerator(),
                ),
                _tool(
                  'linkTool',
                  'linkAbout',
                  Icons.link_outlined,
                  const SecurityLinkScreen(),
                ),
                _tool(
                  'incident',
                  'incidentAbout',
                  Icons.support_outlined,
                  const SecurityIncidentScreen(),
                ),
                const SizedBox(height: NexSpacing.md),
                NexShelfHeading(
                  icon: Icons.manage_accounts_outlined,
                  title: s(context, 'accounts'),
                ),
                if (_accounts.isEmpty)
                  NexEmptyState(
                    icon: Icons.mail_outline,
                    message: s(context, 'empty'),
                  ),
                for (final a in _accounts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: NexSpacing.sm),
                    child: NexPanel(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: NexTextDirection(
                          text: a.label,
                          child: Text(
                            a.label.isEmpty ? s(context, 'untitled') : a.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        subtitle: Text(
                          !a.valid
                              ? s(context, 'invalid')
                              : a.next == null
                              ? s(context, 'reviewed')
                              : '${s(context, 'progress', {'n': a.done})} · ${s(context, 'next', {'item': s(context, a.next!)})}',
                        ),
                        onTap: _busy ? null : () => _edit(a),
                        trailing: NexPopupMenuButton<String>(
                          tooltip: s(context, 'more'),
                          icon: const Icon(Icons.more_horiz),
                          onSelected: (v) {
                            if (!_busy && v == 'delete') unawaited(_delete(a));
                          },
                          itemBuilder: (c) => [
                            nexMenuItem(
                              value: 'delete',
                              icon: Icons.delete_outline,
                              label: s(c, 'delete'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
