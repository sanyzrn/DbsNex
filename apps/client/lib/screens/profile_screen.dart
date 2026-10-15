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
import '../widgets/nex_dialog.dart';
import '../widgets/draft_guard.dart';
import '../widgets/nex_time_picker.dart';
import '../platform/display_date.dart';
import '../widgets/nex_text_field.dart';
import 'camera_sheet.dart';
import 'profile/profile_header.dart';

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
    widget.preferences.editorDrafts?.writeSoon('profile', {
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

  /// The choices behind the picture: a new one from the gallery or the
  /// camera, or none. Removing used to be a full-width text button under the
  /// picture, so a tap anywhere along that line took the photo away; it now
  /// sits here, one deliberate step from the page.
  Future<void> _choosePhoto(bool hasPhoto) async {
    final l10n = AppLocalizations.of(context);
    final error = Theme.of(context).colorScheme.error;
    final choice = await nexShowSheet<String>(
      context: context,
      builder: (sheet) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: NexSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NexSpacing.lg,
                0,
                NexSpacing.lg,
                NexSpacing.sm,
              ),
              child: Text(
                l10n.profilePhotoTitle,
                style: Theme.of(sheet).textTheme.titleMedium,
              ),
            ),
            ListTile(
              key: const ValueKey('profile-photo-gallery'),
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.profilePhotoGallery),
              onTap: () => Navigator.pop(sheet, 'gallery'),
            ),
            ListTile(
              key: const ValueKey('profile-photo-camera'),
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l10n.profilePhotoCamera),
              onTap: () => Navigator.pop(sheet, 'camera'),
            ),
            if (hasPhoto)
              ListTile(
                key: const ValueKey('profile-photo-remove'),
                leading: Icon(Icons.delete_outline, color: error),
                title: Text(
                  l10n.profileRemovePhoto,
                  style: TextStyle(color: error),
                ),
                onTap: () => Navigator.pop(sheet, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'remove') return _removePhoto();
    final taking = choice == 'camera'
        ? nexTakePhoto(context)
        : ImagePicker().pickImage(
            source: ImageSource.gallery,
            imageQuality: 90,
            maxWidth: 1600,
          );
    final picked = await taking;
    if (picked == null) return;
    await _setPhoto(picked);
  }

  Future<void> _setPhoto(XFile picked) async {
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
    final photoFile = resolveProfilePhoto(
      widget.services.mediaDir,
      widget.preferences.profilePhotoPath,
    );
    final hasPhoto = photoFile != null;
    final persian = l10n.localeName == 'fa';
    final birthday = _birthday == null
        ? null
        : profileBirthdayInfo(
            _birthday!,
            DateTime.now(),
            solar: widget.preferences.solarCalendar,
          );
    return guardDraft(
      Scaffold(
        appBar: NexAppBar(
          title: Text(l10n.profileTitle),
          actions: [
            TextButton(
              onPressed: _saving ? null : _save,
              child: Text(l10n.save),
            ),
          ],
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(
            NexSpacing.md,
            NexSpacing.sm,
            NexSpacing.md,
            NexSpacing.lg + nexBottomInset(context),
          ),
          children: [
            ProfileHeader(
              photo: photoFile,
              name: _name.text,
              bio: _bio.text,
              birthdayColor:
                  const {
                    'classic',
                    'graphite',
                  }.contains(widget.preferences.themePreset)
                  ? Theme.of(context).colorScheme.onSurface
                  : null,
              birthdayLine: birthday == null
                  ? null
                  : profileBirthdayCountdown(l10n, birthday.daysUntil),
              onPhoto: () => unawaited(_choosePhoto(hasPhoto)),
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
            const SizedBox(height: NexSpacing.sm),
            _BirthdayRow(
              text: _birthday == null
                  ? l10n.profileBirthdayEmpty
                  : [
                      nexDisplayDate(
                        _birthday!,
                        solar: widget.preferences.solarCalendar,
                        persian: persian,
                      ),
                      l10n.profileAge(
                        nexDigits('${birthday!.age}', persian: persian),
                      ),
                    ].join(' · '),
              onTap: _pickBirthday,
              onClear: _birthday == null
                  ? null
                  : () {
                      setState(() => _birthday = null);
                      _snapshot();
                    },
            ),
            const SizedBox(height: NexSpacing.lg),
            // No icon in front: beside a box several lines tall it either
            // floats in the middle or has to be pushed up by hand, and the
            // label was never where the icon ended up.
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The birthday as a card of its own: date and age, the whole row opening the
/// picker, and a clear button once one is set.
class _BirthdayRow extends StatelessWidget {
  const _BirthdayRow({required this.text, required this.onTap, this.onClear});

  final String text;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final onClear = this.onClear;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(NexRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('profile-birthday'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            NexSpacing.md,
            NexSpacing.sm,
            NexSpacing.xs,
            NexSpacing.sm,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(NexRadius.md),
                ),
                child: Icon(
                  Icons.cake_outlined,
                  size: 20,
                  color: scheme.onTertiaryContainer,
                ),
              ),
              const SizedBox(width: NexSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.profileBirthday,
                      style: theme.textTheme.bodyLarge,
                    ),
                    Text(
                      text,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (onClear != null)
                IconButton(
                  tooltip: l10n.clear,
                  onPressed: onClear,
                  icon: const Icon(Icons.close),
                )
              else
                const Padding(
                  padding: EdgeInsets.all(NexSpacing.sm),
                  child: Icon(Icons.chevron_right),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
