import 'package:nex_client/modules/module_api.dart';

const securityChecks = ['unique', 'mfa', 'recovery', 'sessions'];
const checkStates = ['unknown', 'todo', 'done', 'unavailable'];

class SecurityAccount {
  SecurityAccount(this.id, this.raw);
  factory SecurityAccount.fromRecord(ModuleRecord r) =>
      SecurityAccount(r.id, r.body);
  final String id;
  final Map<String, Object?> raw;
  String get label => raw['label'] is String ? raw['label'] as String : '';
  String state(String key) {
    final checks = raw['checks'];
    final value = checks is Map ? checks[key] : null;
    return checkStates.contains(value) ? value as String : 'unknown';
  }

  bool get valid =>
      raw['v'] == 1 && label.trim().isNotEmpty && label.length <= 60;
  int get done => securityChecks.where((k) => state(k) == 'done').length;
  String? get next => securityChecks
      .where((k) => ['unknown', 'todo'].contains(state(k)))
      .firstOrNull;
}
