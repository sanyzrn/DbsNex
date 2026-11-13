part of 'translate_sheet.dart';

class _TranslationLanguagePicker extends StatefulWidget {
  const _TranslationLanguagePicker({required this.selected});
  final NexTranslationLanguage selected;
  @override
  State<_TranslationLanguagePicker> createState() =>
      _TranslationLanguagePickerState();
}

class _TranslationLanguagePickerState
    extends State<_TranslationLanguagePicker> {
  String _query = '';
  bool _more = false;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final query = _query.trim().toLowerCase();
    final languages = NexTranslationLanguage.values
        .where(
          (language) =>
              query.isEmpty ||
              '${language.english} ${language.native} ${language.persian} ${language.code}'
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
    final visible = query.isNotEmpty || _more
        ? languages
        : languages.take(NexTranslationLanguage.commonCount).toList();
    return Padding(
      padding: const EdgeInsets.all(NexSpacing.md),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.translationChooseLanguage,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: NexSpacing.md),
            NexSearchField(
              controller: _search,
              fieldKey: const ValueKey('translation-language-search'),
              hintText: l10n.search,
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: NexSpacing.sm),
            Expanded(
              child: ListView(
                children: [
                  for (final language in visible)
                    ListTile(
                      key: ValueKey('translation-language-${language.code}'),
                      title: Text(_languageName(language.code, l10n)),
                      subtitle:
                          language.native == _languageName(language.code, l10n)
                          ? null
                          : Text(language.native),
                      trailing: language.code == widget.selected.code
                          ? Icon(
                              Icons.check,
                              color: Theme.of(context).colorScheme.primary,
                            )
                          : null,
                      onTap: () => Navigator.pop(context, language),
                    ),
                  if (query.isEmpty && !_more)
                    TextButton(
                      onPressed: () => setState(() => _more = true),
                      child: Text(l10n.translationMoreLanguages),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
