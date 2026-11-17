/// The shelves the Modules page can be narrowed to (2.8.3), and which one
/// each module — and each still to come — sits on.
///
/// Kept here rather than on the module class: a shelf is how this page
/// groups modules, not something a module says about itself, so a module
/// written outside the repository never has to know about it. One missing
/// from the map sits on "everyday".
const nexModuleCategories = ['money', 'health', 'everyday', 'work'];

const _shelves = <String, String>{
  'gold': 'money',
  'lent_borrowed': 'money',
  'expenses': 'money',
  'price_lens': 'money',
  'cheque-manager': 'money',
  'cheques': 'money',
  'family_fund': 'money',
  'assets': 'money',
  'cycle': 'health',
  'pause': 'health',
  'smoke_free': 'health',
  'habits': 'health',
  'medicine': 'health',
  'prompt_studio': 'work',
  'security_tools': 'work',
  'telegram': 'work',
};

String nexModuleCategory(String id) => _shelves[id] ?? 'everyday';
