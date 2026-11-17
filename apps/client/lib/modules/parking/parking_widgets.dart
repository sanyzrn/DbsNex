import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'parking_fields.dart';
import 'parking_logic.dart';
import 'parking_models.dart';
import 'parking_quick_reminder.dart';
import 'parking_strings.dart';

/// The rows and cards of the parking screen, kept apart so the screen file
/// stays about flow and storage. Everything shown here was typed by the
/// person: no field implies a sensor read it.
///
/// The remaining time on a paid session is read while the screen is open,
/// from a time the person wrote themselves. A person who wants to be told
/// after closing the app sets the explicit, opt-in device reminder on the
/// open parking's card; the countdown itself never runs in the background.

/// The open parking: the place big enough to read at a glance, the floor
/// and spot beside it, and how long it has been there.
class ParkingActiveCard extends StatelessWidget {
  const ParkingActiveCard({
    super.key,
    required this.store,
    required this.record,
    required this.onFound,
    required this.onEdit,
  });

  final NexModuleStore store;

  final ModuleRecord record;

  /// «Found my car» — closes the session by recording `foundAt`.
  final VoidCallback onFound;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final strings = parkingStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = record.body;
    final now = DateTime.now();
    final place = ParkingModels.readString(body, 'place');
    final vehicle = ParkingModels.readString(body, 'vehicle');
    final floor = ParkingModels.readString(body, 'floor');
    final spot = ParkingModels.readString(body, 'spot');
    final elapsed = !ParkingLogic.knownDuration(body)
        ? strings(context, 'unknownDate')
        : ParkingFields.duration(
            context,
            strings,
            ParkingLogic.elapsedOf(body, now),
          );
    final expiry = ParkingLogic.expiryOf(body, now);
    final expiryLeft = ParkingFields.duration(
      context,
      strings,
      Duration(minutes: expiry.minutes),
    );
    final expiresAt = ParkingModels.readDate(body, 'expiresAt');

