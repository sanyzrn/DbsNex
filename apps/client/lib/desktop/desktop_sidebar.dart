import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_data/nex_data.dart' show TagUsage;
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import '../platform/update_service.dart';
import '../screens/timeline_screen.dart';
import '../widgets/nex_brand.dart';
import 'desktop_nav.dart';

/// The left rail (`docs/27-desktop.md`): where the phone has a dock.
///
/// Small, quiet, one column: the wordmark, the way to write a note, the
/// places, then the tags with their colours, and Settings at the foot.
class NexSidebar extends StatefulWidget {
  const NexSidebar({
    super.key,
    required this.nav,
    required this.services,
    required this.preferences,
    required this.timelineKey,
    required this.updates,
  });

  static const width = 232.0;

  final NexDesktopNav nav;
  final NexServices services;
  final NexPreferences preferences;
  final GlobalKey<TimelineScreenState> timelineKey;
  final UpdateService? updates;

  @override
  State<NexSidebar> createState() => _NexSidebarState();
}

class _NexSidebarState extends State<NexSidebar> {
  StreamSubscription<List<Note>>? _changes;
  Timer? _debounce;
  List<TagUsage> _tags = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadTags());
    // Every note written, tagged or deleted lands here; the tag list and the
    // timeline's own filter state are read again once it settles.
    _changes = widget.services.timelineStream.listen((_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 150), () {
        unawaited(_loadTags());
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    unawaited(_changes?.cancel());
    super.dispose();
  }

  Future<void> _loadTags() async {
    try {
      final usage = await widget.services.tagUsage();
      if (!mounted) return;
      setState(
        () => _tags = [
          for (final u in usage)
            if (u.count > 0) u,
        ],
      );
    } catch (_) {
      // A rail without its tags is still a rail.
    }
  }

  TimelineScreenState? get _timeline => widget.timelineKey.currentState;

  void _section(NexSection section) {
    // Nothing happens underneath an open dialog or panel.
    if (widget.nav.covered) return;
    if (section == NexSection.notes) unawaited(_timeline?.clearFilterForRail());
    widget.nav.go(section);
  }

  void _tag(String id) {
    if (widget.nav.covered) return;
    widget.nav.go(NexSection.notes);
    unawaited(_timeline?.showOnlyTag(id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final persian = Localizations.localeOf(context).languageCode == 'fa';
    final timeline = _timeline;
    return AnimatedBuilder(
      animation: Listenable.merge([widget.nav, ?timeline?.filterChanges]),
      builder: (context, _) {
        final section = widget.nav.section;
        final tagIds = timeline?.activeTagIds ?? const <String>{};
        final home = section == NexSection.notes;
        return DecoratedBox(
          decoration: BoxDecoration(
            border: BorderDirectional(
              end: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 8),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: NexLogotype(height: 14),
                    ),
                  ),
                  const SizedBox(height: NexSpacing.md),
                  Tooltip(
                    message: 'Ctrl+N',
                    child: FilledButton.icon(
                      onPressed: widget.nav.covered
                          ? null
                          : () => unawaited(_timeline?.openCapture()),
                      icon: const Icon(Icons.add, size: 16),
                      label: Text(l10n.capture),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 34),
                        visualDensity: VisualDensity.compact,
                        textStyle: Theme.of(
                          context,
                        ).textTheme.labelLarge?.copyWith(fontSize: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(NexRadius.sm),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: NexSpacing.md),
                  _RailItem(
                    icon: Icons.notes_rounded,
                    label: l10n.desktopNotes,
                    selected: home && tagIds.isEmpty,
                    onTap: () => _section(NexSection.notes),
                  ),
                  _RailItem(
                    icon: Icons.auto_awesome_outlined,
                    label: l10n.assistant,
                    onTap: () {
                      if (!widget.nav.covered) _timeline?.showAssistant();
                    },
                  ),
                  _RailItem(
                    icon: Icons.event_repeat_outlined,
                    label: l10n.commitmentsTitle,
                    selected: section == NexSection.recurring,
                    onTap: () => _section(NexSection.recurring),
                  ),
                  _RailItem(
                    icon: Icons.inventory_2_outlined,
                    label: l10n.libraryTitle,
                    selected: section == NexSection.library,
                    onTap: () => _section(NexSection.library),
                  ),
                  _RailItem(
                    icon: Icons.space_dashboard_outlined,
                    label: l10n.toolsTitle,
                    selected: section == NexSection.tools,
                    onTap: () => _section(NexSection.tools),
                  ),
                  if (_tags.isNotEmpty) ...[
                    const SizedBox(height: NexSpacing.md),
                    _RailLabel(l10n.tags, persian: persian),
                    const SizedBox(height: NexSpacing.xs),
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          for (final usage in _tags)
                            _RailItem(
                              leading: _Dot(
                                nexParseTagColor(usage.tag.color) ??
                                    scheme.outline,
                              ),
                              label: usage.tag.name,
                              count: usage.count,
                              selected: home && tagIds.contains(usage.tag.id),
                              onTap: () => _tag(usage.tag.id),
                            ),
                        ],
                      ),
                    ),
                  ] else
                    const Spacer(),
                  _RailItem(
                    icon: Icons.settings_outlined,
                    label: l10n.settings,
                    selected: section == NexSection.settings,
                    badge: _updateDot(l10n),
                    onTap: () => _section(NexSection.settings),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget? _updateDot(AppLocalizations l10n) {
    final service = widget.updates;
    if (service == null) return null;
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) => service.hasUpdate
          ? Semantics(
              label: l10n.updateAvailableBadge,
              child: const ExcludeSemantics(child: NexBadgeDot()),
            )
          : const SizedBox.shrink(),
    );
  }
}

/// A section label: small, quiet, in capitals where the script has them.
class _RailLabel extends StatelessWidget {
  const _RailLabel(this.text, {required this.persian});

  final String text;
  final bool persian;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(start: 8, top: 4),
    child: Text(
      persian ? text : text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        fontSize: 11,
        // Letter-spacing would pull Persian letters apart.
        letterSpacing: persian ? 0 : 0.8,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _Dot extends StatelessWidget {
  const _Dot(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// One row of the rail: an icon (or a tag's dot), a name, and at the far end
/// a count or a badge. A hover and a quiet fill for the one that is current.
class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.label,
    required this.onTap,
    this.icon,
    this.leading,
    this.count,
    this.badge,
    this.selected = false,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final Widget? leading;
  final int? count;
  final Widget? badge;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(NexRadius.sm),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected
            ? scheme.onSurface.withValues(alpha: 0.07)
            : Colors.transparent,
        shape: shape,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          hoverColor: scheme.onSurface.withValues(alpha: 0.05),
          child: Semantics(
            button: true,
            selected: selected,
            label: label,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    child: Center(
                      child:
                          leading ??
                          Icon(
                            icon,
                            size: 17,
                            color: selected
                                ? scheme.onSurface
                                : scheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: selected
                            ? scheme.onSurface
                            : scheme.onSurface.withValues(alpha: 0.82),
                      ),
                    ),
                  ),
                  if (badge case final badge?) badge,
                  if (count != null)
                    Text(
                      '$count',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
