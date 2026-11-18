import '../l10n/app_localizations.dart';
import '../modules/module_registry.dart';
import '../modules/module_shared.dart';
import '../modules/nex_module_store.dart';
import '../modules/nex_stored_module.dart';
import 'nex_preferences.dart';
import 'nex_services.dart';

/// The modules whose facts are about money, health or belongings (2.8.5):
/// the assistant hears that they have something coming up, and how much,
/// never what it is — no amount, no name, no medicine. Kept as a list
/// rather than read from the dues' `private` mark, because a glance line
/// (a balance, a dose) carries the same facts without a mark of its own.
const nexToolsKeptOnPhone = <String>{
  'assets',
  'cheques',
  'expenses',
  'family_fund',
  'gold',
  'lent_borrowed',
  'medicine',
  'smoke_free',
};

/// How far ahead the assistant is told about dates.
const nexToolsAhead = Duration(days: 14);

/// What one module says to the assistant, already gathered.
class NexToolReport {
  const NexToolReport({
    required this.id,
    required this.title,
    this.glance,
    this.dues = const [],
    this.dueLabel,
  });

  final String id;
  final String title;
  final ModuleGlance? glance;
  final List<ModuleDue> dues;
  final String? Function(String kind)? dueLabel;
}

/// "Your tools" as the assistant reads it (2.8.5), or empty. Pure, so what
/// leaves the phone is tested as written:
///
/// - a module in [nexToolsKeptOnPhone], or a private due anywhere, is a
///   count only;
/// - everything else is its glance's headline and detail, and its open
///   dates of the next two weeks (overdue first) by their own titles;
/// - bounded, so a long list never crowds the notes out.
String nexToolsContext(
  List<NexToolReport> reports,
  DateTime now, {
  int budget = 1600,
}) {
  final today = DateTime(now.year, now.month, now.day);
  String day(DateTime at) =>
      '${at.year}-${_pad(at.month)}-${_pad(at.day)}'
      '${at.isBefore(today) ? ' (overdue)' : ''}';
  final lines = <String>[];
  for (final report in reports) {
    final open = [
      for (final due in report.dues)
        if (!due.isOver(today)) due,
    ]..sort((a, b) => a.at.compareTo(b.at));
    if (nexToolsKeptOnPhone.contains(report.id)) {
      // Not even that it is in use, unless something is coming up.
      if (open.isNotEmpty) {
        lines.add(
          '- ${report.title}: ${open.length} item(s) due, earliest '
          '${day(open.first.at)} (details stay on the phone)',
        );
      }
      continue;
    }
    final glance = report.glance;
    final said = [?glance?.headline, ?glance?.detail].join(' — ');
    final private = open.where((d) => d.private).length;
    final dated = [
      for (final due in open.where((d) => !d.private).take(5))
        '${_titleOf(due, report.dueLabel)} ${day(due.at)}',
      if (private > 0) '$private private item(s)',
    ];
    if (said.isEmpty && dated.isEmpty) continue;
    lines.add(
      [
        '- ${report.title}',
        if (said.isNotEmpty) ': $said',
        if (dated.isNotEmpty) '; coming up: ${dated.join(', ')}',
      ].join(),
    );
  }
  if (lines.isEmpty) return '';
  final out = StringBuffer(
    "The user's Nex tools (modules) on this phone, as they stand now. "
    'Summaries, not notes: they have no ids and no action changes them; '
    'to change one, the user opens the tool itself.\n',
  );
  for (final line in lines) {
    if (out.length + line.length > budget) {
      out.writeln('- (more tools not listed)');
      break;
    }
    out.writeln(line);
  }
  return out.toString().trimRight();
}

String _titleOf(ModuleDue due, String? Function(String kind)? label) {
  final what = label?.call(due.kind);
  if (what == null) return due.title;
  if (due.title.isEmpty) return what;
  return '${due.title} ($what)';
}

String _pad(int value) => value.toString().padLeft(2, '0');

/// Gathers [nexToolsContext] from every module that is on — nothing at all
/// unless the person turned on "Let the assistant see my tools".
Future<String> nexToolsForAssistant({
  required NexServices services,
  required NexPreferences preferences,
  required AppLocalizations l10n,
  DateTime? now,
  int budget = 1600,
}) async {
  if (!preferences.aiUseTools) return '';
  final at = now ?? DateTime.now();
  final today = DateTime(at.year, at.month, at.day);
  final reports = <NexToolReport>[];
  for (final module in nexModulesOn(preferences)) {
    if (module is! NexStoredModule) continue;
    final store = NexModuleStore(services, module.id);
    ModuleGlance? glance;
    var dues = const <ModuleDue>[];
    try {
      glance = await module.glance(store, l10n, at);
    } catch (_) {}
    try {
      dues = await module.dues(
        store,
        today.subtract(const Duration(days: 30)),
        today.add(nexToolsAhead),
      );
    } catch (_) {}
    reports.add(
      NexToolReport(
        id: module.id,
        title: module.title(l10n),
        glance: glance,
        dues: dues,
        dueLabel: (kind) => module.dueLabel(l10n, kind),
      ),
    );
  }
  return nexToolsContext(reports, at, budget: budget);
}