    return NexPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  place.isEmpty ? strings(context, 'detailsTitle') : place,
                  style: theme.textTheme.headlineSmall,
                ),
              ),
              IconButton(
                key: const ValueKey('parking-active-edit'),
                tooltip: AppLocalizations.of(context).edit,
                icon: const Icon(Icons.edit_outlined),
                onPressed: onEdit,
              ),
            ],
          ),
          const SizedBox(height: NexSpacing.xs),
          Wrap(
            spacing: NexSpacing.sm,
            runSpacing: NexSpacing.xs,
            children: [
              if (vehicle.isNotEmpty)
                _chip(context, Icons.directions_car_outlined, vehicle),
              if (floor.isNotEmpty)
                _chip(
                  context,
                  Icons.layers_outlined,
                  strings(context, 'floorShort', {'value': floor}),
                ),
              if (spot.isNotEmpty) _chip(context, Icons.grid_on_outlined, spot),
            ],
          ),
          const SizedBox(height: NexSpacing.md),
          Text(
            strings(context, 'elapsed', {'duration': elapsed}),
            style: theme.textTheme.titleMedium?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (expiresAt != null) ...[
            const SizedBox(height: NexSpacing.sm),
            // The number a person glances at from across the car park: how
            // long is left, large, with what it means underneath.
            Text(
              expiryLeft,
              key: const ValueKey('parking-time-left'),
              style: theme.textTheme.headlineLarge?.copyWith(
                color: expiry.over ? scheme.error : scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              strings(context, expiry.over ? 'timeLeftOver' : 'timeLeft'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: expiry.over ? scheme.error : scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (place.isEmpty)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('parking-add-where'),
                onPressed: onEdit,
                icon: const Icon(Icons.add_location_alt_outlined),
                label: Text(strings(context, 'addWhere')),
              ),
            ),
          const SizedBox(height: NexSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('parking-found'),
              onPressed: onFound,
              icon: const Icon(Icons.directions_car_outlined),
              label: Text(strings(context, 'foundMyCar')),
            ),
          ),
          const SizedBox(height: NexSpacing.xs),
          Text(
            strings(context, 'reminderNote'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          // Opt-in: an OS alert for when paid time runs out or the car is
          // needed. Wired to this record, so the platform auto-cancels when
          // the parking is deleted — and «I'm back» clears it too
          // (parking_repository.dart). A parking with a paid time counts
          // back from it (ten minutes by default) instead of asking for an
          // arbitrary moment.
          if (expiresAt != null)
            ParkingQuickReminder(
              key: const ValueKey('parking-quick-reminder'),
              store: store,
              recordId: record.id,
              expiresAt: expiresAt,
              place: place,
              floor: floor,
            )
          else
            NexModuleReminderControl(
              key: const ValueKey('parking-reminders'),
              store: store,
              sourceKind: ParkingModels.session,
              sourceId: record.id,
            ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, IconData icon, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        icon,
        size: 16,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: NexSpacing.xs),
      Flexible(
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    ],
  );
}

/// One closed parking in the history.
class ParkingHistoryRow extends StatelessWidget {
  const ParkingHistoryRow({
    super.key,
    required this.record,
    required this.onTap,
    required this.onDelete,
  });

  final ModuleRecord record;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final strings = parkingStrings;
    final theme = Theme.of(context);
    final body = record.body;
    final started = ParkingModels.readDate(body, 'startedAt');
    final place = ParkingModels.readString(body, 'place');
    final vehicle = ParkingModels.readString(body, 'vehicle');
    final when = started == null ? '' : _date(context, started.toLocal());
    final duration = !ParkingLogic.knownDuration(body)
        ? strings(context, 'unknownDate')
        : ParkingFields.duration(
            context,
            strings,
            ParkingLogic.elapsedOf(body, DateTime.now()),
          );
    final subtitle = [
      if (vehicle.isNotEmpty) vehicle,
      if (when.isNotEmpty) when,
      duration,
    ].join(' · ');

    return ListTile(
      key: ValueKey('parking-history-${record.id}'),
      onTap: onTap,
      leading: NexIconTile(
        Icons.local_parking_outlined,
        color: NexHue.sky.of(theme.brightness),
      ),
      title: Text(
        place.isEmpty ? strings(context, 'detailsTitle') : place,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: subtitle.isEmpty ? null : Text(subtitle, maxLines: 1),
      trailing: IconButton(
        key: ValueKey('parking-delete-${record.id}'),
        tooltip: AppLocalizations.of(context).delete,
        icon: const Icon(Icons.delete_outline),
        onPressed: onDelete,
      ),
    );
  }
}

/// A remembered place, one tap from a new parking.
class ParkingPlaceRow extends StatelessWidget {
  const ParkingPlaceRow({
    super.key,
    required this.record,
    this.onTap,
    this.onFavourite,
  });

  final ModuleRecord record;
  final VoidCallback? onTap;

  /// Marks or unmarks this place as a favourite. A favourite is only a
  /// shortcut: it fills the editor, it never parks the car by itself.
  final ValueChanged<bool>? onFavourite;

  @override
  Widget build(BuildContext context) {
    final body = record.body;
    final theme = Theme.of(context);
    final place = ParkingModels.readString(body, 'place');
    final floor = ParkingModels.readString(body, 'floor');
    final spot = ParkingModels.readString(body, 'spot');
    final details = [floor, spot].where((s) => s.isNotEmpty).join(' · ');
    final favourite = ParkingModels.isFavourite(body);

    return ListTile(
      key: ValueKey('parking-place-${record.id}'),
      onTap: onTap,
      leading: NexIconTile(
        favourite ? Icons.star_outline : Icons.bookmark_outline,
        color: NexHue.sky.of(theme.brightness),
      ),
      title: Text(place, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: details.isEmpty ? null : Text(details, maxLines: 1),
      trailing: IconButton(
        key: ValueKey('parking-favourite-${record.id}'),
        tooltip: parkingStrings(context, 'markFavourite'),
        isSelected: favourite,
        icon: const Icon(Icons.star_outline),
        selectedIcon: const Icon(Icons.star),
        onPressed: onFavourite == null ? null : () => onFavourite!(!favourite),
      ),
    );
  }
}

// ---------------------------------------------------------------- helpers

/// A date said as "today" when it is this day, in the person's own
/// calendar otherwise — Jalali for a Persian reader, Gregorian for an
/// English one.
String _date(BuildContext context, DateTime value) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  // The civil day is rebuilt in the local zone, so a western time zone
  // never prints the day before the one the parking began.
  final that = DateTime(value.year, value.month, value.day);
  if (that == today) {
    return parkingStrings(context, 'justNow');
  }
  return nexModuleDateLabel(context, that);
}
