/// Durable notification destination. Values are identifiers, never item text.
class NexModuleTarget {
  const NexModuleTarget(
    this.module, {
    this.kind = '',
    this.id = '',
    this.key = '',
    this.day = '',
    this.progress = false,
  });
  final String module, kind, id, key, day;
  final bool progress;
  String get payload =>
      'nex:module:$module?${Uri(queryParameters: {'kind': kind, 'id': id, 'key': key, 'day': day}).query}';
  NexModuleTarget forProgress() => NexModuleTarget(
    module,
    kind: kind,
    id: id,
    key: key,
    day: day,
    progress: true,
  );

  static NexModuleTarget? parse(String? payload) {
    if (payload == null ||
        !payload.startsWith('nex:module:') ||
        payload.length > 1800) {
      return null;
    }
    try {
      final value = payload.substring('nex:module:'.length);
      final cut = value.indexOf('?');
      final module = cut < 0 ? value : value.substring(0, cut);
      if (!RegExp(r'^[a-z_]{1,40}$').hasMatch(module)) return null;
      final fields = cut < 0
          ? <String, String>{}
          : Uri.splitQueryString(value.substring(cut + 1));
      return NexModuleTarget(
        module,
        kind: fields['kind'] ?? '',
        id: fields['id'] ?? '',
        key: fields['key'] ?? '',
        day: fields['day'] ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}
