/// Which modules are available to people (the others show as Soon).
///
/// Cycle, and the add-ons that have been reviewed and finished one at a time:
/// Habits, Price Lens, Lent & Borrowed, Quit Habits (`smoke_free`) and
/// Birthdays & occasions. Re-enable the rest the same
/// way — one id, after its own review. Rollout never changes saved
/// installation choices or data.
const nexAvailableModuleIds = {
  'cycle',
  'habits',
  'price_lens',
  'lent_borrowed',
  'smoke_free',
  'occasions',
};

bool nexModuleAvailable(String id) => nexAvailableModuleIds.contains(id);
