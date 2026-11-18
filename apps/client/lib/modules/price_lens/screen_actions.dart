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
          first: DateTime(1900),
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
          productName: option.productName,
          person: option.person,
        ),
      );
      _pendingMemoryIds.remove(option.id);
      if (mounted) {
        NexBannerHost.of(context)
            ?.show(message: priceLensStrings(context, 'saved'));
      }
    } catch (_) {
      if (mounted) lensWriteFailure(context);
    } finally {
      _paint(() => _writing = false);
    }
  }

  Future<void> _reset() async {
    if (_writing || !_scratchReady || _scratchFailed) return;
    _paint(() => _writing = true);
    final cleared = await _scratch.clear();
    _paint(() => _writing = false);
    if (!cleared) {
      _scratch.resume();
      if (mounted) lensWriteFailure(context);
      return;
    }
    _scratch.resume();
    if (!mounted) return;
    final previous = List<PriceOption>.of(options), oldUnit = commonUnitKey;
    _paint(() {
      options = [];
      commonUnitKey = null;
    });
    NexBannerHost.of(context)?.show(
      message: priceLensStrings(context, 'resetDone'),
      actionLabel: previous.isEmpty ? null : priceLensStrings(context, 'undo'),
      onAction: () {
        if (options.isEmpty) {
          _paint(() {
            options = previous;
            commonUnitKey = oldUnit;
            _workspaceChanged();
          });
        }
      },
    );
  }

  Future<void> _menu(String action) async {
    if (_writing) return;
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
            NexBannerHost.of(context)
                ?.show(message: priceLensStrings(context, 'saved'));
          }
        case 'memory':
          if (!mounted) return;
          await Navigator.push<void>(
            context,
            NexPageRoute<void>(
              builder: lensRouteBuilder(
                context,
                LensMemoryPage(controller: controller),
              ),
            ),
          );
        case 'saved':
          if (!mounted) return;
          await Navigator.push<void>(
            context,
            NexPageRoute<void>(
              builder: lensRouteBuilder(
                context,
                LensSavedPage(
                  controller: controller,
                  hasCalculatorOffers: options.isNotEmpty,
                  onOpenUnit: (unit) => commonUnitKey = unit,
                  onOpen: (restored) => _paint(() {
                    options = restored.take(4).toList();
                    _workspaceChanged();
                    // Common unit restored by the paired callback.
                  }),
                ),
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
