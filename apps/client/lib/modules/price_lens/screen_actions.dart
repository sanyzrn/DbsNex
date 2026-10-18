part of 'price_lens_screen.dart';

extension _ScreenActions on _PriceLensScreenState {
  Future<void> _rememberPrice(PriceOption option) async {
    if (_writing || !optionSafe(option)) return;
    _paint(() => _writing = true);
    try {
      var date = option.date;
      if (date == null) {
        final now = DateTime.now();
        date = await nexPickModuleDate(
          context,
          initial: now,
          first: DateTime(1),
          last: now,
        );
      }
      if (date == null || !mounted) return;
      final paid = effectivePriceMinor(option);
      final id = _pendingMemoryIds.putIfAbsent(
        option.id,
        controller.newMemoryId,
      );
      await controller.saveMemory(
        PriceMemory(
          id: id,
          label: option.label,
          priceMinor: paid.roundHalfUp(),
          paidFraction: paid,
          currency: option.currency,
          quantity: option.quantity,
          unitKey: option.unitKey,
          packageCount: option.packageCount,
          date: date,
        ),
      );
      _pendingMemoryIds.remove(option.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(priceLensStrings(context, 'saved'))),
        );
      }
    } catch (_) {
      if (mounted) lensWriteFailure(context);
    } finally {
      _paint(() => _writing = false);
    }
  }

  void _reset() {
    if (_writing) return;
    final previous = List<PriceOption>.of(options), oldUnit = commonUnitKey;
    _paint(() {
      options = [];
      commonUnitKey = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(priceLensStrings(context, 'resetDone')),
        action: previous.isEmpty
            ? null
            : SnackBarAction(
                label: priceLensStrings(context, 'undo'),
                onPressed: () {
                  if (options.isEmpty) {
                    _paint(() {
                      options = previous;
                      commonUnitKey = oldUnit;
                    });
                  }
                },
              ),
      ),
    );
  }

  Future<void> _menu(String action) async {
    try {
      switch (action) {
        case 'save':
          if (_writing || options.length < 2) return;
          _paint(() => _writing = true);
          _pendingComparisonId ??= controller.newComparisonId();
          await controller.saveComparison(
            options,
            id: _pendingComparisonId,
            commonUnitKey: commonUnitKey,
          );
          _pendingComparisonId = null;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(priceLensStrings(context, 'saved'))),
            );
          }
        case 'memory':
          if (!mounted) return;
          await Navigator.push<void>(
            context,
            NexPageRoute<void>(
              builder: (_) => LensMemoryPage(controller: controller),
            ),
          );
        case 'saved':
          if (!mounted) return;
          await Navigator.push<void>(
            context,
            NexPageRoute<void>(
              builder: (_) => LensSavedPage(
                controller: controller,
                onOpenUnit: (unit) => commonUnitKey = unit,
                onOpen: (restored) => _paint(() {
                  options = restored.take(4).toList();
                  // Common unit restored by the paired callback.
                }),
              ),
            ),
          );
      }
    } catch (_) {
      if (mounted) lensWriteFailure(context);
    } finally {
      _paint(() => _writing = false);
    }
  }
}
