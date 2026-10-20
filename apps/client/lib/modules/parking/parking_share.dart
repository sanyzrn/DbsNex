import 'package:flutter/material.dart';

import 'parking_fields.dart';
import 'parking_models.dart';
import 'parking_strings.dart';

/// Where the car is, as a few lines of text a person can send to whoever
/// is coming to meet them: the place, floor, spot and landmark they wrote
/// down, since when, and — only if they typed coordinates — a map link.
/// Built from the record alone; it is shared only by a tap on Share.
String parkingShareText(BuildContext context, Map<String, Object?> body) {
  final strings = parkingStrings;
  String text(String key) => ParkingModels.readString(body, key).trim();
  final lines = <String>[];
  void field(String label, String value) {
    if (value.isNotEmpty) lines.add('$label: $value');
  }

  field(strings(context, 'vehicleLabel'), text('vehicle'));
  field(strings(context, 'placeLabel'), text('place'));
  field(strings(context, 'floorLabel'), text('floor'));
  field(strings(context, 'spotLabel'), text('spot'));
  field(strings(context, 'landmarkLabel'), text('landmark'));
  final started = ParkingModels.readDate(body, 'startedAt')?.toLocal();
  if (started != null) {
    field(
      strings(context, 'startedLabel'),
      ParkingFields.when(context, started),
    );
  }
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
  if (lat != null && lng != null) {
    lines.add(
      'https://www.google.com/maps?q=${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}',
    );
  }
  return lines.join('\n');
}
