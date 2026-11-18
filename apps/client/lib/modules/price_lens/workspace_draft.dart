part of 'price_lens_screen.dart';

extension _LensWorkspaceDraft on _PriceLensScreenState {
  void _workspaceChanged() {
    if (_scratchReady && !_scratchFailed) _scratch.changed();
  }

  Future<void> _restoreWorkspace() async {
    if (_scratchReading) return;
    _scratchReading = true;
    try {
      final data = await _scratch.load();
      if (_scratch.loadFailed) throw const FormatException('draft read');
      if (data != null) {
        if (data['workspaceVersion'] != 1 ||
            data['offers'] is! List ||
            (data['offers'] as List).length > 4) {
          throw const FormatException('workspace');
        }
        final restored = <PriceOption>[];
        for (final item in data['offers'] as List) {
          if (item is! Map ||
              item['id'] is! String ||
              item['body'] is! Map ||
              restored.any((o) => o.id == item['id'])) {
            throw const FormatException('offer');
          }
          restored.add(
            PriceOption.fromBody(
              item['id'] as String,
              Map<String, Object?>.from(item['body'] as Map),
            ),
          );
        }
        options = restored;
        final key = data['commonUnit'];
        if (key != null && (key is! String || priceUnitOf(key) == null)) {
          throw const FormatException('unit');
        }
        commonUnitKey = key as String?;
        final tab = data['tab'];
        if (tab is int && tab >= 0 && tab <= 2) _tab = tab;
      }
      _scratch.start();
      if (mounted) {
        _paint(() {
          _scratchReady = true;
          _scratchFailed = false;
        });
      }
    } catch (_) {
      if (mounted) {
        _paint(() {
          _scratchFailed = true;
        });
      }
    } finally {
      _scratchReading = false;
    }
  }
}
