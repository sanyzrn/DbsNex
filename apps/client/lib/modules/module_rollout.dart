/// Which modules are available to people (the others would show as Soon).
///
/// Cycle and every add-on: each was reviewed and finished one at a time —
/// Habits, Price Lens, Lent & Borrowed, Quit Habits (`smoke_free`), Birthdays
/// & occasions, then (2.1.14) Expenses, Gold, Words, Parking, Medicine,
/// Warranty and Maintenance. A module that is not listed here is Soon: no
/// install, open or reminders. Rollout never changes saved installation
/// choices or data.
const nexAvailableModuleIds = {
  'cycle',
  'habits',
  'price_lens',
  'lent_borrowed',
  'smoke_free',
  'occasions',
  'expenses',
  'gold',
  'words',
  'parking',
  'medicine',
  'warranty',
  'maintenance',
};

bool nexModuleAvailable(String id) => nexAvailableModuleIds.contains(id);
