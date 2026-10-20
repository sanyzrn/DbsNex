/// Which modules are available to people (the others show as Soon).
///
/// Cycle, and the three add-ons that have been reviewed and finished one at a
/// time: Habits, Price Lens and Lent & Borrowed. Re-enable the rest the same
/// way — one id, after its own review. Rollout never changes saved
/// installation choices or data.
const nexAvailableModuleIds = {
  'cycle',
  'habits',
  'price_lens',
  'lent_borrowed',
};

bool nexModuleAvailable(String id) => nexAvailableModuleIds.contains(id);
