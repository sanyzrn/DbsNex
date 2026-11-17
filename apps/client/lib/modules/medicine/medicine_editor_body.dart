part of 'medicine_editor.dart';

extension _MedicineEditorBody on _MedicineEditorSheetState {
  Widget _editorBody(BuildContext context) {
    final strings = medicineStrings;
    final theme = Theme.of(context);

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
          // The save stays where the person can see it: a form this long
          // scrolled its own primary action off a small phone.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(NexSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings(
                          context,
                          widget.existing != null
                              ? 'editMedicine'
                              : 'addMedicine',
                        ),
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: NexSpacing.md),
                      MedicineFields.line(
                        fieldKey: const ValueKey('medicine-field-name'),
                        controller: _name,
                        label: strings(context, 'name'),
                        hint: strings(context, 'nameHint'),
                        helper: _showErrors && _name.text.trim().isEmpty
                            ? strings(context, 'nameRequired')
                            : null,
                      ),
                      const SizedBox(height: NexSpacing.sm),
                      Row(
                        children: [
                          Expanded(
                            child: MedicineFields.line(
                              fieldKey: const ValueKey(
                                'medicine-field-strength',
                              ),
                              controller: _strength,
                              label: strings(context, 'strength'),
                              hint: strings(context, 'strengthHint'),
                            ),
                          ),
                          const SizedBox(width: NexSpacing.sm),
                          Expanded(
                            child: MedicineFields.line(
                              fieldKey: const ValueKey(
                                'medicine-field-package',
                              ),
                              controller: _packageUnit,
                              label: strings(context, 'packageUnit'),
                              hint: strings(context, 'packageHint'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: NexSpacing.sm),
                      MedicineFields.line(
                        fieldKey: const ValueKey('medicine-field-person'),
                        controller: _person,
                        label: strings(context, 'person'),
                        hint: strings(context, 'personHint'),
                        helper: strings(context, 'personNote'),
                      ),
                      const SizedBox(height: NexSpacing.sm),
                      NexMoreDetails(
                        toggleKey: const ValueKey('medicine-more-toggle'),
                        open: _moreOpen,
                        onChanged: (open) => _paint(() => _more = open),
                        title: strings(context, 'moreDetails'),
                        hint: strings(context, 'moreDetailsHint'),
                        child: _detailsFields(context),
                      ),
                      const SizedBox(height: NexSpacing.lg),
                      Text(
                        strings(context, 'safetyNote'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  NexSpacing.md,
                  NexSpacing.sm,
                  NexSpacing.md,
                  NexSpacing.md,
                ),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: const ValueKey('medicine-save'),
                        onPressed: _session.busy ? null : _save,
                        child: Text(strings(context, 'save')),
                      ),
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        key: const ValueKey('medicine-keep-draft'),
                        onPressed: _session.busy ? null : _keepDraft,
                        child: Text(strings(context, 'keepDraft')),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
