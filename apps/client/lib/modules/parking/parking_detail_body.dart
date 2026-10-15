part of 'parking_detail.dart';

extension _ParkingDetailBody on _ParkingDetailPageState {
  Widget _view(BuildContext context) {
    final strings = parkingStrings;
    final body = _body;
    final active = body != null && ParkingLogic.isActive(body);

    return Scaffold(
      appBar: NexAppBar(
        title: Text(strings(context, 'detailsTitle')),
        actions: [
          IconButton(
            key: const ValueKey('parking-detail-edit'),
            tooltip: AppLocalizations.of(context).edit,
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => unawaited(_edit()),
          ),
          IconButton(
            key: const ValueKey('parking-detail-delete'),
            tooltip: AppLocalizations.of(context).delete,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => unawaited(_delete()),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadFailed || body == null
          ? _readError()
          : ListView(
              padding: const EdgeInsets.all(NexSpacing.md),
              children: [
                NexPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _row(
                        context,
                        Icons.place_outlined,
                        strings(context, 'placeLabel'),
                        ParkingModels.readString(body, 'place'),
                      ),
                      _row(
                        context,
                        Icons.directions_car_outlined,
                        strings(context, 'vehicleLabel'),
                        ParkingModels.readString(body, 'vehicle'),
                      ),
                      _row(
                        context,
                        Icons.layers_outlined,
                        strings(context, 'floorLabel'),
                        ParkingModels.readString(body, 'floor'),
                      ),
                      _row(
                        context,
                        Icons.grid_on_outlined,
                        strings(context, 'spotLabel'),
                        ParkingModels.readString(body, 'spot'),
                      ),
                      _row(
                        context,
                        Icons.flag_outlined,
                        strings(context, 'landmarkLabel'),
                        ParkingModels.readString(body, 'landmark'),
                      ),
                      _row(
                        context,
                        Icons.my_location_outlined,
                        strings(context, 'coordinatesLabel'),
                        _coordinates(body),
                      ),
                      _row(
                        context,
                        Icons.schedule,
                        strings(context, 'startedLabel'),
                        _when(body, 'startedAt', context),
                      ),
                      _row(
                        context,
                        Icons.event_available,
                        strings(context, 'foundLabel'),
                        _when(body, 'foundAt', context),
                      ),
                      _row(
                        context,
                        Icons.timelapse,
                        strings(context, 'durationLabel'),
                        !ParkingLogic.knownDuration(body)
                            ? strings(context, 'unknownDate')
                            : ParkingFields.duration(
                                context,
                                strings,
                                ParkingLogic.elapsedOf(body, DateTime.now()),
                              ),
                      ),
                      if (ParkingModels.readDate(body, 'expiresAt') != null)
                        _row(
                          context,
                          Icons.timer_outlined,
                          strings(context, 'expiryLabel'),
                          _when(body, 'expiresAt', context),
                        ),
                    ],
                  ),
                ),
                if (active)
                  Padding(
                    padding: const EdgeInsets.only(top: NexSpacing.md),
                    child: FilledButton.icon(
                      key: const ValueKey('parking-found'),
                      onPressed: () => unawaited(_found()),
                      icon: const Icon(Icons.directions_car_outlined),
                      label: Text(strings(context, 'foundMyCar')),
                    ),
                  ),
              ],
            ),
    );
  }

  String _coordinates(Map<String, Object?> body) {
    final lat = ParkingModels.readCoord(
      body,
      'lat',
      min: ParkingModels.latMin,
      max: ParkingModels.latMax,
    );
    final lng = ParkingModels.readCoord(
      body,
      'lng',
      min: ParkingModels.lngMin,
      max: ParkingModels.lngMax,
    );
    if (lat == null || lng == null) {
      return parkingStrings(context, 'noValue');
    }
    return ParkingFields.digits(context, '${_trim(lat)}, ${_trim(lng)}');
  }

  static String _trim(double value) {
    var text = value.toStringAsFixed(5);
    while (text.contains('.') && (text.endsWith('0') || text.endsWith('.'))) {
      text = text.substring(0, text.length - 1);
    }
    return text;
  }

  String _when(Map<String, Object?> body, String key, BuildContext context) {
    final value = ParkingModels.readDate(body, key)?.toLocal();
    if (value == null) {
      return parkingStrings(context, 'noValue');
    }
    return ParkingFields.startedAt(context, value);
  }

  Widget _row(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: NexSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 20,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: NexSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                value.isEmpty ? parkingStrings(context, 'noValue') : value,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
