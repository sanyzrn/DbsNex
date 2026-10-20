part of 'warranty_widgets.dart';

class WarrantyClaimSheet extends StatefulWidget {
  const WarrantyClaimSheet({
    super.key,
    required this.store,
    required this.parentId,
    required this.kind,
  });

  final String kind;
  final NexModuleStore store;
  final String parentId;

  @override
  State<WarrantyClaimSheet> createState() => _WarrantyClaimSheetState();
}

class _WarrantyClaimSheetState extends State<WarrantyClaimSheet> {
  final _note = TextEditingController();
  bool _showError = false;
  late final EditorCheckpoint _session;
  @override
  void initState() {
    super.initState();
    _session = EditorCheckpoint(
      widget.store,
      'claim',
      null,
      {'note': _note},
      () => {'parentId': widget.parentId, 'kind': widget.kind},
      (_) {},
      () {
        if (mounted) {
          setState(() {});
        }
      },
    );
    unawaited(_session.load());
  }

  @override
  void dispose() {
    _session.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = warrantyStrings;
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    return CheckpointFrame(
      session: _session,
      checkpointBack: true,
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
                  widget.kind == WarrantyModels.claimKind
                      ? 'addClaim'
                      : 'addService',
                ),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: NexSpacing.md),
              WarrantyTextField(
                key: const ValueKey('warranty-claim-field'),
                controller: _note,
                hint: strings(context, 'claimPlaceholder'),
                helper: _showError ? strings(context, 'claimRequired') : null,
              ),
              const SizedBox(height: NexSpacing.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('warranty-claim-save'),
                  onPressed: _session.busy
                      ? null
                      : () async {
                          if (_note.text.trim().isEmpty) {
                            setState(() => _showError = true);
                            return;
                          }
                          setState(() => _session.busy = true);
                          try {
                            await WarrantyRepository.claim(
                              widget.store,
                              widget.parentId,
                              _session.recordId,
                              widget.kind,
                              _note.text,
                            );
                            await _session.draft.clear();
                            if (context.mounted) {
                              Navigator.of(context).pop();
                            }
                          } catch (_) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(strings(context, 'saveFailed')),
                                ),
                              );
                            }
                          } finally {
                            if (mounted) {
                              setState(() => _session.busy = false);
                            }
                          }
                        },
                  child: Text(AppLocalizations.of(context).save),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One dated claim or service note.
class WarrantyClaimRow extends StatelessWidget {
  const WarrantyClaimRow({super.key, required this.claim, this.onDelete});

  final ModuleRecord claim;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final strings = warrantyStrings;
    final theme = Theme.of(context);
    final at = WarrantyModels.readDate(claim.body, 'at')?.toLocal();
    final knownKind = const ['claim', 'service'].contains(claim.body['kind']);
    final isClaim =
        WarrantyModels.readString(claim.body, 'kind') ==
        WarrantyModels.claimKind;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        isClaim ? Icons.report_outlined : Icons.build_outlined,
        color: (isClaim ? NexHue.rose : NexHue.slate).of(theme.brightness),
      ),
      title: Text(
        WarrantyModels.readString(claim.body, 'note'),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: at == null
          ? null
          : Text(
              '${strings(context, !knownKind
                  ? 'unknownLog'
                  : isClaim
                  ? 'claimed'
                  : 'serviced')} — '
              '${WarrantyFields.instantLabel(context, at)}',
            ),
      trailing: IconButton(
        key: ValueKey('warranty-claim-delete-${claim.id}'),
        tooltip: AppLocalizations.of(context).delete,
        icon: const Icon(Icons.delete_outline),
        onPressed: onDelete,
      ),
    );
  }
}

/// The claims and service section of the detail sheet: the two add
/// actions and the dated notes under them, each deletable as a
/// correction.
class WarrantyClaimsSection extends StatelessWidget {
  const WarrantyClaimsSection({
    super.key,
    required this.claims,
    required this.onAdd,
    required this.onDeleteClaim,
  });

  final List<ModuleRecord> claims;

  /// Adds a claim or a service note, per [WarrantyModels.claimKind] and
  /// [WarrantyModels.serviceKind].
  final void Function(String kind) onAdd;
  final void Function(ModuleRecord claim) onDeleteClaim;

  @override
  Widget build(BuildContext context) {
    final strings = warrantyStrings;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('warranty-add-claim'),
                onPressed: () => onAdd(WarrantyModels.claimKind),
                icon: const Icon(Icons.report_outlined),
                label: Text(strings(context, 'addClaim')),
              ),
            ),
            const SizedBox(width: NexSpacing.sm),
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('warranty-add-service'),
                onPressed: () => onAdd(WarrantyModels.serviceKind),
                icon: const Icon(Icons.build_outlined),
                label: Text(strings(context, 'addService')),
              ),
            ),
          ],
        ),
        const SizedBox(height: NexSpacing.md),
        Text(
          strings(context, 'claimsTitle'),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: NexSpacing.sm),
        if (claims.isEmpty)
          Text(
            strings(context, 'noClaims'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final claim in claims)
            WarrantyClaimRow(
              claim: claim,
              onDelete: () => onDeleteClaim(claim),
            ),
      ],
    );
  }
}
