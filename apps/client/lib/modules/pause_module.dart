import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import '../screens/pause/pause_screen.dart';
import '../widgets/nex_shelf.dart';
import 'nex_module.dart';

/// «Pause», a breathing break (2.4.0).
///
/// First-party rather than a module-kit folder, because it needs what the kit
/// keeps out: a player for its sound, the phone's haptics and a lit screen.
/// It keeps nothing but three settings, so taking it off has no data to ask
/// about.
class PauseModule extends NexModule {
  const PauseModule();

  @override
  String get id => 'pause';

  @override
  String title(AppLocalizations l10n) => l10n.pauseTitle;

  @override
  String tagline(AppLocalizations l10n) => l10n.pauseTagline;

  @override
  String about(AppLocalizations l10n) => l10n.planPauseAbout;

  @override
  List<String> points(AppLocalizations l10n) => [
    l10n.pausePointModes,
    l10n.pausePointMotion,
    l10n.pausePointSound,
    l10n.pausePointHaptics,
  ];

  @override
  IconData get icon => Icons.air_outlined;

  @override
  NexHue get hue => NexHue.sky;

  @override
  bool isOn(NexPreferences preferences) => preferences.isModuleOn(id);

  @override
  Future<void> turnOn(
    BuildContext context, {
    required NexServices services,
    required NexPreferences preferences,
  }) => preferences.setModuleOn(id, true);

  @override
  Future<bool> turnOff(
    BuildContext context, {
    required NexServices services,
    required NexPreferences preferences,
  }) async {
    await preferences.setModuleOn(id, false);
    return true;
  }

  @override
  Widget open({
    required NexServices services,
    required NexPreferences preferences,
  }) => PauseScreen(preferences: preferences);
}
