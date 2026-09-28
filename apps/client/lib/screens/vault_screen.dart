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
import '../platform/vault_store.dart';
import 'vault_editor.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({
    super.key,
    required this.kind,
    this.store,
    this.authentication,
  });
  final VaultKind kind;
  final VaultStore? store;
  final AppLockService? authentication;
  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> with WidgetsBindingObserver {
  late final store = widget.store ?? VaultStore();
  late final auth = widget.authentication ?? AppLockService();
  late final Future<bool> protection;
  final search = TextEditingController();
  List<VaultEntry> entries = [];
  VaultEntry? draft, selected, editing;
  bool unlocked = false,
      busy = false,
      authenticating = false,
      favorites = false;
  bool confirmDelete = false;
  String? error, copiedField;
  Timer? idle, draftTimer, copiedTimer;
  final messageInput = TextEditingController();
  int generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    protection = NexSecureWindow.acquirePrivateSurface();
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
    idle?.cancel();
    idle = Timer(const Duration(minutes: 2), _lock);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached ||
        (state == AppLifecycleState.inactive && !authenticating)) {
      _lock();
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

  void _lock() {
    messageInput.clear();
    _flushDraft();
    idle?.cancel();
    copiedTimer?.cancel();
    generation++;
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      unlocked = false;
      busy = false;
      entries = [];
      selected = null;
      editing = null;
      draft = null;
      confirmDelete = false;
      copiedField = null;
      search.clear();
    });
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
      final data = await store.read();
      if (!mounted || ticket != generation) return;
      setState(() {
        entries = data.entries;
        draft = data.draft;
        unlocked = true;
      });
      _touch();
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
    bool remove = false,
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
        if (remove) selected = null;
        if (selected != null) {
          selected = entries.where((e) => e.id == selected!.id).firstOrNull;
        }
        confirmDelete = false;
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
      selected = null;
      confirmDelete = false;
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
      canPop: !busy && editing == null && selected == null,
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
                      if (editing != null || selected != null) {
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
                      : selected != null
                      ? _detail(l, theme, selected!)
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
    if (!unlocked) await _unlock();
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

  Widget _locked(AppLocalizations l, ThemeData theme) => Center(
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
                  (!favorites || e.favorite) &&
                  [
                    e.title,
                    e.value('login'),
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        FilledButton.icon(
          onPressed: busy || draft != null
              ? null
              : () => _edit(VaultStore.empty(widget.kind)),
          icon: Icon(
            widget.kind == VaultKind.password
                ? Icons.add_moderator_outlined
                : Icons.add_card,
          ),
          label: Text(
            widget.kind == VaultKind.password
                ? l.vaultAddPassword
                : l.vaultAddCard,
          ),
        ),
        if (draft != null)
          Card(
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
        const SizedBox(height: 16),
        TextField(
          controller: search,
          autocorrect: false,
          enableSuggestions: false,
          enableIMEPersonalizedLearning: false,
          onChanged: (_) {
            _touch();
            setState(() {});
          },
          decoration: InputDecoration(
            hintText: l.vaultSearch,
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: Text(l.vaultAll),
              selected: !favorites,
              onSelected: (_) => setState(() => favorites = false),
            ),
            ChoiceChip(
              label: Text(l.vaultFavorites),
              avatar: const Icon(Icons.star_outline, size: 18),
              selected: favorites,
              onSelected: (_) => setState(() => favorites = true),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(
              children: [
                Icon(
                  widget.kind == VaultKind.password
                      ? Icons.key_outlined
                      : Icons.credit_card,
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
              ],
            ),
          ),
        for (final entry in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: entry.kind == VaultKind.card
                ? _bankCard(
                    theme,
                    entry,
                    onTap: () => setState(() => selected = entry),
                  )
                : Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 8,
                      ),
                      leading: CircleAvatar(
                        child: Icon(
                          entry.favorite
                              ? Icons.star_rounded
                              : Icons.key_rounded,
                        ),
                      ),
                      title: Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        entry.value('login'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => setState(() => selected = entry),
                    ),
                  ),
          ),
        const SizedBox(height: 20),
        Text(l.vaultBackupHint, style: theme.textTheme.bodySmall),
      ],
    );
  }

  Widget _bankCard(ThemeData theme, VaultEntry entry, {VoidCallback? onTap}) {
    final number = vaultCardDigits(entry.value('number'));

    return Material(
      color: theme.colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.primaryContainer,
                theme.colorScheme.secondaryContainer,
              ],
            ),
          ),
          padding: const EdgeInsets.all(22),
          child: DefaultTextStyle(
            style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.credit_card,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        entry.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    if (entry.favorite)
                      Icon(
                        Icons.star_rounded,
                        size: 20,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  number,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontSize: 21,
                    letterSpacing: 2,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  entry.value('holder'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detail(AppLocalizations l, ThemeData theme, VaultEntry entry) {
    final fields = entry.kind == VaultKind.password
        ? [
            ('login', l.vaultLogin),
            ('password', l.vaultPassword),
            ('website', l.vaultWebsite),
            ('notes', l.vaultNotes),
          ]
        : [
            ('bank', l.vaultBank),
            ('holder', l.vaultHolder),
            ('number', l.vaultNumber),
            ('expiry', l.vaultExpiry),
            ('iban', l.vaultIban),
            ('account', l.vaultAccount),
            ('notes', l.vaultNotes),
          ];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (entry.kind == VaultKind.card)
          _bankCard(theme, entry)
        else ...[
          Icon(Icons.key_rounded, color: theme.colorScheme.primary, size: 44),
          const SizedBox(height: 16),
          Text(
            entry.title,
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: busy || draft != null ? null : () => _edit(entry),
              icon: const Icon(Icons.edit_outlined),
              label: Text(l.vaultEdit),
            ),
            FilterChip(
              label: Text(l.vaultFavorite),
              selected: entry.favorite,
              avatar: const Icon(Icons.star_outline, size: 18),
              onSelected: busy
                  ? null
                  : (v) => _operate(
                      () => store.save(
                        VaultEntry(
                          id: entry.id,
                          kind: entry.kind,
                          fields: entry.fields,
                          updatedAt: DateTime.now(),
                          favorite: v,
                        ),
                      ),
                    ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        for (final (key, label) in fields)
          if (entry.value(key).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  minVerticalPadding: 16,
                  title: Text(label, style: theme.textTheme.labelMedium),
                  subtitle: Text(
                    entry.value(key),
                    textDirection:
                        [
                          'password',
                          'number',
                          'iban',
                          'expiry',
                          'account',
                          'website',
                          'login',
                        ].contains(key)
                        ? TextDirection.ltr
                        : null,
                    style: theme.textTheme.bodyLarge,
                    maxLines: key == 'notes' ? 8 : 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _copy(key, entry.value(key)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: copiedField == key ? l.vaultCopied : l.copy,
                        onPressed: () => _copy(key, entry.value(key)),
                        icon: Icon(
                          copiedField == key
                              ? Icons.check_rounded
                              : Icons.copy_outlined,
                          color: copiedField == key
                              ? theme.colorScheme.primary
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        if (copiedField != null)
          Semantics(
            liveRegion: true,
            child: Text(l.vaultCopied, textAlign: TextAlign.center),
          ),
        const SizedBox(height: 24),
        if (confirmDelete) ...[
          Text(l.vaultDeleteHint),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => setState(() => confirmDelete = false),
                child: Text(l.cancel),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () =>
                          _operate(() => store.delete(entry.id), remove: true),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                ),
                child: Text(l.vaultDeleteConfirm),
              ),
            ],
          ),
        ] else
          TextButton.icon(
            onPressed: busy ? null : () => setState(() => confirmDelete = true),
            icon: const Icon(Icons.delete_outline),
            label: Text(l.vaultDelete),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
          ),
      ],
    );
  }
}
