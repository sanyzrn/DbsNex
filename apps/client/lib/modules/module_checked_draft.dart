/// One draft implementation, two names.
///
/// `NexCheckedModuleFormDraft` began as a corrected copy of
/// `NexModuleFormDraft` — untouched forms stopped writing checkpoints,
/// `start` stopped double-listening, a failed load became visible — and the
/// two lived side by side, each fix landing in one of them. The behaviour
/// that shipped under the checked name is the superset, so it is the one
/// implementation now, and this file keeps the name modules were written
/// against.
library;

import 'module_draft.dart' show NexModuleFormDraft;

export 'module_draft.dart' show NexModuleFormDraft;

typedef NexCheckedModuleFormDraft = NexModuleFormDraft;
