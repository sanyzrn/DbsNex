import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'local_writes.dart';
import 'parking_dialogs.dart';
import 'parking_models.dart';
import 'parking_strings.dart';
import 'parking_widgets.dart';
import 'parking_writes.dart';

/// Every remembered place, including the ones the home screen's six-row
/// shelves do not reach. Tapping one hands it back to the home screen to fill
/// the editor; the star and the bin act here, where a mistake is deliberate.
class ParkingPlacesSheet extends StatefulWidget {
  const ParkingPlacesSheet({super.key, required this.store});

  final NexModuleStore store;

  @override
  State<ParkingPlacesSheet> createState() => _ParkingPlacesSheetState();
}

class _ParkingPlacesSheetState extends State<ParkingPlacesSheet> {
  List<ModuleRecord> _places = const [];
  StreamSubscription<void>? _changes;
  bool _loading = true;
  bool _failed = false;
  bool _busy = false;
  int _loadSeq = 0;

  @override
  void initState() {
    super.initState();
    _changes = widget.store.changes.listen((_) => unawaited(_load()));
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_loadSeq;
    try {
      final places = await widget.store.list(ParkingModels.place);
      places.sort(
        (a, b) => (ParkingModels.readDate(b.body, 'lastUsedAt') ?? DateTime(0))
            .compareTo(
              ParkingModels.readDate(a.body, 'lastUsedAt') ?? DateTime(0),
            ),
      );
      if (!mounted || seq != _loadSeq) {
        return;
      }
      setState(() {
        _places = places;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted || seq != _loadSeq) {
        return;
      }
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _toggle(ModuleRecord record, bool favourite) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ParkingWrites.setFavourite(widget.store, record.id, favourite);
    } catch (_) {
      _failedBanner();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _delete(ModuleRecord record) async {
    if (_busy) {
      return;
    }
    if (await ParkingDialogs.confirmDeletePlace(context, parkingStrings) !=
            true ||
        !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      final undo = await LocalWrites.delete(
        widget.store,
        ParkingModels.place,
        record.id,
      );
      if (!mounted) {
        return;
      }
      ParkingDialogs.offerUndo(
        NexBannerHost.of(context),
        parkingStrings(context, 'placeDeleted'),
        AppLocalizations.of(context).undo,
        undo,
      );
    } catch (_) {
      _failedBanner();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _failedBanner() {
    if (!mounted) {
      return;
    }
    NexBannerHost.of(context)?.show(
      kind: NexBannerKind.failed,
      message: parkingStrings(context, 'saveFailed'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = parkingStrings;
    final theme = Theme.of(context);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .68,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              NexSpacing.md,
              NexSpacing.md,
              NexSpacing.md,
              NexSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    strings(context, 'placesTitle'),
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                Text(
                  strings(context, 'placesCount', {'count': _places.length}),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _failed
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(strings(context, 'loadFailed')),
                        TextButton(
                          onPressed: () => unawaited(_load()),
                          child: Text(strings(context, 'retry')),
                        ),
                      ],
                    ),
                  )
                : _places.isEmpty
                ? Center(child: Text(strings(context, 'placesEmpty')))
                : ListView.builder(
                    padding: EdgeInsets.only(
                      bottom:
                          NexSpacing.lg +
                          MediaQuery.viewPaddingOf(context).bottom,
                    ),
                    itemCount: _places.length,
                    itemBuilder: (context, index) {
                      final place = _places[index];
                      return ParkingPlaceRow(
                        key: ValueKey('parking-places-row-${place.id}'),
                        record: place,
                        onTap: () => Navigator.of(context).pop(place),
                        onFavourite: (value) =>
                            unawaited(_toggle(place, value)),
                        onDelete: () => unawaited(_delete(place)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
