/// Which modules are available to people (the others would show as Soon).
///
/// Cycle only, for now (2.2.0). The twelve add-ons — Habits, Price Lens, Lent &
/// Borrowed, Quit Habits (`smoke_free`), Birthdays & occasions, Expenses, Gold,
/// Words, Parking, Medicine, Warranty and Maintenance — were all integrated,
/// reviewed and enabled (2.1.9–2.1.14), then put back to Soon after real-device
/// testing showed they need more work. Their code, data layer, tests and
/// installation choices are untouched: adding an id back to this set is the
/// whole of re-enabling one.
///
/// A module that is not listed here is Soon: no install, open or reminders.
/// Rollout never changes saved installation choices or data.
const nexAvailableModuleIds = {'cycle'};

bool nexModuleAvailable(String id) => nexAvailableModuleIds.contains(id);
