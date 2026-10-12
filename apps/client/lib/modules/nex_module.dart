import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import '../widgets/nex_shelf.dart';

/// A feature that ships inside Nex but is not part of it until someone adds
/// it — see `docs/17-modules.md` and ADR-040.
///
/// Off, a module has no tile, no menu entry, no reminders, no background
/// work, no widget and no assistant tool: everything it does outside its own
/// screen asks [isOn] first. It is added and removed on Tools → Modules.
abstract class NexModule {
  const NexModule();

  /// Stable and lower-case; keys its preference and its widgets in tests.
  String get id;

  String title(AppLocalizations l10n);

  /// One line, under the title on its card and its Tools tile.
  String tagline(AppLocalizations l10n);

  /// What it does, in a few sentences, on its card.
  String about(AppLocalizations l10n);

  /// Three or four things it does, as chips on its card.
  List<String> points(AppLocalizations l10n);

  IconData get icon;

  /// Its colour: on its card, its Tools tile and its chips.
  NexHue get hue;

  /// Whether it is part of the app right now.
  bool isOn(NexPreferences preferences);

  /// Adds it, and does whatever it needs on the way in.
  Future<void> turnOn(
    BuildContext context, {
    required NexServices services,
    required NexPreferences preferences,
  });

  /// Removes it: asks whether to keep its data, and stops everything it does.
  /// Resolves to whether it is now off — false if the person backed out.
  Future<bool> turnOff(
    BuildContext context, {
    required NexServices services,
    required NexPreferences preferences,
  });

  /// Its own screen, opened from its tile in Tools.
  Widget open({
    required NexServices services,
    required NexPreferences preferences,
  });
}
