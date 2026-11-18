import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';

import '../../l10n/app_localizations.dart';
import '../../modules/module_registry.dart';
import '../../platform/nex_preferences.dart';
import '../../platform/timeline_shelves.dart';
import '../nex_shelf.dart';

/// Where a tip's button goes. The home screen decides how to get there, so
/// a tip names a place, never a route.
enum NexTipTarget { tools, homeLayout, guide }

/// What a tip may ask about before it is shown: the notes on the home
/// screen and the person's settings. Nothing is read for a tip that is not
/// already in memory.
class NexTipContext {
  const NexTipContext({required this.notes, required this.preferences});

  final List<Note> notes;
  final NexPreferences preferences;

  int get modulesOn => nexModulesOn(preferences).length;
}

/// One tip on the home screen (2.8.4).
///
/// **Adding one** is one entry in [nexTips] and its two strings
/// (`tip<Name>Title` / `tip<Name>Body`) in both ARB files. Give it:
///
/// - an [id] that never changes — it is what "already shown" remembers, so
///   renaming it shows the tip again;
/// - [fresh] for something new in this release, which makes it likelier to
///   be picked first;
/// - [when] if it only makes sense for some people (no lock yet, no tools
///   pinned) — a tip about something already in use is noise;
/// - [target] and [action] for a button that takes the person there.
///
/// Changing words is a string edit; removing a tip is deleting its entry.
/// The schedule ([NexTipSchedule]) decides when any of them appears.
class NexTip {
  const NexTip({
    required this.id,
    required this.icon,
    required this.hue,
    required this.title,
    required this.body,
    this.when,
    this.target,
    this.action,
    this.fresh = false,
  });

  final String id;
  final IconData icon;
  final NexHue hue;
  final String Function(AppLocalizations l10n) title;
  final String Function(AppLocalizations l10n) body;
  final bool Function(NexTipContext context)? when;
  final NexTipTarget? target;
  final String Function(AppLocalizations l10n)? action;
  final bool fresh;

  bool fits(NexTipContext context) => when?.call(context) ?? true;
}

