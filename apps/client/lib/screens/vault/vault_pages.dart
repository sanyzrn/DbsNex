part of '../vault_screen.dart';

/// The vault's other pages: locked, messages, and importing passwords.
extension _VaultPages on _VaultScreenState {
  Future<void> _importPasswords() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Password CSV',
          extensions: ['csv'],
          mimeTypes: ['text/csv', 'text/comma-separated-values'],
        ),
      ],
    );
    if (file == null) return;
    // The picker's copy holds every password in plain text (SEC-01): it goes
    // the moment it has been read, whichever way this ends.
    try {
      await _importPasswordsFrom(file);
    } finally {
      await discardPickedCopy(file.path, await getTemporaryDirectory());
    }
  }

  Future<void> _importPasswordsFrom(XFile file) async {
    if (!mounted) return;
    if (!unlocked) {
      await (session.isOpen ? _reload() : _unlock());
    }
    if (!mounted || !unlocked) return;
    final ticket = generation;
    final PasswordCsvResult result;
    try {
      if (await file.length() > 16 * 1024 * 1024) {
        throw const FormatException('File too large');
      }
      // UTF-8 as Chrome writes it, or UTF-16 or Windows-1256 if a
      // spreadsheet saved it again: the decoder documents import already uses.
      result = parsePasswordCsv(
        NexTextImport.decodeText(await file.readAsBytes()),
      );
    } catch (_) {
      if (mounted && unlocked && ticket == generation) {
        _rebuild(
          () => error = nexLabel(
            context,
            'This file is not a password export. Choose the CSV that Chrome or Google Password Manager exports (up to 16 MB). Nothing was imported.',
            'این فایل خروجی رمزها نیست. فایل CSV خروجی Chrome یا Google Password Manager را انتخاب کنید (تا ۱۶ مگابایت). چیزی وارد نشد.',
          ),
        );
      }
      return;
    }
    if (!mounted || !unlocked || ticket != generation) return;
    final seen = entries
        .where((e) => e.kind == VaultKind.password)
        .map(passwordIdentity)
        .toSet();
    final fresh = result.entries.where((e) => seen.add(passwordIdentity(e)));
    final count = fresh.length;
    final duplicates = result.entries.length - count;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(nexLabel(context, 'Import passwords', 'ورود رمزها')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_importSummary(context, count, duplicates)),
              if (result.problems.isNotEmpty) ...[
                const SizedBox(height: 12),
                _ImportProblems(problems: result.problems),
              ],
              const SizedBox(height: 12),
              Text(
                nexLabel(
                  context,
                  'The exported file is not encrypted; delete it after importing.',
                  'فایل خروجی رمزگذاری نشده است؛ پس از ورود آن را پاک کنید.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          if (count > 0)
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
    VaultImportOutcome? outcome;
    await _operate(() async {
      outcome = await store.importPasswords(result.entries);
    });
    final done = outcome;
    if (done == null || !mounted) return;
    nexShowBanner(
      context,
      kind: NexBannerKind.done,
      message: done.overCapacity == 0
          ? nexLabel(
              context,
              '${done.added} passwords imported',
              '${nexDigits('${done.added}', persian: true)} رمز وارد شد',
            )
          : nexLabel(
              context,
              '${done.added} passwords imported. ${done.overCapacity} did not fit: the vault holds ${VaultSnapshot.maxEntries} items.',
              '${nexDigits('${done.added}', persian: true)} رمز وارد شد. ${nexDigits('${done.overCapacity}', persian: true)} رمز جا نشد؛ ظرفیت بخش خصوصی ${nexDigits('${VaultSnapshot.maxEntries}', persian: true)} مورد است.',
            ),
    );
  }

  String _importSummary(BuildContext context, int count, int duplicates) {
    String fa(int n) => nexDigits('$n', persian: true);
    final dup = duplicates == 0
        ? ''
        : nexLabel(
            context,
            ' $duplicates already in the vault are skipped.',
            ' ${fa(duplicates)} رمزِ تکراری که از قبل هست رد می‌شود.',
          );
    return count == 0
        ? nexLabel(
            context,
            'Nothing new to import.$dup',
            'رمز تازه‌ای برای ورود نیست.$dup',
          )
        : nexLabel(
            context,
            '$count new passwords will be imported.$dup',
            '${fa(count)} رمز تازه وارد می‌شود.$dup',
          );
  }

  /// Deletes every item on this page, after a confirmation that names how
  /// many and says it cannot be undone.
  Future<void> _confirmDeleteAll() async {
    final kind = widget.kind;
    final count = entries.where((e) => e.kind == kind).length;
    if (count == 0) return;
    final l = AppLocalizations.of(context);
    final n = nexLabel(context, '$count', nexDigits('$count', persian: true));
    final what = switch (kind) {
      VaultKind.password => nexLabel(context, 'passwords', 'رمز'),
      VaultKind.card => nexLabel(context, 'cards', 'کارت'),
      VaultKind.message => nexLabel(context, 'messages', 'پیام'),
    };
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_deleteAllLabel(ctx)),
        content: Text(
          nexLabel(
            ctx,
            'All $n $what on this page will be deleted. This cannot be undone, except by restoring a backup that includes the vault.',
            'همهٔ $n $what این صفحه پاک می‌شود. این کار برگشت‌پذیر نیست، مگر با بازگرداندن پشتیبانی که بخش خصوصی را دارد.',
          ),
        ),
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
            child: Text(nexLabel(ctx, 'Delete all', 'پاک کردن همه')),
          ),
        ],
      ),
    );
    if (yes == true && mounted && unlocked) {
      await _operate(() => store.deleteAll(kind));
    }
  }

  String _deleteAllLabel(BuildContext context) => switch (widget.kind) {
    VaultKind.password => nexLabel(
      context,
      'Delete all passwords',
      'پاک کردن همهٔ رمزها',
    ),
    VaultKind.card => nexLabel(
      context,
      'Delete all cards',
      'پاک کردن همهٔ کارت‌ها',
    ),
    VaultKind.message => nexLabel(
      context,
      'Delete all messages',
      'پاک کردن همهٔ پیام‌ها',
    ),
  };

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
                child: NexTextField(
                  controller: messageInput,
                  onCopy: PrivateClipboard.copy,
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
}

