part of '../vault_screen.dart';

/// The vault's other pages: locked, messages, and importing passwords.
extension _VaultPages on _VaultScreenState {
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
        _rebuild(
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
