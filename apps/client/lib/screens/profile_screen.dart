import 'dart:async';
import 'dart:io';
import 'dart:ui' show BoxWidthStyle;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_localizations.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import '../platform/profile_photo.dart';
import '../widgets/nex_banner.dart';
import '../widgets/draft_guard.dart';
import '../widgets/nex_time_picker.dart';
import '../platform/display_date.dart';
import '../widgets/nex_text_field.dart';
import '../widgets/keyboard_dismisser.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.services,
    required this.preferences,
  });

  final NexServices services;
  final NexPreferences preferences;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with NexDraftGuard<ProfileScreen> {
  @override
  bool get hasUnsavedChanges =>
      _name.text != (widget.preferences.displayName ?? '') ||
      _bio.text != widget.preferences.profileBio ||
      _birthday != widget.preferences.profileBirthday;
  @override
  void discardDraft() => widget.preferences.editorDrafts?.clear('profile');
  void _snapshot() {
    widget.preferences.editorDrafts?.write('profile', {
      'name': _name.text,
      'bio': _bio.text,
      'birthday': _birthday?.toIso8601String(),
    });
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    final draft = widget.preferences.editorDrafts?.read('profile');
    if (draft != null) {
      _name.text = draft['name'] as String? ?? _name.text;
      _bio.text = draft['bio'] as String? ?? _bio.text;
      _birthday = DateTime.tryParse(draft['birthday'] as String? ?? '');
    }
    _name.addListener(_snapshot);
    _bio.addListener(_snapshot);
  }

  late final TextEditingController _name = TextEditingController(
    text: widget.preferences.displayName ?? '',
  );
  late final TextEditingController _bio = TextEditingController(
    text: widget.preferences.profileBio,
  );
  late DateTime? _birthday = widget.preferences.profileBirthday;
  bool _saving = false;

  @override
  void dispose() {
    _name.removeListener(_snapshot);
    _bio.removeListener(_snapshot);
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
      maxWidth: 1600,
    );
    if (picked == null) return;
    try {
      final directory = Directory(p.join(widget.services.mediaDir, 'profile'));
      await directory.create(recursive: true);
      final target = nextProfilePhotoPath(
        widget.services.mediaDir,
        p.extension(picked.path).toLowerCase(),
      );
      await File(picked.path).copy(target);
      await widget.preferences.setProfilePhotoPath(target);
      if (mounted) setState(() {});
      // The old picture goes after the new one is showing.
      _forgetPhotos(except: target);
    } catch (_) {
      if (!mounted) return;
      nexShowBanner(
        context,
        message: AppLocalizations.of(context).profilePhotoFailed,
        kind: NexBannerKind.failed,
      );
    }
  }

  Future<void> _removePhoto() async {
    // Every picture, not only the current one: recovery finds any avatar
    // left in the folder, so one left behind would appear to come back.
    // Synchronously, before the next frame, so the removed picture is gone
    // the moment the button is pressed.
    _forgetPhotos();
    await widget.preferences.setProfilePhotoPath(null);
    if (mounted) setState(() {});
  }

  /// Deletes the kept pictures, but [except], and drops them from the image
  /// cache so nothing on screen can keep drawing one.
  void _forgetPhotos({String? except}) {
    for (final file in profilePhotoFiles(widget.services.mediaDir)) {
      if (file.path == except) continue;
      unawaited(FileImage(file).evict());
      try {
        file.deleteSync();
      } catch (_) {
        // A file already gone is the outcome wanted.
      }
    }
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final picked = await nexPickDate(
      context,
      solar: widget.preferences.solarCalendar,
      initial: _birthday ?? DateTime(now.year - 25),
      first: DateTime(1900),
      last: now,
    );
    if (picked != null && mounted) {
      setState(() => _birthday = picked);
      _snapshot();
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.preferences.setDisplayName(_name.text);
      await widget.preferences.setProfileBio(_bio.text);
      await widget.preferences.setProfileBirthday(_birthday);
      widget.preferences.editorDrafts?.clear('profile');
      if (!mounted) return;
      Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        nexShowBanner(
          context,
          message: AppLocalizations.of(context).captureFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final photoFile = resolveProfilePhoto(
      widget.services.mediaDir,
      widget.preferences.profilePhotoPath,
    );
    final hasPhoto = photoFile != null;
    return guardDraft(
      Scaffold(
        appBar: AppBar(
          title: Text(l10n.profileTitle),
          actions: [
            NexTypingAction(
              child: TextButton(
                onPressed: _saving ? null : _save,
                child: Text(l10n.save),
              ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(NexSpacing.md),
          children: [
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 52,
                    backgroundColor: theme.colorScheme.surfaceContainerHigh,
                    backgroundImage: hasPhoto ? FileImage(photoFile) : null,
                    child: hasPhoto
                        ? null
                        : Icon(
                            Icons.person_outline,
                            size: 44,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                  ),
                  PositionedDirectional(
                    end: 0,
                    bottom: 0,
                    child: IconButton.filled(
                      tooltip: l10n.profileChangePhoto,
                      onPressed: _pickPhoto,
                      icon: const Icon(Icons.photo_camera_outlined),
                    ),
                  ),
                ],
              ),
            ),
            if (hasPhoto)
              TextButton(
                onPressed: _removePhoto,
                child: Text(l10n.profileRemovePhoto),
              ),
            const SizedBox(height: NexSpacing.lg),
            NexAutoDirection(
              controller: _name,
              builder: (context, direction) => TextField(
                controller: _name,
                selectionWidthStyle: BoxWidthStyle.tight,
                contextMenuBuilder: nexReadingMenu,
                maxLength: 40,
                textDirection: direction,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: l10n.yourName,
                  prefixIcon: const Icon(Icons.badge_outlined),
                ),
              ),
            ),
            const SizedBox(height: NexSpacing.md),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.cake_outlined),
              title: Text(l10n.profileBirthday),
              subtitle: Text(
                _birthday == null
                    ? l10n.profileBirthdayEmpty
                    : nexDisplayDate(
                        _birthday!,
                        solar: widget.preferences.solarCalendar,
                        persian: l10n.localeName == 'fa',
                      ),
              ),
              trailing: _birthday == null
                  ? const Icon(Icons.chevron_right)
                  : IconButton(
                      tooltip: l10n.clear,
                      onPressed: () {
                        setState(() => _birthday = null);
                        _snapshot();
                      },
                      icon: const Icon(Icons.close),
                    ),
              onTap: _pickBirthday,
            ),
            const SizedBox(height: NexSpacing.md),
            NexTextField(
              controller: _bio,
              maxLength: 300,
              minLines: 3,
              maxLines: 6,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                labelText: l10n.profileBio,
                hintText: l10n.profileBioHint,
                alignLabelWithHint: true,
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(bottom: 72),
                  child: Icon(Icons.notes_outlined),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
