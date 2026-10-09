part of '../nex_preferences.dart';

/// The assistant and the AI provider: which provider, how it answers, what it
/// may see.
mixin _AiPreferences on _PreferencesStore {
  /// Whether the terms for a downloadable model have been shown and agreed to.
  ///
  /// Keyed per model, not a single flag: accepting Gemma's terms says nothing
  /// about a different model under a different licence, and the app is
  /// expected to offer more than one eventually.
  ///
  /// Recorded because the licence requires the terms reach every recipient
  /// before distribution, and a record of that is what makes it verifiable
  /// rather than assumed — see 09-ai.md.
  bool acceptedModelLicense(String modelId) =>
      _prefs.getBool('ai.model.license.$modelId') ?? false;

  Future<void> acceptModelLicense(String modelId) async {
    await _prefs.setBool('ai.model.license.$modelId', true);
    notifyListeners();
  }

  bool get cloudAiOptIn => _prefs.getBool('ai.cloud_opt_in') ?? false;

  AiCapabilities get aiCapabilities => AiCapabilities(
    transcription: _prefs.getBool('ai.transcription') ?? true,
    ocr: _prefs.getBool('ai.ocr') ?? true,
    tagSuggestions: _prefs.getBool('ai.tags') ?? true,
    semanticSearch: _prefs.getBool('ai.semantic') ?? true,
    summarization: _prefs.getBool('ai.summary') ?? true,
    relatedNotes: _prefs.getBool('ai.related') ?? true,
  );

  /// Personal-assistant tier (09-ai.md — Free vs. Paid Boundary, ADR-030).
  /// No payment processor exists yet, so this defaults to `free` and nothing
  /// in the app currently offers a way to change it — it exists so the
  /// gating hook (`GatedToolExecutor`) has somewhere real to read from.
  AiEntitlement get aiEntitlement => AiEntitlement.values.firstWhere(
    (e) => e.name == _prefs.getString('ai.entitlement'),
    orElse: () => AiEntitlement.free,
  );

  Future<void> setCloudAiOptIn(bool value) =>
      _setBool('ai.cloud_opt_in', value);

  Future<void> setAiEntitlement(AiEntitlement value) async {
    await _prefs.setString('ai.entitlement', value.name);
    notifyListeners();
  }

  Future<void> setAiCapabilities(AiCapabilities value) async {
    await _prefs.setBool('ai.transcription', value.transcription);
    await _prefs.setBool('ai.ocr', value.ocr);
    await _prefs.setBool('ai.tags', value.tagSuggestions);
    await _prefs.setBool('ai.semantic', value.semanticSearch);
    await _prefs.setBool('ai.summary', value.summarization);
    await _prefs.setBool('ai.related', value.relatedNotes);
    notifyListeners();
  }

  /* ------------------------------------------------------------ AI provider */

  /// The master switch for everything in the intelligence layer.
  ///
  /// Off until the user turns it on and accepts what that means. The product
  /// promise is that Nex works fully offline; the intelligence layer is the one
  /// part that can send a note somewhere else, so it does not start enabled and
  /// the individual capability switches do nothing while this is off.
  bool get aiEnabled => _prefs.getBool('ai.enabled') ?? false;

  Future<void> setAiEnabled(bool value) async {
    await _prefs.setBool('ai.enabled', value);
    notifyListeners();
  }

  /// The capabilities actually in force: all off while the master switch is.
  /// Where the on-device search model is, once it has been installed and
  /// shown to run; null while it is not. See `NexServices.activeSearchModel`
  /// for why the file is checked as well.
  String? get searchModelPath => _prefs.getString('ai.searchModel.path');

  Future<void> setSearchModelPath(String? path) async {
    if (path == null) {
      await _prefs.remove('ai.searchModel.path');
    } else {
      await _prefs.setString('ai.searchModel.path', path);
    }
    notifyListeners();
  }

  AiCapabilities get effectiveAiCapabilities =>
      aiEnabled ? aiCapabilities : AiCapabilities.allOff;

  // The key/baseUrl/model are namespaced per provider rather than kept in one
  // shared slot: a single slot meant switching from, say, Claude to OpenAI
  // left Claude's key sitting in the OpenAI field, since there was only ever
  // one to overwrite. Each provider now keeps its own, so switching back to
  // one configured earlier restores what was saved for it.
  //
  // Only the key lives in secure storage — see [_secureApiKeys]. baseUrl and
  // model are not credentials, and keeping them in plain `_prefs` is what
  // lets every other getter here stay a synchronous read against one store.
  AiProviderConfig get aiProvider =>
      configFor(AiProviderWire.fromWire(_prefs.getString('ai.provider')));

  /// What is stored for [provider] specifically, whether or not it is the
  /// active one — how the provider screen fills its fields in when the user
  /// is only looking at (not yet saving) a different provider.
  AiProviderConfig configFor(AiProvider provider) => AiProviderConfig(
    provider: provider,
    apiKey: _secureApiKeys[provider.wireName] ?? '',
    baseUrl: _prefs.getString('ai.baseUrl.${provider.wireName}') ?? '',
    model: _prefs.getString('ai.model.${provider.wireName}') ?? '',
  );

  /// Which language the model answers in — independent of [locale].
  ///
  /// Not folded into [AiProviderConfig]: that is per-provider storage, and
  /// this is one global choice. Putting it there would have meant writing the
  /// same value under every provider's namespace and picking a winner when
  /// they disagreed.
  AiOutputLanguage get aiOutputLanguage =>
      AiOutputLanguage.fromWire(_prefs.getString('ai.outputLanguage'));

  Future<void> setAiOutputLanguage(AiOutputLanguage value) async {
    await _prefs.setString('ai.outputLanguage', value.wireName);
    // The two cached AI strings on the timeline were written in the old
    // language; leaving them would show the setting as having done nothing
    // until tomorrow.
    await _prefs.remove('ai.daySummary.text');
    await _prefs.remove('ai.daySummary.date');
    await _prefs.remove('ai.headline.text');
    await _prefs.remove('ai.headline.date');
    notifyListeners();
  }

  Future<void> setAiProvider(AiProviderConfig config) async {
    final wireName = config.provider.wireName;
    final key = 'ai.key.$wireName';
    await _prefs.setString('ai.provider', wireName);
    if (config.apiKey.isEmpty) {
      // An empty field is not proof the key is gone: when secure storage
      // could not be read at launch the field simply had nothing to show,
      // and saving the screen then deleted the one copy of a key that was
      // still stored. Only a key this session actually read can be cleared.
      if (!secureStorageUnavailable || _secureApiKeys.containsKey(wireName)) {
        await _secureStorage.delete(key: key);
      }
      _secureApiKeys.remove(wireName);
    } else {
      await _secureStorage.write(key: key, value: config.apiKey);
      _secureApiKeys[wireName] = config.apiKey;
    }
    await _prefs.remove(key);
    await _prefs.setString('ai.baseUrl.$wireName', config.baseUrl);
    await _prefs.setString('ai.model.$wireName', config.model);
    notifyListeners();
  }

  /* ------------------------------------------------------------- Assistant */

  /// Saved assistant conversations.
  ///
  /// Reached through here rather than constructed alongside this because it
  /// is backed by the same preference store and needs nothing else — hanging
  /// it off the object that already owns that store is one dependency to
  /// thread through the widget tree instead of two. It is still its own
  /// [ChangeNotifier]: the conversation list rebuilds when a thread is saved
  /// or deleted, and nothing else in the app should rebuild for that.
  late final ChatHistory chatHistory = ChatHistory(_prefs);

  /// How far the assistant may wander from the plainest answer.
  AiCreativity get aiCreativity =>
      AiCreativity.fromWire(_prefs.getString('ai.creativity'));

  Future<void> setAiCreativity(AiCreativity value) async {
    await _prefs.setString('ai.creativity', value.wireName);
    notifyListeners();
  }

  /// How long its answers are allowed to be.
  AiAnswerLength get aiAnswerLength =>
      AiAnswerLength.fromWire(_prefs.getString('ai.answerLength'));

  Future<void> setAiAnswerLength(AiAnswerLength value) async {
    await _prefs.setString('ai.answerLength', value.wireName);
    notifyListeners();
  }

  /// How the assistant should sound — one of five presets, or the user's own
  /// sentence.
  ///
  /// Tone used to have two controls: these presets, and a free-text
  /// instruction in a section of its own. That is two answers to one
  /// question — pick "Formal", write "be witty and sarcastic", and nothing
  /// says which the assistant follows. `custom` folds the second into the
  /// first: it is the preset you write yourself.
  ///
  /// Which leaves the people who wrote an instruction before there was a
  /// preset for it. Their style key was never written — they never touched
  /// the presets — so it is derived rather than migrated: an untouched style
  /// with an instruction behind it *is* a custom style, and reading it that
  /// way keeps their sentence working without writing anything to their
  /// preferences on their behalf.
  AiResponseStyle get aiResponseStyle {
    final stored = _prefs.getString('ai.responseStyle');
    if (stored == null && aiInstruction.trim().isNotEmpty) {
      return AiResponseStyle.custom;
    }
    return AiResponseStyle.fromWire(stored);
  }

  Future<void> setAiResponseStyle(AiResponseStyle value) async {
    await _prefs.setString('ai.responseStyle', value.wireName);
    notifyListeners();
  }

  String get aiUserName => _prefs.getString('ai.userName') ?? '';

  Future<void> setAiUserName(String value) async {
    await _setBoundedText(
      'ai.userName',
      value,
      NexPreferences.aiUserNameMaxLength,
    );
  }

  String get aiUserIntroduction =>
      _prefs.getString('ai.userIntroduction') ?? '';

  Future<void> setAiUserIntroduction(String value) async {
    await _setBoundedText(
      'ai.userIntroduction',
      value,
      NexPreferences.aiUserIntroductionMaxLength,
    );
  }

  /// Whether the assistant stays inside the user's notes and this app.
  ///
  /// Defaults to true, and the default is the point: this is a notes app's
  /// assistant, and the first time someone opens it they should find
  /// something that knows their notes rather than a general chatbot that
  /// happens to live here.
  bool get aiNotesOnly => _prefs.getBool('ai.notesOnly') ?? true;

  Future<void> setAiNotesOnly(bool value) async {
    await _prefs.setBool('ai.notesOnly', value);
    notifyListeners();
  }

  String get aiInstruction => _prefs.getString('ai.instruction') ?? '';

  Future<void> setAiInstruction(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await _prefs.remove('ai.instruction');
    } else {
      await _prefs.setString(
        'ai.instruction',
        trimmed.length <= NexPreferences.aiInstructionMaxLength
            ? trimmed
            : trimmed.substring(0, NexPreferences.aiInstructionMaxLength),
      );
    }
    notifyListeners();
  }

  /// Whether the smart summary and the greeting may use as many tokens as
  /// the provider allows, instead of the few hundred they are normally held
  /// to. Off by default: the summary refreshes many times a day, and a cap is
  /// what keeps that cheap. It exists for "thinking" models, which spend
  /// their budget reasoning before they write and come back empty under it.
  bool get aiSummaryUnlimited =>
      _prefs.getBool('brief.unlimited_tokens') ?? false;

  Future<void> setAiSummaryUnlimited(bool value) async {
    await _prefs.setBool('brief.unlimited_tokens', value);
    notifyListeners();
  }

  /// How many recent notes are sent with each question.
  ///
  /// A privacy setting before it is a quality one. Every one of these leaves
  /// the device and reaches whichever provider is configured, so the amount
  /// is the user's to choose — and zero is a real choice, not a broken one:
  /// the assistant still answers about the app itself.
  int get aiNotesContextCount {
    final stored = _prefs.getInt('ai.notesContext') ?? 20;
    return NexPreferences.aiNotesContextChoices.contains(stored) ? stored : 20;
  }

  Future<void> setAiNotesContextCount(int value) async {
    await _prefs.setInt('ai.notesContext', value);
    notifyListeners();
  }
}
