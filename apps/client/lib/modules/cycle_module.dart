import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import '../screens/cycle/cycle_switch.dart';
import '../screens/cycle_screen.dart';
import '../widgets/nex_shelf.dart';
import 'nex_module.dart';

/// «Cycle», the first module.
///
/// It lived in the profile as a switch until 1.99.60. Its on/off state is the
/// same preference it always was, so it carries over untouched.
class CycleModule extends NexModule {
  const CycleModule();

  @override
  String get id => 'cycle';

  @override
  String title(AppLocalizations l10n) => l10n.cycleTitle;

  @override
  String tagline(AppLocalizations l10n) => l10n.cycleSubtitle;

  @override
  String about(AppLocalizations l10n) => l10n.cycleProfileAbout;

  @override
  List<String> points(AppLocalizations l10n) => [
    l10n.moduleCyclePointPredict,
    l10n.moduleCyclePointLog,
    l10n.moduleCyclePointModes,
    l10n.moduleCyclePointPrivate,
  ];

  @override
  IconData get icon => Icons.water_drop_outlined;

  @override
  NexHue get hue => NexHue.rose;

  @override
  bool isOn(NexPreferences preferences) => preferences.cycleEnabled;

  @override
  Future<void> turnOn(
    BuildContext context, {
    required NexServices services,
    required NexPreferences preferences,
  }) => nexSetCycleEnabled(
    context,
    services: services,
    preferences: preferences,
    value: true,
  );

  @override
  Future<bool> turnOff(
    BuildContext context, {
    required NexServices services,
    required NexPreferences preferences,
  }) async => !await nexSetCycleEnabled(
    context,
    services: services,
    preferences: preferences,
    value: false,
  );

  @override
  Widget open({
    required NexServices services,
    required NexPreferences preferences,
  }) => CycleScreen(services: services, preferences: preferences);
}
