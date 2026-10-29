import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'module.dart';
import 'occasion_model.dart';

/// The greetings for a kind of date, three of each (2.4.0): one was the same
/// words for every friend, every year.
List<String> occasionGreetings(BuildContext context, OccasionKind kind) {
  final base = switch (kind) {
    OccasionKind.birthday => 'greetBirthday',
    OccasionKind.anniversary => 'greetAnniversary',
    OccasionKind.memorial => 'greetMemorial',
    OccasionKind.other => 'greetOther',
  };
  return [
    occasionsStrings(context, base),
    occasionsStrings(context, '${base}2'),
    occasionsStrings(context, '${base}3'),
  ];
}

Future<void> _copy(BuildContext context, String text) async {
  await nexModuleCopyText(text);
  if (!context.mounted) return;
  nexShowBanner(context, message: occasionsStrings(context, 'greetingCopied'));
}

/// Copy and share, in white, for the coloured card on the day itself.
class OccasionGreetingActions extends StatelessWidget {
  const OccasionGreetingActions({super.key, required this.occasion});

  final Occasion occasion;

  @override
  Widget build(BuildContext context) {
    final text = occasionGreetings(context, occasion.kind).first;
    final style = FilledButton.styleFrom(
      backgroundColor: Colors.white.withValues(alpha: 0.22),
      foregroundColor: Colors.white,
    );
    return Wrap(
      spacing: NexSpacing.sm,
      runSpacing: NexSpacing.sm,
      children: [
        FilledButton.icon(
          key: const ValueKey('occasion-hero-copy'),
          style: style,
          onPressed: () => unawaited(_copy(context, text)),
          icon: const Icon(Icons.copy_outlined, size: 18),
          label: Text(occasionsStrings(context, 'copyGreeting')),
        ),
        FilledButton.icon(
          key: const ValueKey('occasion-hero-share'),
          style: style,
          onPressed: () => unawaited(nexModuleShareText(text)),
          icon: const Icon(Icons.ios_share, size: 18),
          label: Text(occasionsStrings(context, 'shareGreeting')),
        ),
      ],
    );
  }
}

/// The greeting on an occasion's page: one of three, another a tap away,
/// ready to copy or share.
class OccasionGreetingPanel extends StatefulWidget {
  const OccasionGreetingPanel({super.key, required this.occasion});

  final Occasion occasion;

  @override
  State<OccasionGreetingPanel> createState() => _OccasionGreetingPanelState();
}

class _OccasionGreetingPanelState extends State<OccasionGreetingPanel> {
  var _index = 0;

  @override
  Widget build(BuildContext context) {
    final strings = occasionsStrings;
    final greetings = occasionGreetings(context, widget.occasion.kind);
    final text = greetings[_index % greetings.length];
    return NexPanel(
      title: strings(context, 'greetingTitle'),
      icon: Icons.chat_bubble_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedSwitcher(
            duration: NexMotion.of(context, NexMotion.standard),
            child: NexTextSurface(
              text,
              key: ValueKey('occasion-greeting-$_index'),
              selectable: true,
            ),
          ),
          const SizedBox(height: NexSpacing.sm),
          Wrap(
            spacing: NexSpacing.sm,
            runSpacing: NexSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonalIcon(
                key: const ValueKey('occasion-copy-greeting'),
                onPressed: () => unawaited(_copy(context, text)),
                icon: const Icon(Icons.copy_outlined),
                label: Text(strings(context, 'copyGreeting')),
              ),
              TextButton.icon(
                key: const ValueKey('occasion-share-greeting'),
                onPressed: () => unawaited(nexModuleShareText(text)),
                icon: const Icon(Icons.ios_share),
                label: Text(strings(context, 'shareGreeting')),
              ),
              TextButton.icon(
                key: const ValueKey('occasion-another-greeting'),
                onPressed: () => setState(() => _index++),
                icon: const Icon(Icons.autorenew),
                label: Text(strings(context, 'anotherGreeting')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