/// The rows an import left out, by line, with why. Long lists show the first
/// fifty and say how many more there are.
class _ImportProblems extends StatelessWidget {
  const _ImportProblems({required this.problems});

  final List<PasswordCsvProblem> problems;

  static const _shown = 50;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final persian = Localizations.localeOf(context).languageCode == 'fa';
    String n(int v) => nexDigits('$v', persian: persian);
    String reason(PasswordCsvIssue issue) => switch (issue) {
      PasswordCsvIssue.noPassword => nexLabel(
        context,
        'no password (often a passkey or a "never save" site)',
        'بدون رمز (معمولاً کلید عبور یا سایتی که «هرگز ذخیره نشود» است)',
      ),
      PasswordCsvIssue.wrongColumns => nexLabel(
        context,
        'columns do not match the header',
        'تعداد ستون‌ها با سطر عنوان نمی‌خواند',
      ),
      PasswordCsvIssue.tooLong => nexLabel(
        context,
        'a field longer than 10,000 characters',
        'فیلدی بلندتر از ۱۰٬۰۰۰ نویسه',
      ),
      PasswordCsvIssue.unclosedQuote => nexLabel(
        context,
        'a quote that is never closed',
        'گیومه‌ای که بسته نشده',
      ),
      PasswordCsvIssue.tooMany => nexLabel(
        context,
        'past ${VaultSnapshot.maxEntries} rows',
        'بیش از ${n(VaultSnapshot.maxEntries)} ردیف',
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          nexLabel(
            context,
            '${problems.length} rows could not be read and will be left out:',
            '${n(problems.length)} ردیف خوانده نشد و وارد نمی‌شود:',
          ),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        for (final p in problems.take(_shown))
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              nexLabel(
                context,
                'Line ${p.line}: ${reason(p.issue)}',
                'سطر ${n(p.line)}: ${reason(p.issue)}',
              ),
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (problems.length > _shown)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              nexLabel(
                context,
                'and ${problems.length - _shown} more',
                'و ${n(problems.length - _shown)} ردیف دیگر',
              ),
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}
