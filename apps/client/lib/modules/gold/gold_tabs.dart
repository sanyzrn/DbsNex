import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

/// Gold's destinations in one place (2.8.2): every tab once opened stays
/// built — its fields, its scroll, what was typed — and only the one chosen
/// is laid out and shown, fading in over a short rise.
///
/// Selling used to be a page pushed over buying, so a tap on a tab slid the
/// whole screen away and brought another in, and the form under it was read
/// back from storage each time: it looked, and was, a reload.
class GoldKeptTabs extends StatefulWidget {
  const GoldKeptTabs({super.key, required this.index, required this.builders});

  final int index;

  /// Built the first time its tab is chosen, then kept.
  final List<WidgetBuilder> builders;

  @override
  State<GoldKeptTabs> createState() => _GoldKeptTabsState();
}

class _GoldKeptTabsState extends State<GoldKeptTabs>
    with SingleTickerProviderStateMixin {
  late final _built = <int>{widget.index};
  late final AnimationController _arrive = AnimationController(
    vsync: this,
    value: 1,
  );

  @override
  void didUpdateWidget(GoldKeptTabs old) {
    super.didUpdateWidget(old);
    if (old.index == widget.index) return;
    _built.add(widget.index);
    _arrive
      ..duration = NexMotion.of(context, NexMotion.standard)
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _arrive.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final arriving = CurvedAnimation(parent: _arrive, curve: NexMotion.curve);
    const still = AlwaysStoppedAnimation<double>(1);
    // The same widgets above every tab, chosen or not: a tab whose wrapping
    // changed when it was chosen would be a new tab, and its state gone.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < widget.builders.length; i++)
          if (_built.contains(i))
            KeyedSubtree(
              key: ValueKey('gold-tab-$i'),
              child: Offstage(
                offstage: i != widget.index,
                child: TickerMode(
                  enabled: i == widget.index,
                  child: FadeTransition(
                    opacity: i == widget.index ? arriving : still,
                    child: SlideTransition(
                      position: (i == widget.index ? arriving : still).drive(
                        Tween(begin: const Offset(0, 0.015), end: Offset.zero),
                      ),
                      child: Builder(builder: widget.builders[i]),
                    ),
                  ),
                ),
              ),
            ),
      ],
    );
  }
}
