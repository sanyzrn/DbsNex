import '../platform/crash_reporter.dart';

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:file_selector/file_selector.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../platform/file_opener.dart';
import '../platform/vault_files.dart';
import '../platform/sharing.dart';
import '../widgets/photo_viewer.dart';
import 'camera_sheet.dart';
import '../widgets/recording_sheet.dart';
import '../widgets/nex_dialog.dart';
import '../widgets/feature_label.dart';
import '../widgets/nex_text_field.dart';
import '../platform/password_csv.dart';
import '../platform/export_cache.dart';

import 'package:path_provider/path_provider.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../documents/text_import.dart';
import '../platform/app_lock.dart';
import '../platform/display_date.dart';
import '../platform/private_clipboard.dart';
import '../platform/secure_window.dart';
import '../platform/vault_session.dart';
import '../platform/vault_store.dart';

import 'package:nex_ui/nex_ui.dart';

import 'vault_editor.dart';
import '../widgets/nex_banner.dart';
part 'vault/vault_items.dart';
part 'vault/vault_pages.dart';
part 'vault/vault_attachments.dart';
part 'vault/vault_messages.dart';

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

  /// The one secret row currently shown in the clear, as `entryId:password`.
  /// Masked by default — a password in the list was the plain text — and
  /// revealed by a tap that puts itself back after a few seconds, so a
  /// secret left open does not walk off with the phone.
  String? revealedSecret;
  Timer? revealTimer;
  Timer? idle, draftTimer, copiedTimer;
  final messageInput = TextEditingController();
  late final _vaultFiles = VaultFiles();
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

  /// [setState], for the extensions in `vault/` that draw this screen's
  /// pages and items (W4.2): an extension is not a subclass, so it cannot
  /// call the protected method itself.
  void _rebuild(VoidCallback change) => setState(change);

  @override
  void dispose() {
    messageInput.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _flushDraft();
    idle?.cancel();
    _veilHide?.cancel();
    copiedTimer?.cancel();
    revealTimer?.cancel();
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
        // Actually leaving: covered at once, and the real clearing a beat
        // later — a pause that resumes inside the beat keeps everything
        // where it was, and one that doesn't keeps nothing readable either
        // way. The veil itself was raised by the `inactive` that always
        // comes first.
        if (!authenticating && !_veiled) _cover();
        _veilHide?.cancel();
        _veilHide = Timer(const Duration(milliseconds: 600), () {
          _veilHide = null;
          if (!mounted) return;
          setState(() => _veiled = false);
          _hide();
        });
      case AppLifecycleState.inactive:
        // The shade, a system dialog, the app switcher's glance: cover, don't
        // clear. The form beneath keeps its words, its caret and its place,
        // and the veil lifts the moment the app is active again — clearing
        // here used to trade a pulled-down notification for a half-restored
        // form and a caret back at the top.
        if (!authenticating && !_veiled) _cover();
      case AppLifecycleState.resumed:
        _veilHide?.cancel();
        _veilHide = null;
        if (_veiled && mounted) setState(() => _veiled = false);
        if (authenticating) return;
        // The veil keeps everything — but time still passed while it was
        // up. The session's own deadline decides whether what it covered
        // comes back or the locked screen does; without this check a
        // background that never ran the clearing timer would come back to
        // an unlocked vault hours later.
        if (unlocked && !session.isOpen) {
          _lock();
          return;
        }
        if (unlocked) return;
        if (session.isOpen) {
          unawaited(_reload());
        } else {
          _lock();
        }
    }
  }

  /// The privacy layer over everything private: a blur and a scrim the
  /// switcher's thumbnail and a passing glance read as nothing. Nothing
  /// beneath it is touched — that is the whole point of it.
  bool _veiled = false;

  /// The pause that has not yet become a real leave.
  Timer? _veilHide;

  void _cover() {
    if (!mounted) return;
    setState(() => _veiled = true);
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
    } catch (cause) {
      unawaited(NexCrashLog.handled('vault.draft', cause));
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
      revealedSecret = null;
      revealTimer?.cancel();
      _veiled = false;
    });
  }

  /// Ends the unlock for every private tool.
  void _lock() {
    session.close();
    // Plain copies made to play or open an attachment go with the unlock.
    unawaited(VaultFiles.clearOpenCopies());
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
    } catch (cause) {
      unawaited(NexCrashLog.handled('vault.save', cause));
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
    } catch (cause) {
      unawaited(NexCrashLog.handled('vault.open', cause));
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
    } catch (cause) {
      unawaited(NexCrashLog.handled('vault.load', cause));
      if (mounted && ticket == generation) {
        setState(() => error = AppLocalizations.of(context).vaultError);
      }
    } finally {
      if (mounted && ticket == generation) setState(() => busy = false);
    }
  }

  /// Opens the editor. It does not make a draft: opening a card and leaving
  /// it, or opening a new one and typing nothing, changes nothing — and used
  /// to leave an "unfinished edit" behind that blocked everything else until
  /// it was resumed or discarded. A draft exists from the first real change.
  void _edit(VaultEntry entry) {
    setState(() {
      editing = entry;
      copiedField = null;
    });
    _touch();
  }

  /// The saved entry the editor is working on, or null for a new one.
  VaultEntry? _saved(VaultEntry entry) =>
      entries.where((e) => e.id == entry.id).firstOrNull;

  void _changed(VaultEntry entry) {
    _touch();
    draftTimer?.cancel();
    if (!vaultEntryDiffers(entry, _saved(entry))) {
      // Typed and typed back: nothing is unfinished any more.
      if (draft != null) {
        setState(() => draft = null);
        unawaited(_clearDraft());
      }
      return;
    }
    draft = entry;
    draftTimer = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_writeDraft(entry)),
    );
  }

  Future<void> _clearDraft() async {
    try {
      await store.saveDraft(null);
    } catch (cause) {
      unawaited(NexCrashLog.handled('vault.draft', cause));
    }
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
    } catch (cause) {
      unawaited(NexCrashLog.handled('vault.copy', cause));
      if (mounted && ticket == generation) {
        setState(() => error = AppLocalizations.of(context).vaultCopyFailed);
      }
    }
  }

  /// The eye beside a secret row: a few seconds of reading, then the mask
  /// returns by itself. Off the same generation ticket as [_copy], so a
  /// reveal cannot outlive the entry it belongs to.
  void _revealSecret(String field) {
    revealTimer?.cancel();
    setState(() => revealedSecret = revealedSecret == field ? null : field);
    if (revealedSecret != null) {
      revealTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => revealedSecret = null);
      });
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
    final yes = await nexShowDialog<bool>(
      context: context,
      builder: (ctx) => NexAlertDialog(
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
        child: Stack(
          children: [
            // Covered rather than cleared also means still present to a
            // screen reader: while the veil is up, nothing beneath it is
            // announced either.
            ExcludeSemantics(
              excluding: _veiled,
              child: Scaffold(
                appBar: NexAppBar(
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
                    if (unlocked &&
                        editing == null &&
                        !widget.picking &&
                        widget.focusId == null &&
                        entries.any((e) => e.kind == widget.kind))
                      NexPopupMenuButton<String>(
                        key: const ValueKey('vault-page-menu'),
                        tooltip: nexLabel(context, 'More', 'بیشتر'),
                        enabled: !busy,
                        onSelected: (_) => unawaited(_confirmDeleteAll()),
                        itemBuilder: (context) => [
                          nexMenuItem(
                            value: 'delete-all',
                            icon: Icons.delete_sweep_outlined,
                            label: _deleteAllLabel(context),
                          ),
                        ],
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
                          padding: const EdgeInsets.all(NexSpacing.md),
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
            // Over everything, including the app bar and its private title:
            // the switcher's thumbnail and a glance from beside the phone
            // read blur and scrim, and the form beneath is untouched.
            if (_veiled)
              Positioned.fill(
                key: const ValueKey('vault-veil'),
                child: AbsorbPointer(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
                    child: ColoredBox(
                      color: theme.colorScheme.surface.withValues(alpha: 0.86),
                      child: Center(
                        child: Icon(
                          Icons.lock_outline,
                          size: 32,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
