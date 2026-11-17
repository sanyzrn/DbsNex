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
    this.files,
    this.authentication,
    this.focusId,
    this.picking = false,
    this.biometricOnly = false,
  });
  final VaultKind kind;
  final VaultStore? store;
  final VaultFiles? files;
  final AppLockService? authentication;

  /// Show only this entry — a Recurring item's linked card (W5.4). The
  /// unlock is the same as ever; only what is listed after it changes.
  final String? focusId;

  /// Choosing a card to link: tapping one pops with its id. Nothing about
  /// the card leaves the vault; the id is all the caller keeps.
  final bool picking;

  /// Whether the vault's own unlock may offer only the fingerprint, never
  /// the device's PIN or pattern. The Security screen's "Biometrics only"
  /// switch says the same thing for the app's gate, and the vault — the
  /// more sensitive of the two — must not quietly ask for less
  /// (SEC-01). A device without biometrics answers the same refusal the
  /// gate gives; this defaults to the previous behaviour for callers that
  /// do not say.
  final bool biometricOnly;
  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> with WidgetsBindingObserver {
  late final store = widget.store ?? VaultStore();

  /// The attachments of private messages. Injectable like [store] — a
  /// widget test runs in a fake-async zone another isolate never talks to.
  late final _vaultFiles = widget.files ?? VaultFiles();
  late final auth = widget.authentication ?? AppLockService();
  late final Future<bool> protection;
  final session = VaultSession.instance;
  final search = TextEditingController();
  List<VaultEntry> entries = [];
  VaultEntry? draft, editing;

  /// The vault list's filter/sort memo, one entry deep — see
  /// `_visibleEntries` in vault_items.dart.
  _VaultFilterCache? _filterCache;
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
  int generation = 0;

  /// Whether the editor was open when the app went to the background, so a
  /// return inside the grace period lands back in it rather than on the list.
  bool _resumeEditing = false;
  Future<void>? _loading;

  /// Routes this screen pushed that show private content in the clear: the
  /// fullscreen photo and the recording sheet. The vault's own tree is
  /// emptied by [_hide], but a route lives in the navigator, above this
  /// screen, and nothing else was closing it — a locked vault could be
  /// resumed onto a decrypted photo no prompt had been asked for
  /// (SEC-02). They go when the unlock ends.
  final Set<Route<void>> _privateRoutes = {};

  /// Pushes [route] and remembers it for [_lock] to close.
  void _pushPrivate(Route<void> route) {
    _privateRoutes.add(route);
    route.popped.whenComplete(() => _privateRoutes.remove(route));
    Navigator.of(context).push(route);
  }

  /// Registers a route this screen did not push itself — a modal sheet —
  /// for the same closing. The builder's context is where the route can be
  /// found; the assignment runs again on every rebuild and is idempotent.
  void _keepPrivateRoute(BuildContext inside) {
    final route = ModalRoute.of(inside);
    if (route != null) _privateRoutes.add(route);
    route?.popped.whenComplete(() => _privateRoutes.remove(route));
  }

  /// Closes everything private this screen left above it. `removeRoute`
  /// rather than `pop`: a pop would animate, and would run the route's own
  /// pop logic (which for the recording sheet hands back "discarded", and
  /// for the photo viewer runs a dismiss animation on content that must be
  /// gone already).
  void _closePrivateRoutes() {
    for (final route in _privateRoutes) {
      if (route.isActive) route.navigator?.removeRoute(route);
    }
    _privateRoutes.clear();
  }

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
    _removeVeil();
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
        // A biometric reply after real backgrounding must never unlock.
        // Inactive alone is expected during authentication prompts.
        if (authenticating) {
          generation++;
          setState(() {
            authenticating = false;
            busy = false;
          });
        }
        if (!_veiled) _cover();
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
        if (_veiled && mounted) {
          setState(() => _veiled = false);
          _syncVeil();
        }
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
  ///
  /// It lives in the **root overlay**, not in this screen's tree. The screen
  /// only sees itself; the fullscreen photo and the recording sheet are
  /// routes *above* it in the navigator, and a veil that was part of this
  /// screen never covered them — the shade's glance and the switcher
  /// thumbnail read a decrypted photo the vault believed was hidden
  /// (SEC-02). An entry in the root overlay covers every route of this
  /// navigator at once, whatever is pushed when the veil goes up.
  bool _veiled = false;
  OverlayEntry? _veilEntry;

  /// The pause that has not yet become a real leave.
  Timer? _veilHide;

  void _cover() {
    if (!mounted) return;
    setState(() => _veiled = true);
    _syncVeil();
  }

  /// Puts the veil over the whole navigator, or takes it down.
  ///
  /// Called from the same places that set [_veiled], so the two can never
  /// disagree; the entry is removed exactly once by keeping it in a nullable
  /// field. If there is no overlay to hang it on — a screen tested outside
  /// a `WidgetsApp` — the veil inside the tree below is the fallback.
  void _syncVeil() {
    if (_veiled && _veilEntry == null) {
      final overlay = Overlay.maybeOf(context, rootOverlay: true);
      if (overlay != null) {
        // Not opaque: an opaque entry stops what is under it from being
        // painted at all, and the blur would have nothing to blur — the veil
        // would become a flat grey sheet instead of the frosted cover it
        // has always been. The blur and the scrim are what hide; the hit
        // test is absorbed and the semantics blocked either way.
        _veilEntry = OverlayEntry(
          builder: (_) => const _VaultVeil(key: ValueKey('vault-veil')),
        );
        overlay.insert(_veilEntry!);
      }
    } else if (!_veiled && _veilEntry != null) {
      _removeVeil();
    }
  }

  void _removeVeil() {
    _veilEntry?.remove();
    _veilEntry = null;
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
    // A copied secret has no reason to outlive the screen that copied it:
    // the wipe that would have come at the timer's leisure comes now
    // (SEC-05). On Android the native sweep owns this and nothing is
    // outstanding here; on the desktop the clipboard is the only copy.
    unawaited(PrivateClipboard.sweepNow());
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
    _syncVeil();
  }

  /// Ends the unlock for every private tool.
  void _lock() {
    session.close();
    // Plain copies made to play or open an attachment go with the unlock,
    // and so does anything they were playing or showing: a route is above
    // this screen in the navigator, and leaving one up put a decrypted
    // photo or a live recording over a locked vault (SEC-02).
    _closePrivateRoutes();
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
      // The Security screen's "Biometrics only" switch is the user saying
      // the device's PIN may never open what is theirs; the vault is the
      // most private surface in the app and must not quietly ask for less
      // (SEC-01).
      final accepted = await auth.authenticate(
        reason: l.vaultAuthReason,
        biometricOnly: widget.biometricOnly,
      );
      if (!mounted || ticket != generation) return;
      if (!accepted) {
        // A plain cancel says nothing (lastFailure is null) and deserves no
        // red text or "open settings" — an error shown for changing your
        // mind teaches that the error can be ignored. Only a real refusal
        // from the phone is said (SEC-07).
        if (auth.lastFailure != null) {
          setState(() => error = l.vaultUnavailable);
        }
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
            // The fallback, for the rare embedding with no root overlay:
            // the veil over this screen's own tree. With an overlay, the
            // veil is an entry in it (see [_syncVeil]) and covers the
            // routes above this screen — the fullscreen photo, the
            // recording sheet — as well.
            if (_veiled && _veilEntry == null)
              Positioned.fill(
                key: const ValueKey('vault-veil'),
                child: const _VaultVeil(),
              ),
          ],
        ),
      ),
    );
  }
}

/// Blur and scrim, and nothing readable under it: what the root overlay
/// hangs over the whole navigator while the vault is covered, and what the
/// screen itself shows when no overlay could be found. A blur rather than a
/// blank cover, so the shape beneath stays legible as "something is there
/// and it is none of your business".
///
/// [BlockSemantics] carries the covering into the screen-reader tree too:
/// nothing beneath the veil is announced while it is up — not this screen's
/// content, and not a route pushed above it.
class _VaultVeil extends StatelessWidget {
  const _VaultVeil({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AbsorbPointer(
      child: BlockSemantics(
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
    );
  }
}