/// Every tip, in no particular order: the schedule picks among them.
final List<NexTip> nexTips = [
  NexTip(
    id: 'reminder-clears',
    icon: Icons.auto_delete_outlined,
    hue: NexHue.rose,
    title: (l) => l.tipReminderClearsTitle,
    body: (l) => l.tipReminderClearsBody,
    fresh: true,
  ),
  NexTip(
    id: 'tool-dates',
    icon: Icons.event_note_outlined,
    hue: NexHue.sky,
    title: (l) => l.tipToolDatesTitle,
    body: (l) => l.tipToolDatesBody,
    when: (c) => c.modulesOn > 0,
    target: NexTipTarget.homeLayout,
    action: (l) => l.layoutTitle,
    fresh: true,
  ),
  NexTip(
    id: 'tool-peek',
    icon: Icons.visibility_outlined,
    hue: NexHue.teal,
    title: (l) => l.tipToolPeekTitle,
    body: (l) => l.tipToolPeekBody,
    when: (c) => c.modulesOn > 0 && c.preferences.pinnedTools.isNotEmpty,
    fresh: true,
  ),
  NexTip(
    id: 'modules',
    icon: Icons.widgets_outlined,
    hue: NexHue.violet,
    title: (l) => l.tipModulesTitle,
    body: (l) => l.tipModulesBody,
    when: (c) => c.modulesOn < 3,
    target: NexTipTarget.tools,
    action: (l) => l.tipOpenTools,
    fresh: true,
  ),
  NexTip(
    id: 'pin-tools',
    icon: Icons.push_pin_outlined,
    hue: NexHue.teal,
    title: (l) => l.tipPinToolsTitle,
    body: (l) => l.tipPinToolsBody,
    when: (c) => c.modulesOn > 0 && c.preferences.pinnedTools.isEmpty,
    target: NexTipTarget.tools,
    action: (l) => l.tipOpenTools,
  ),
  NexTip(
    id: 'flick-plus',
    icon: Icons.swipe_outlined,
    hue: NexHue.sky,
    title: (l) => l.tipFlickPlusTitle,
    body: (l) => l.tipFlickPlusBody,
  ),
  NexTip(
    id: 'send-later',
    icon: Icons.schedule_send_outlined,
    hue: NexHue.amber,
    title: (l) => l.tipSendLaterTitle,
    body: (l) => l.tipSendLaterBody,
  ),
  NexTip(
    id: 'grid',
    icon: Icons.grid_view_rounded,
    hue: NexHue.sky,
    title: (l) => l.tipGridTitle,
    body: (l) => l.tipGridBody,
    when: (c) => !c.preferences.timelineGrid && c.notes.length >= 6,
    target: NexTipTarget.homeLayout,
    action: (l) => l.layoutTitle,
  ),
  NexTip(
    id: 'group-by',
    icon: Icons.view_agenda_outlined,
    hue: NexHue.violet,
    title: (l) => l.tipGroupByTitle,
    body: (l) => l.tipGroupByBody,
    when: (c) =>
        c.preferences.timelineArrangement == NexTimelineArrangement.time &&
        c.notes.length >= 10,
    target: NexTipTarget.homeLayout,
    action: (l) => l.layoutTitle,
  ),
  NexTip(
    id: 'pinch-fold',
    icon: Icons.unfold_less_rounded,
    hue: NexHue.slate,
    title: (l) => l.tipPinchTitle,
    body: (l) => l.tipPinchBody,
    when: (c) => c.notes.length >= 15,
  ),
  NexTip(
    id: 'pin-note',
    icon: Icons.push_pin_outlined,
    hue: NexHue.amber,
    title: (l) => l.tipPinNoteTitle,
    body: (l) => l.tipPinNoteBody,
    when: (c) => c.notes.length >= 5 && !c.notes.any((n) => n.pinnedAt != null),
  ),
  NexTip(
    id: 'select',
    icon: Icons.checklist_rtl_rounded,
    hue: NexHue.teal,
    title: (l) => l.tipSelectTitle,
    body: (l) => l.tipSelectBody,
    when: (c) => c.notes.length >= 8,
  ),
  NexTip(
    id: 'archive',
    icon: Icons.inventory_2_outlined,
    hue: NexHue.slate,
    title: (l) => l.tipArchiveTitle,
    body: (l) => l.tipArchiveBody,
    when: (c) => c.notes.length >= 10,
  ),
  NexTip(
    id: 'app-lock',
    icon: Icons.fingerprint,
    hue: NexHue.teal,
    title: (l) => l.tipLockTitle,
    body: (l) => l.tipLockBody,
    when: (c) => !c.preferences.appLockEnabled,
  ),
  NexTip(
    id: 'backup-folder',
    icon: Icons.drive_folder_upload_outlined,
    hue: NexHue.violet,
    title: (l) => l.tipBackupTitle,
    body: (l) => l.tipBackupBody,
    when: (c) => c.preferences.backupFolderUri == null && c.notes.length >= 10,
  ),
  NexTip(
    id: 'widget',
    icon: Icons.widgets_rounded,
    hue: NexHue.sky,
    title: (l) => l.tipWidgetTitle,
    body: (l) => l.tipWidgetBody,
  ),
  NexTip(
    id: 'save-from-apps',
    icon: Icons.ios_share_rounded,
    hue: NexHue.rose,
    title: (l) => l.tipShareInTitle,
    body: (l) => l.tipShareInBody,
  ),
  NexTip(
    id: 'trash',
    icon: Icons.restore_from_trash_outlined,
    hue: NexHue.slate,
    title: (l) => l.tipTrashTitle,
    body: (l) => l.tipTrashBody,
    when: (c) => c.notes.length >= 5,
  ),
  NexTip(
    id: 'guide',
    icon: Icons.menu_book_outlined,
    hue: NexHue.amber,
    title: (l) => l.tipGuideTitle,
    body: (l) => l.tipGuideBody,
    target: NexTipTarget.guide,
    action: (l) => l.onboardingGuideOpen,
  ),
];
