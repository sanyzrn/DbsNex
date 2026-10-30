import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;

/// Which modules are available to people (the others would show as Soon).
///
/// Cycle, and from 2.4.0 Pause — a breathing break, built for the phone with
/// its own sound and haptics. The twelve add-ons — Habits, Price Lens, Lent &
/// Borrowed, Quit Habits (`smoke_free`), Birthdays & occasions, Expenses, Gold,
/// Words, Parking, Medicine, Warranty and Maintenance — were all integrated,
/// reviewed and enabled (2.1.9–2.1.14), then put back to Soon after real-device
/// testing showed they need more work. Their code, data layer, tests and
/// installation choices are untouched: adding an id back to this set is the
/// whole of re-enabling one.
///
/// A module that is not listed here is Soon: no install, open or reminders.
/// Rollout never changes saved installation choices or data.
/// Birthdays & occasions and Word by Word are the first of them back,
/// finished and redesigned in 2.4.0. Habits returns in 2.4.1.
const nexAvailableModuleIds = {'cycle', 'pause', 'occasions', 'words', 'habits'};

/// Windows, Linux and macOS. The modules are made for the phone; the desktop
/// has none of them for now (its own tools are to come, `docs/27-desktop.md`),
/// so on a desktop none is available, and Tools does not offer them at all.
/// Their data and installation choices are untouched.
bool get nexDesktopPlatform => switch (defaultTargetPlatform) {
  TargetPlatform.windows ||
  TargetPlatform.linux ||
  TargetPlatform.macOS => true,
  _ => false,
};

bool nexModuleAvailable(String id) =>
    !nexDesktopPlatform && nexAvailableModuleIds.contains(id);

