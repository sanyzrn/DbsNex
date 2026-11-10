import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../platform/device_label.dart';
import 'nex_banner.dart';

/// Copies [text] and acknowledges it in the app's one voice.
///
/// Three paths used to give three receipts for the same act: the hold menu
/// copied in silence (nothing at all on Android 7–12), the detail sheet
/// raised this app's banner, and the multi-select raised a counted one —
/// while Android 13+ pins its own preview of the clipboard at the foot of
/// the screen, so a banner there doubled the receipt. One helper, one rule:
/// the system's preview is the receipt where one exists, and the banner is
/// the receipt everywhere else.
///
/// [count] names how many notes the text came from, for the selection's
/// receipt; a single copy says the plain word.
Future<void> nexCopy(BuildContext context, String text, {int? count}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  if (await _systemShowsItsOwnReceipt()) return;
  if (!context.mounted) return;
  final l10n = AppLocalizations.of(context);
  nexShowBanner(
    context,
    message: count == null ? l10n.copied : l10n.selectionCopied(count),
    // A direct result of the gesture that asked for the copy: no buzz.
    haptics: false,
  );
}

bool? _previewCapable;

/// Android 13+ shows a clipboard preview of its own; below that, nothing
/// does. Decided once per run from the release string ([NexDevice.describe]
/// answers "android 14"); anything unparsable — a desktop, a test harness
/// without the native half, an unknown version — answers "no", so the
/// banner says what happened rather than nothing at all.
Future<bool> _systemShowsItsOwnReceipt() async {
  if (_previewCapable case final known?) return known;
  if (!Platform.isAndroid) return false;
  final label = await NexDevice.describe();
  final release = label.platform.startsWith('android ')
      ? label.platform.substring('android '.length)
      : '';
  return _previewCapable = (int.tryParse(release) ?? 0) >= 13;
}
