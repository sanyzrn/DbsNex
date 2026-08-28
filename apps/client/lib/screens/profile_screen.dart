import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_localizations.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import '../widgets/nex_banner.dart';

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

class _ProfileScreenState extends State<ProfileScreen> {
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
      final extension = p.extension(picked.path).toLowerCase();
      final target = p.join(
        directory.path,
        'avatar${extension.isEmpty ? '.jpg' : extension}',
      );
      final old = widget.preferences.profilePhotoPath;
      await File(picked.path).copy(target);
      if (old != null && old != target) {
        final oldFile = File(old);
        if (await oldFile.exists()) await oldFile.delete();
      }
      await widget.preferences.setProfilePhotoPath(target);
      if (mounted) setState(() {});
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
    final path = widget.preferences.profilePhotoPath;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    await widget.preferences.setProfilePhotoPath(null);
    if (mounted) setState(() {});
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthday ?? DateTime(now.year - 25),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null && mounted) setState(() => _birthday = picked);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.preferences.setDisplayName(_name.text);
    await widget.preferences.setProfileBio(_bio.text);
    await widget.preferences.setProfileBirthday(_birthday);
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final photo = widget.preferences.profilePhotoPath;
    final photoFile = photo == null ? null : File(photo);
    final hasPhoto = photoFile?.existsSync() ?? false;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.profileTitle),
        actions: [
          TextButton(onPressed: _saving ? null : _save, child: Text(l10n.save)),
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
                  backgroundImage: hasPhoto ? FileImage(photoFile!) : null,
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
                  : MaterialLocalizations.of(
                      context,
                    ).formatMediumDate(_birthday!),
            ),
            trailing: _birthday == null
                ? const Icon(Icons.chevron_right)
                : IconButton(
                    tooltip: l10n.clear,
                    onPressed: () => setState(() => _birthday = null),
                    icon: const Icon(Icons.close),
                  ),
            onTap: _pickBirthday,
          ),
          const SizedBox(height: NexSpacing.md),
          NexAutoDirection(
            controller: _bio,
            builder: (context, direction) => TextField(
              controller: _bio,
              maxLength: 300,
              minLines: 3,
              maxLines: 6,
              textDirection: direction,
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
          ),
        ],
      ),
    );
  }
}
