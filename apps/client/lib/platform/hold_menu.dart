import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../widgets/feature_label.dart';

/// Everything a note's hold menu can offer: every action on the note's detail
/// sheet, its More menu included.
///
/// Which of them the menu shows is the user's choice (Settings → Capture →
/// Hold menu). The default is the five people reach for from the timeline
/// itself; Open and Add tag used to be in it, and both are one tap away
/// anyway — tap the card, swipe the card.
///
/// Declared in the order the menu lists them. Delete is always last.
///
/// [select] is not a choice: every card's menu starts with it, whatever is
/// picked in Settings, because it is how picking several notes at once
/// begins and there is no other way in.
enum NexHoldAction {
  select,
  pin,
  copy,
  edit,
  remind,
  share,
  addTag,
  thread,
  caption,
  expand,
  open,
  openFile,
  openLink,
  convert,
  ask,
  translate,
  summarize,
  details,
  delete;

  static const defaults = [pin, copy, edit, remind, delete];

  static NexHoldAction? fromWire(String value) => values
      .where((action) => action.name == value && action.choosable)
      .firstOrNull;

  /// Whether Settings lists it; everything but [select].
  bool get choosable => this != select;

  static Iterable<NexHoldAction> get choices =>
      values.where((action) => action.choosable);

  IconData get icon => switch (this) {
    select => Icons.check_circle_outline,
    pin => Icons.push_pin_outlined,
    copy => Icons.copy_outlined,
    edit => Icons.edit_outlined,
    remind => Icons.notifications_outlined,
    share => Icons.ios_share,
    addTag => Icons.label_outline,
    thread => Icons.timeline_outlined,
    caption => Icons.short_text,
    expand => Icons.unfold_more,
    open => Icons.open_in_full,
    openFile => Icons.open_in_new,
    openLink => Icons.link,
    convert => Icons.description_outlined,
    ask => Icons.auto_awesome,
    translate => Icons.translate,
    summarize => Icons.summarize_outlined,
    details => Icons.info_outline,
    delete => Icons.delete_outline,
  };

  String label(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return switch (this) {
      select => l10n.selectNotes,
      pin => l10n.pin,
      copy => l10n.copy,
      edit => l10n.edit,
      remind => l10n.remind,
      share => l10n.share,
      addTag => l10n.addTag,
      thread => l10n.threads,
      caption => nexLabel(context, 'Description', 'توضیح'),
      expand => l10n.expandCard,
      open => nexLabel(context, 'Open details', 'باز کردن جزئیات'),
      openFile => nexLabel(context, 'Open file', 'باز کردن فایل'),
      openLink => l10n.openLink,
      convert => nexLabel(
        context,
        'Convert (Markdown / note)',
        'تبدیل (مارک‌داون / یادداشت)',
      ),
      ask => l10n.askAboutNote,
      translate => l10n.translate,
      summarize => l10n.summarize,
      details => l10n.details,
      delete => l10n.delete,
    };
  }
}
