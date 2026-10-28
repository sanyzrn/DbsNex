import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import '../platform/update_service.dart';
import '../screens/timeline_screen.dart';
import 'desktop_nav.dart';
import 'desktop_sidebar.dart';

/// The desktop frame: a rail on the leading side and, beside it, the app's
/// Navigator, which is told its window is only as wide as what is left.
///
/// In a narrow window this is the Navigator and nothing else. The tree is the
/// same shape either way, so crossing the breakpoint while resizing keeps
/// every page and its state.
class NexDesktopShell extends StatelessWidget {
  const NexDesktopShell({
    super.key,
    required this.nav,
    required this.services,
    required this.preferences,
    required this.timelineKey,
    required this.updates,
    required this.child,
  });

  final NexDesktopNav nav;
  final NexServices services;
  final NexPreferences preferences;
  final GlobalKey<TimelineScreenState> timelineKey;
  final UpdateService? updates;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final wide =
        nexWideWindow(media.size.width) && preferences.onboardingComplete;
    const rail = NexSidebar.width;
    return NexDesktopScope(
      enabled: wide,
      child: Stack(
        children: [
          PositionedDirectional(
            start: wide ? rail : 0,
            end: 0,
            top: 0,
            bottom: 0,
            child: MediaQuery(
              data: wide
                  ? media.copyWith(
                      size: Size(media.size.width - rail, media.size.height),
                    )
                  : media,
              child: child,
            ),
          ),
          if (wide)
            PositionedDirectional(
              start: 0,
              top: 0,
              bottom: 0,
              width: rail,
              child: _RailHost(
                child: NexSidebar(
                  nav: nav,
                  services: services,
                  preferences: preferences,
                  timelineKey: timelineKey,
                  updates: updates,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The rail sits above the app's Navigator, so it has no Overlay of its own,
/// and a tooltip needs one. This gives it a small one.
class _RailHost extends StatefulWidget {
  const _RailHost({required this.child});

  final Widget child;

  @override
  State<_RailHost> createState() => _RailHostState();
}

class _RailHostState extends State<_RailHost> {
  late final _entry = OverlayEntry(builder: (_) => widget.child);

  @override
  void didUpdateWidget(_RailHost old) {
    super.didUpdateWidget(old);
    _entry.markNeedsBuild();
  }

  @override
  void dispose() {
    _entry
      ..remove()
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_entry]);
}
