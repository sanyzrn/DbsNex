part of 'parking_editor.dart';

extension _ParkingEditorBody on _ParkingEditorSheetState {
  Widget _editorBody(BuildContext context) {
    final strings = parkingStrings;
    final theme = Theme.of(context);
    final expiry = ParkingParse.expiry(_expiryDate.text, _expiryTime.text);
    final lat = ParkingParse.coordinate(
      _lat.text,
      ParkingModels.latMin,
      ParkingModels.latMax,
    );
    final lng = ParkingParse.coordinate(
      _lng.text,
      ParkingModels.lngMin,
      ParkingModels.lngMax,
    );

    // The keyboard must not cover the save button: the module's own body
    // wrapper, because `NexSheetBody` is not part of the module API.
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_maybePop());
      },
      child: CheckpointFrame(
        session: _session,
        strings: strings,
        child: Padding(
          padding: EdgeInsets.only(bottom: viewInsets),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(NexSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings(
                    context,
                    widget.existing != null ? 'editParking' : 'newParking',
                  ),
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: NexSpacing.md),
                ParkingFields.line(
                  fieldKey: const ValueKey('parking-field-place'),
                  controller: _place,
                  label: strings(context, 'place'),
                  hint: strings(context, 'placeHint'),
                  helper: _showErrors && _place.text.trim().isEmpty
                      ? strings(context, 'placeRequired')
                      : null,
                ),
                const SizedBox(height: NexSpacing.sm),
                NexMoreDetails(
                  toggleKey: const ValueKey('parking-more-toggle'),
                  open: _moreOpen,
                  onChanged: _setMore,
                  title: strings(context, 'moreDetails'),
                  hint: strings(context, 'moreDetailsHint'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ParkingFields.line(
                        fieldKey: const ValueKey('parking-field-vehicle'),
                        controller: _vehicle,
                        label: strings(context, 'vehicle'),
                        hint: strings(context, 'vehicleHint'),
                      ),
                      const SizedBox(height: NexSpacing.sm),
                      Row(
                        children: [
                          Expanded(
                            child: ParkingFields.line(
                              fieldKey: const ValueKey('parking-field-floor'),
                              controller: _floor,
                              label: strings(context, 'floor'),
                              hint: strings(context, 'floorHint'),
                            ),
                          ),
                          const SizedBox(width: NexSpacing.sm),
                          Expanded(
                            child: ParkingFields.line(
                              fieldKey: const ValueKey('parking-field-spot'),
                              controller: _spot,
                              label: strings(context, 'spot'),
                              hint: strings(context, 'spotHint'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: NexSpacing.sm),
                      ParkingTextField(
                        controller: _landmark,
                        hint: strings(context, 'landmarkHint'),
                      ),
                      const SizedBox(height: NexSpacing.lg),
                      Text(
                        strings(context, 'coordinates'),
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        strings(context, 'coordinatesNote'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: NexSpacing.sm),
                      Row(
                        children: [
                          Expanded(
                            child: ParkingFields.line(
                              fieldKey: const ValueKey('parking-field-lat'),
                              controller: _lat,
                              label: strings(context, 'latitude'),
                              keyboard: const TextInputType.numberWithOptions(
                                decimal: true,
                                signed: true,
                              ),
                              helper: _showErrors && lat != null && lat.isNaN
                                  ? strings(context, 'badLatitude')
                                  : null,
                            ),
                          ),
                          const SizedBox(width: NexSpacing.sm),
                          Expanded(
                            child: ParkingFields.line(
                              fieldKey: const ValueKey('parking-field-lng'),
                              controller: _lng,
                              label: strings(context, 'longitude'),
                              keyboard: const TextInputType.numberWithOptions(
                                decimal: true,
                                signed: true,
                              ),
                              helper: _showErrors && lng != null && lng.isNaN
                                  ? strings(context, 'badLongitude')
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: NexSpacing.lg),
                      Text(
                        strings(context, 'expiry'),
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        strings(context, 'expiryNote'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: NexSpacing.sm),
                      Row(
                        children: [
                          Expanded(
                            child: NexModuleDateEntry(
                              controller: _expiryDate,
                              child: ParkingFields.line(
                                fieldKey: const ValueKey(
                                  'parking-field-expiry-date',
                                ),
                                controller: _expiryDate,
                                label: strings(context, 'expiryDate'),
                                hint: strings(context, 'dateHint'),
                                keyboard: TextInputType.datetime,
                                helper:
                                    _showErrors &&
                                        expiry == ParkingParse.invalid
                                    ? strings(context, 'badExpiry')
                                    : null,
                              ),
                            ),
                          ),
                          const SizedBox(width: NexSpacing.sm),
                          Expanded(
                            child: ParkingFields.line(
                              fieldKey: const ValueKey(
                                'parking-field-expiry-time',
                              ),
                              controller: _expiryTime,
                              label: strings(context, 'expiryTime'),
                              keyboard: TextInputType.datetime,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: NexSpacing.xs),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Wrap(
                          spacing: NexSpacing.sm,
                          children: [
                            ActionChip(
                              key: const ValueKey('parking-today'),
                              label: Text(strings(context, 'today')),
                              onPressed: () {
                                final now = DateTime.now();
                                // Zero padded, like the calendar button writes it.
                                _expiryDate.text =
                                    '${now.year}/${ParkingFields.two(now.month)}/${ParkingFields.two(now.day)}';
                              },
                            ),
                            // The one way to take a paid time back off the record.
                            ActionChip(
                              key: const ValueKey('parking-clear-time'),
                              label: Text(strings(context, 'clearTime')),
                              onPressed: () {
                                _expiryDate.clear();
                                _expiryTime.clear();
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: NexSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const ValueKey('parking-save'),
                    onPressed: _session.busy ? null : _save,
                    child: Text(strings(context, 'save')),
                  ),
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    key: const ValueKey('parking-keep-draft'),
                    onPressed: _session.busy ? null : _keepDraft,
                    child: Text(strings(context, 'keepDraft')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
