part of 'gold_form.dart';

Future<void> _restoreGoldDraft(
  _GoldFormLogic state, {
  bool initial = false,
}) async {
  if (state._restoring && !initial) return;
  state._beginRestore();
  final body = await state._draft!.load();
  if (!state.mounted) return;
  if (state._draft!.loadFailed) {
    state._draftReadError();
    return;
  }
  if (body != null) {
    state._draft!.apply(body);
    final fine = body['fineness'];
    final ref = body['rateRef'];
    if (fine is int && fine >= 100 && fine <= 999) state._fineness = fine;
    if (ref is int && ref >= 100 && ref <= 999) state._rateRef = ref;
    state._mode =
        GoldMakingMode.values
            .where((e) => e.name == body['mode'])
            .firstOrNull ??
        state._mode;
    state._profitBase =
        GoldProfitBase.values
            .where((e) => e.name == body['profitBase'])
            .firstOrNull ??
        state._profitBase;
    state._commissionTaxable = body['commissionTaxable'] != false;
    final extras = body['extras'];
    if (extras is List) {
      for (final e in state._extras) {
        e.label.dispose();
        e.amount.dispose();
      }
      state._extras.clear();
      for (final e in extras.take(50)) {
        if (e is Map && e['label'] is String && e['amount'] is String) {
          final label = TextEditingController(text: e['label'] as String)
            ..addListener(state._changed);
          final amount = TextEditingController(text: e['amount'] as String)
            ..addListener(state._changed);
          state._extras.add(GoldExtraControllers(label, amount));
        }
      }
    }
  }
  state._draft!.resume();
  state._completeRestore();
}
