import 'dart:convert';
import 'package:file_selector/file_selector.dart';
import '../widgets/feature_label.dart';
import '../platform/password_csv.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../platform/app_lock.dart';
import '../platform/private_clipboard.dart';
import '../platform/secure_window.dart';
import '../platform/vault_session.dart';
import '../platform/vault_store.dart';
import 'package:nex_ui/nex_ui.dart';
import 'vault_editor.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({
    super.key,
    required this.kind,
    this.store,
    this.authentication,
    this.focusId,
    this.picking = false,
  });
  final VaultKind kind;
  final VaultStore? store;
  final AppLockService? authentication;

  /// Show only this entry — a Recurring item's linked card (W5.4). The
  /// unlock is the same as ever; only what is listed after it changes.
  final String? focusId;

  /// Choosing a card to link: tapping one pops with its id. Nothing about
  /// the card leaves the vault; the id is all the caller keeps.
  final bool picking;
  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> with WidgetsBindingObserver {
  late final store = widget.store ?? VaultStore();
  late final auth = widget.authentication ?? AppLockService();
  late final Future<bool> protection;
  final session = VaultSession.instance;
  final search = TextEditingController();
  List<VaultEntry> entries = [];
  VaultEntry? draft, editing;
  bool unlocked = false,
      busy = false,
      authenticating = false,
      favorites = false;
  String? error, copiedField;
  Timer? idle, draftTimer, copiedTimer;
  final messageInput = TextEditingController();
  int generation = 0;

  /// Whether the editor was open when the app went to the background, so a
  /// return inside the grace period lands back in it rather than on the list.
  bool _resumeEditing = false;
  Future<void>? _loading;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    protection = NexSecureWindow.acquirePrivateSurface();
    // Another private tool was unlocked moments ago: open straight away.
    if (session.isOpen) unawaited(_reload());
  }

  @override
  void dispose() {
    messageInput.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _flushDraft();
    idle?.cancel();
    copiedTimer?.cancel();
    search.dispose();
    unawaited(NexSecureWindow.releasePrivateSurface());
    super.dispose();
  }

  void _touch() {
    if (!unlocked) return;
    session.touch();
    _armIdle();
  }

  void _armIdle() {
    idle?.cancel();
    idle = Timer(session.remaining, () {
      // Another private screen may have extended the unlock meanwhile: wait
      // for the new deadline instead of giving up on locking at all.
      if (session.isOpen) {
        _armIdle();
      } else {
        _lock();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.detached:
        _lock();
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        _hide();
      case AppLifecycleState.inactive:
        if (!authenticating) _hide();
      case AppLifecycleState.resumed:
        if (unlocked || authenticating) return;
        if (session.isOpen) {
          unawaited(_reload());
        } else {
          _lock();
        }
    }
  }

  void _flushDraft() {
    if (draftTimer?.isActive != true) return;
    draftTimer?.cancel();
    final value = draft;
    if (value != null) unawaited(_writeDraft(value));
  }

  Future<void> _writeDraft(VaultEntry value) async {
    try {
      await store.saveDraft(value);
    } catch (_) {
      if (mounted) {
        setState(() => error = AppLocalizations.of(context).vaultError);
      }
    }
  }

  /// Takes everything private off the screen without ending the unlock.
  ///
  /// Used whenever the app leaves the foreground: the task switcher, a
  /// screenshot or someone glancing at the phone sees nothing, but coming
  /// back inside [VaultSession.grace] reopens without authenticating.
  void _hide({bool keepPlace = true}) {
    _flushDraft();
    copiedTimer?.cancel();
    generation++;
    if (!mounted) return;
    if (unlocked) _resumeEditing = keepPlace && editing != null;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      unlocked = false;
      busy = false;
      entries = [];
      editing = null;
      draft = null;
      copiedField = null;
    });
  }

  /// Ends the unlock for every private tool.
  void _lock() {
    session.close();
    idle?.cancel();
    messageInput.clear();
    search.clear();
    _resumeEditing = false;
    _hide(keepPlace: false);
  }

  Future<void> _reload() =>
      _loading ??= _load().whenComplete(() => _loading = null);

  Future<void> _load() async {
    final ticket = generation;
    try {
      if (!await protection) throw StateError('Secure window unavailable');
      final data = await store.read();
      if (!mounted || ticket != generation || !session.isOpen) return;
      setState(() {
        entries = data.entries;
        draft = data.draft;
        unlocked = true;
        error = null;
        if (_resumeEditing && data.draft?.kind == widget.kind) {
          editing = data.draft;
        }
        _resumeEditing = false;
      });
      _touch();
    } catch (_) {
      if (mounted && ticket == generation) {
        setState(() => error = AppLocalizations.of(context).vaultError);
      }
    }
  }

  Future<void> _unlock() async {
    if (busy || authenticating) return;
    final l = AppLocalizations.of(context);
    setState(() {
      busy = true;
      authenticating = true;
      error = null;
    });
    final ticket = generation;
    try {
      if (!await protection) throw StateError('Secure window unavailable');
      final accepted = await auth.authenticate(
        reason: l.vaultAuthReason,
        biometricOnly: false,
      );
      if (!mounted || ticket != generation) return;
      if (!accepted) {
        setState(() => error = l.vaultUnavailable);
        return;
      }
      session.open();
      authenticating = false;
      await _load();
    } catch (_) {
      if (mounted && ticket == generation) setState(() => error = l.vaultError);
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          authenticating = false;
        });
      }
    }
  }

  Future<void> _operate(
    Future<void> Function() action, {
    bool closeEditor = false,
  }) async {
    if (busy) return;
    final ticket = generation;
    setState(() {
      busy = true;
      error = null;
    });
    draftTimer?.cancel();
    try {
      await action();
      final data = await store.read();
      if (!mounted || ticket != generation) return;
      setState(() {
        entries = data.entries;
        draft = data.draft;
        if (closeEditor) editing = null;
      });
    } catch (_) {
      if (mounted && ticket == generation) {
        setState(() => error = AppLocalizations.of(context).vaultError);
      }
    } finally {
      if (mounted && ticket == generation) setState(() => busy = false);
    }
  }

  void _edit(VaultEntry entry) {
    setState(() {
      editing = entry;
      draft = entry;
      copiedField = null;
    });
    _touch();
  }

  void _changed(VaultEntry entry) {
    draft = entry;
    _touch();
    draftTimer?.cancel();
    draftTimer = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_writeDraft(entry)),
    );
  }

  void _back() {
    _flushDraft();
    setState(() {
      editing = null;
      error = null;
    });
  }

  Future<void> _copy(String field, String value) async {
    final ticket = generation;
    try {
      await PrivateClipboard.copy(value);
      if (!mounted || ticket != generation) return;
      _touch();
      copiedTimer?.cancel();
      setState(() => copiedField = field);
      copiedTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => copiedField = null);
      });
    } catch (_) {
      if (mounted && ticket == generation) {
        setState(() => error = AppLocalizations.of(context).vaultCopyFailed);
      }
    }
  }

  Future<void> _toggleFavorite(VaultEntry entry) => _operate(
    () => store.save(
      VaultEntry(
        id: entry.id,
        kind: entry.kind,
        fields: entry.fields,
        updatedAt: DateTime.now(),
        favorite: !entry.favorite,
      ),
    ),
  );

  Future<void> _confirmDelete(VaultEntry entry) async {
    final l = AppLocalizations.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.vaultDelete),
        content: Text(l.vaultDeleteHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            child: Text(l.vaultDeleteConfirm),
          ),
        ],
      ),
    );
    if (yes == true && mounted && unlocked) {
      await _operate(() => store.delete(entry.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final title = widget.kind == VaultKind.message
        ? nexLabel(
            context,
            'Private saved messages',
            'پیام‌های ذخیره‌شدهٔ خصوصی',
          )
        : widget.kind == VaultKind.password
        ? l.vaultPasswords
        : l.vaultCards;
    return PopScope(
      canPop: !busy && editing == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !busy) _back();
      },
      child: Listener(
        onPointerDown: (_) => _touch(),
        child: Scaffold(
          appBar: AppBar(
            leading: BackButton(
              onPressed: busy
                  ? null
                  : () {
                      if (editing != null) {
                        _back();
                      } else {
                        Navigator.maybePop(context);
                      }
                    },
            ),
            title: Text(editing == null ? title : l.vaultEdit),
            actions: [
              if (unlocked &&
                  widget.kind == VaultKind.password &&
                  editing == null)
                IconButton(
                  tooltip: nexLabel(
                    context,
                    'Import Chrome CSV',
                    'ورود رمزهای Chrome',
                  ),
                  onPressed: busy ? null : _importPasswords,
                  icon: const Icon(Icons.file_download_outlined),
                ),
              if (unlocked)
                IconButton(
                  tooltip: l.vaultLock,
                  onPressed: _lock,
                  icon: const Icon(Icons.lock_outline),
                ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      error!,
                      style: TextStyle(color: theme.colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ),
                if (busy) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: !unlocked
                      ? _locked(l, theme)
                      : editing != null
                      ? VaultEditor(
                          key: ValueKey(editing!.id),
                          entry: editing!,
                          busy: busy,
                          onChanged: _changed,
                          onSave: (entry) => _operate(
                            () => store.save(entry),
                            closeEditor: true,
                          ),
                          onDiscard: () => _operate(
                            () => store.saveDraft(null),
                            closeEditor: true,
                          ),
                        )
                      : widget.kind == VaultKind.message
                      ? _messages(l, theme)
                      : _list(l, theme),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _importPasswords() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Chrome CSV',
          extensions: ['csv'],
          mimeTypes: ['text/csv', 'text/comma-separated-values'],
        ),
      ],
    );
    if (file == null || !mounted) return;
    if (!unlocked) {
      await (session.isOpen ? _reload() : _unlock());
    }
    if (!mounted || !unlocked) return;
    final ticket = generation;
    try {
      if (await file.length() > 4 * 1024 * 1024) {
        throw const FormatException('File too large');
      }
      final imported = parsePasswordCsv(utf8.decode(await file.readAsBytes()));
      if (!mounted || !unlocked || ticket != generation) return;
      final seen = entries
          .where((e) => e.kind == VaultKind.password)
          .map(passwordIdentity)
          .toSet();
      final count = imported.where((e) => seen.add(passwordIdentity(e))).length;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(nexLabel(context, 'Import passwords', 'ورود رمزها')),
          content: Text(
            nexLabel(
              context,
              '$count new passwords. Exact duplicates are skipped. Chrome CSV is unencrypted; delete the export after importing.',
              '$count رمز تازه وارد می‌شود؛ تکراری‌های یکسان رد می‌شوند. فایل خروجی Chrome رمزگذاری نشده است؛ پس از ورود آن را پاک کنید.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppLocalizations.of(context).cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(nexLabel(context, 'Import', 'واردکردن')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted || !unlocked || ticket != generation) {
        return;
      }
      await _operate(() => store.importPasswords(imported));
    } catch (_) {
      if (mounted && unlocked && ticket == generation) {
        setState(
          () => error = nexLabel(
            context,
            'Could not import. Choose a valid Chrome password CSV (up to 2,000 rows / 4 MB). Nothing was imported.',
            'ورود انجام نشد. فایل معتبر CSV رمزهای Chrome تا ۲۰۰۰ ردیف و ۴ مگابایت انتخاب کنید.',
          ),
        );
      }
    }
  }

  Widget _messages(AppLocalizations l, ThemeData theme) {
    final messages = entries.where((e) => e.kind == VaultKind.message).toList()
      ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    return Column(
      children: [
        Expanded(
          child: ListView(
            reverse: true,
            padding: const EdgeInsets.all(16),
            children: [
              for (final e in messages.reversed)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.value('text'),
                            textDirection:
                                RegExp('[ا-ی]').hasMatch(e.value('text'))
                                ? TextDirection.rtl
                                : TextDirection.ltr,
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: l.copy,
                                onPressed: () => _copy(e.id, e.value('text')),
                                icon: Icon(
                                  copiedField == e.id
                                      ? Icons.check
                                      : Icons.copy_outlined,
                                ),
                              ),
                              IconButton(
                                tooltip: l.delete,
                                onPressed: busy
                                    ? null
                                    : () async {
                                        final yes = await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: Text(l.delete),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, false),
                                                child: Text(l.cancel),
                                              ),
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, true),
                                                child: Text(l.delete),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (yes == true &&
                                            mounted &&
                                            unlocked) {
                                          await _operate(
                                            () => store.delete(e.id),
                                          );
                                        }
                                      },
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: messageInput,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 10000,
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  onChanged: (_) => _touch(),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: nexLabel(
                      context,
                      'Write a private message',
                      'پیام خصوصی بنویسید',
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              IconButton.filled(
                tooltip: l.vaultSave,
                onPressed: busy
                    ? null
                    : () async {
                        final text = messageInput.text.trim();
                        if (text.isEmpty) return;
                        final empty = VaultStore.empty(VaultKind.message);
                        await _operate(
                          () => store.save(
                            VaultEntry(
                              id: empty.id,
                              kind: empty.kind,
                              fields: {'text': text},
                              updatedAt: empty.updatedAt,
                            ),
                          ),
                        );
                        if (mounted &&
                            error == null &&
                            messageInput.text.trim() == text) {
                          messageInput.clear();
                        }
                      },
                icon: const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _locked(AppLocalizations l, ThemeData theme) => session.isOpen
      // Still unlocked, only off screen for a moment (or about to load):
      // no prompt to authenticate, just nothing private to see.
      ? const Center(child: CircularProgressIndicator())
      : Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.lock_person_outlined,
                    size: 56,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 24),
                Text(l.vaultLocked, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 12),
                Text(l.vaultUnlockHint, textAlign: TextAlign.center),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: busy ? null : _unlock,
                  icon: const Icon(Icons.fingerprint),
                  label: Text(l.vaultUnlock),
                ),
                if (error != null)
                  TextButton(
                    onPressed: auth.openDeviceSecurity,
                    child: Text(l.settings),
                  ),
                const SizedBox(height: 24),
                Text(
                  l.vaultPrivacyHint,
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
  Widget _list(AppLocalizations l, ThemeData theme) {
    final query = search.text.trim().toLowerCase();
    final items =
        entries
            .where(
              (e) =>
                  e.kind == widget.kind &&
                  (widget.focusId == null || e.id == widget.focusId) &&
                  (!favorites || e.favorite) &&
                  [
                    e.title,
                    e.value('login'),
                    e.value('website'),
                    e.value('bank'),
                    e.value('holder'),
                  ].join(' ').toLowerCase().contains(query),
            )
            .toList()
          ..sort((a, b) {
            final favorite = (b.favorite ? 1 : 0).compareTo(a.favorite ? 1 : 0);
            return favorite != 0
                ? favorite
                : b.updatedAt.compareTo(a.updatedAt);
          });
    final password = widget.kind == VaultKind.password;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: search,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                onChanged: (_) {
                  _touch();
                  setState(() {});
                },
                decoration: InputDecoration(
                  isDense: true,
                  hintText: l.vaultSearch,
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: l.vaultFavorites,
              isSelected: favorites,
              onPressed: () => setState(() => favorites = !favorites),
              icon: const Icon(Icons.star_outline_rounded),
              selectedIcon: const Icon(Icons.star_rounded),
            ),
            const SizedBox(width: 4),
            IconButton.filled(
              tooltip: password ? l.vaultAddPassword : l.vaultAddCard,
              onPressed: busy || draft != null
                  ? null
                  : () => _edit(VaultStore.empty(widget.kind)),
              icon: Icon(
                password ? Icons.add_moderator_outlined : Icons.add_card,
              ),
            ),
          ],
        ),
        if (draft != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.edit_note),
                title: Text(l.vaultResume),
                subtitle: Text(
                  draft!.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _edit(draft!),
              ),
            ),
          ),
        const SizedBox(height: 14),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(
              children: [
                Icon(
                  password ? Icons.key_outlined : Icons.credit_card,
                  size: 44,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  query.isNotEmpty || favorites
                      ? l.vaultNoResults
                      : l.vaultEmpty,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(l.vaultEmptyHint, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: busy || draft != null
                      ? null
                      : () => _edit(VaultStore.empty(widget.kind)),
                  icon: Icon(
                    password ? Icons.add_moderator_outlined : Icons.add_card,
                  ),
                  label: Text(password ? l.vaultAddPassword : l.vaultAddCard),
                ),
              ],
            ),
          ),
        for (final entry in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: widget.picking
                ? Card(
                    key: ValueKey('vault-pick-${entry.id}'),
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => Navigator.pop(context, entry.id),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: _bankCard(theme, entry, menu: null, onTap: null),
                      ),
                    ),
                  )
                : entry.kind == VaultKind.card
                ? _cardItem(l, theme, entry)
                : _passwordItem(l, theme, entry),
          ),
        const SizedBox(height: 12),
        Text(l.vaultBackupHint, style: theme.textTheme.bodySmall),
      ],
    );
  }

  /// Everything about one password on the list itself.
  ///
  /// There used to be a details page between the list and the value, which
  /// made the most common thing anyone does here — copy a password — cost an
  /// extra tap and a page transition every time.
  Widget _passwordItem(AppLocalizations l, ThemeData theme, VaultEntry entry) {
    final scheme = theme.colorScheme;
    return Card(
      key: ValueKey('vault-item-${entry.id}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 4, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(
                    Icons.key_rounded,
                    size: 20,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (entry.favorite)
                  Icon(Icons.star_rounded, size: 20, color: scheme.primary),
                _itemMenu(l, entry),
              ],
            ),
            for (final (key, label) in [
              ('login', l.vaultLogin),
              ('password', l.vaultPassword),
              ('website', l.vaultWebsite),
              ('notes', l.vaultNotes),
            ])
              if (entry.value(key).isNotEmpty)
                _fieldRow(theme, entry, key, label),
          ],
        ),
      ),
    );
  }

  /// The card itself, then every detail under it, copyable in one tap.
  Widget _cardItem(AppLocalizations l, ThemeData theme, VaultEntry entry) {
    return Card(
      key: ValueKey('vault-item-${entry.id}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _bankCard(
              theme,
              entry,
              menu: _itemMenu(l, entry),
              onTap: () => _copy(
                '${entry.id}:number',
                vaultCardDigits(entry.value('number')),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (key, label) in [
                    ('number', l.vaultNumber),
                    ('expiry', l.vaultExpiry),
                    ('iban', l.vaultIban),
                    ('account', l.vaultAccount),
                    ('holder', l.vaultHolder),
                    ('bank', l.vaultBank),
                    ('notes', l.vaultNotes),
                  ])
                    if (entry.value(key).isNotEmpty)
                      _fieldRow(theme, entry, key, label),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemMenu(AppLocalizations l, VaultEntry entry) =>
      PopupMenuButton<String>(
        tooltip: nexLabel(context, 'More', 'بیشتر'),
        enabled: !busy,
        icon: const Icon(Icons.more_vert),
        onSelected: (choice) {
          _touch();
          switch (choice) {
            case 'edit':
              if (draft == null) _edit(entry);
            case 'favorite':
              unawaited(_toggleFavorite(entry));
            case 'delete':
              unawaited(_confirmDelete(entry));
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'edit',
            enabled: draft == null,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.edit_outlined),
              title: Text(l.vaultEdit),
            ),
          ),
          PopupMenuItem(
            value: 'favorite',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                entry.favorite ? Icons.star_rounded : Icons.star_outline,
              ),
              title: Text(l.vaultFavorite),
            ),
          ),
          PopupMenuItem(
            value: 'delete',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.delete_outline),
              title: Text(l.vaultDelete),
            ),
          ),
        ],
      );

  static const _ltrFields = {
    'password',
    'number',
    'iban',
    'expiry',
    'account',
    'website',
    'login',
  };

  /// One labelled value. The whole row copies; the icon says it did.
  Widget _fieldRow(
    ThemeData theme,
    VaultEntry entry,
    String key,
    String label,
  ) {
    final l = AppLocalizations.of(context);
    final id = '${entry.id}:$key';
    final copied = copiedField == id;
    final raw = entry.value(key);
    final shown = key == 'number' ? _groupDigits(vaultCardDigits(raw)) : raw;
    final value = key == 'number' ? vaultCardDigits(raw) : raw;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _copy(id, value),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 2, top: 2, bottom: 2),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    shown,
                    textDirection: _ltrFields.contains(key)
                        ? TextDirection.ltr
                        : null,
                    maxLines: key == 'notes' ? 6 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontFeatures: _ltrFields.contains(key)
                          ? const [FontFeature.tabularFigures()]
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: copied ? l.vaultCopied : '${l.copy} · $label',
              onPressed: () => _copy(id, value),
              icon: Icon(
                copied ? Icons.check_rounded : Icons.copy_outlined,
                size: 20,
                color: copied ? theme.colorScheme.primary : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _groupDigits(String digits) => [
    for (var i = 0; i < digits.length; i += 4)
      digits.substring(i, i + 4 > digits.length ? digits.length : i + 4),
  ].join(' ');

  Widget _bankCard(
    ThemeData theme,
    VaultEntry entry, {
    VoidCallback? onTap,
    Widget? menu,
  }) {
    final number = vaultCardDigits(entry.value('number'));
    final chosen = nexParseTagColor(entry.value('color'));
    final base = chosen ?? theme.colorScheme.primaryContainer;
    final second = chosen == null
        ? theme.colorScheme.secondaryContainer
        : Color.lerp(chosen, Colors.black, 0.35)!;
    final ink =
        ThemeData.estimateBrightnessForColor(Color.lerp(base, second, .5)!) ==
            Brightness.dark
        ? Colors.white
        : const Color(0xFF14161A);
    final foreground = chosen == null
        ? theme.colorScheme.onPrimaryContainer
        : ink;
    return AspectRatio(
      aspectRatio: 1.9,
      child: Material(
        color: base,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [base, second],
              ),
            ),
            padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 4, 16),
            child: IconTheme.merge(
              data: IconThemeData(color: foreground),
              child: DefaultTextStyle.merge(
                style: TextStyle(color: foreground),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.credit_card),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            entry.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: foreground,
                            ),
                          ),
                        ),
                        if (entry.favorite)
                          const Icon(Icons.star_rounded, size: 20),
                        ?menu,
                        if (menu == null) const SizedBox(height: 48),
                      ],
                    ),
                    const Spacer(),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        _groupDigits(number),
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(
                          fontSize: 22,
                          letterSpacing: 1.5,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.value('holder'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (entry.value('expiry').isNotEmpty)
                            Text(
                              entry.value('expiry'),
                              textDirection: TextDirection.ltr,
                              style: const TextStyle(
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
