part of '../nex_preferences.dart';

/// Who the person is, and the copy of it kept beside the library.
mixin _ProfilePreferences on _PreferencesStore {
  File? _profileMirror;

  /// Keep profile details beside the photo in media/profile, which is included
  /// in library backups. SharedPreferences can be absent after a restore even
  /// when the library survives; the mirror fills only missing keys, then is
  /// refreshed from the merged values. A deliberately cleared field is also
  /// cleared in the mirror by its setter.
  Future<void> attachProfileMirror(String mediaDir) async {
    editorDrafts = EditorDrafts(p.join(p.dirname(mediaDir), 'editor-drafts'));
    final file = File(p.join(mediaDir, 'profile', 'details.json'));
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) {
          for (final key in [
            'profile.name',
            'profile.birthday',
            'profile.bio',
          ]) {
            final value = decoded[key];
            if (!_prefs.containsKey(key) &&
                value is String &&
                value.isNotEmpty) {
              await _prefs.setString(key, value);
            }
          }
        }
      } catch (_) {
        // Preferences remain authoritative if an interrupted write left an
        // unreadable mirror. Never replace good values with a damaged copy.
      }
    }
    _profileMirror = file;
    await _writeProfileMirror();
    notifyListeners();
  }

  Future<void> _profileWrites = Future.value();

  Future<void> _writeProfileMirror() {
    final file = _profileMirror;
    if (file == null) return Future.value();
    final content = jsonEncode({
      'profile.name': _prefs.getString('profile.name'),
      'profile.birthday': _prefs.getString('profile.birthday'),
      'profile.bio': _prefs.getString('profile.bio'),
    });
    return _profileWrites = _profileWrites.then((_) async {
      try {
        await file.parent.create(recursive: true);
        final temporary = File('${file.path}.${const Uuid().v4()}.tmp');
        try {
          await temporary.writeAsString(content, flush: true);
          await temporary.rename(file.path);
        } finally {
          if (await temporary.exists()) await temporary.delete();
        }
      } catch (_) {
        // The primary preferences write succeeded. A mirror failure must not
        // strand the profile screen in its saving state.
      }
    });
  }

  /// What the app calls you, if you told it.
  ///
  /// Decoration and nothing else: it never leaves the device, is never sent
  /// with a sync or an AI request, and an empty value is stored as absent so
  /// callers only ever have to check for null.
  String? get displayName {
    final value = _prefs.getString('profile.name')?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String? get profilePhotoPath {
    final value = _prefs.getString('profile.photo')?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  DateTime? get profileBirthday {
    final value = _prefs.getString('profile.birthday');
    return value == null ? null : DateTime.tryParse(value);
  }

  String get profileBio => _prefs.getString('profile.bio') ?? '';

  /// [displayName] cut to its first two words, for the places that render it
  /// inside a line of running text.
  ///
  /// Someone who types their full name gets it back in full on the profile
  /// row, where there is room for it, and gets "Saeed Karimi" in the timeline
  /// greeting, where a third and fourth word push the line onto a second row
  /// and knock the headline below it out of place.
  String? get shortDisplayName {
    final value = displayName;
    if (value == null) return null;
    final words = value.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    return words.take(2).join(' ');
  }

  Future<void> setDisplayName(String? value) async {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      await _prefs.remove('profile.name');
    } else {
      // A name longer than this is not a name, and the app bar has to hold it.
      await _prefs.setString(
        'profile.name',
        trimmed.length > 40 ? trimmed.substring(0, 40) : trimmed,
      );
    }
    await _writeProfileMirror();
    notifyListeners();
  }

  Future<void> setProfilePhotoPath(String? value) async {
    final path = value?.trim() ?? '';
    if (path.isEmpty) {
      await _prefs.remove('profile.photo');
    } else {
      await _prefs.setString('profile.photo', path);
    }
    notifyListeners();
  }

  Future<void> setProfileBirthday(DateTime? value) async {
    if (value == null) {
      await _prefs.remove('profile.birthday');
    } else {
      await _prefs.setString(
        'profile.birthday',
        DateTime(value.year, value.month, value.day).toIso8601String(),
      );
    }
    await _writeProfileMirror();
    notifyListeners();
  }

  Future<void> setProfileBio(String value) async {
    await _setBoundedText('profile.bio', value, 300);
    await _writeProfileMirror();
  }
}
