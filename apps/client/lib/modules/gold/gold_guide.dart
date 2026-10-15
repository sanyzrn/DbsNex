/// The guide page: the formula in plain words, what this tool is not, the
/// scope note, and the «Ask for these on the invoice» checklist. Also home
/// of the small disclosure the calculator shows inline.
library;

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'gold_strings.dart';

/// The whole guide, as one scrolling page. Pushed with [NexPageRoute].
class GoldGuidePage extends StatelessWidget {
  const GoldGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = goldStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: NexAppBar(title: Text(strings(context, 'guideTitle'))),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: NexSpacing.md),
        children: [
          const SizedBox(height: NexSpacing.md),
          _Section(
            icon: Icons.calculate_outlined,
            title: strings(context, 'howTitle'),
            children: [
              for (var i = 1; i <= 5; i++)
                _Paragraph(strings(context, 'howBody$i')),
            ],
          ),
          _Section(
            icon: Icons.help_outline,
            title: strings(context, 'disclaimerTitle'),
            children: [_Paragraph(strings(context, 'disclaimerBody'))],
          ),
          _Section(
            icon: Icons.inventory_2_outlined,
            title: null,
            children: [_Paragraph(strings(context, 'scopeNote'))],
          ),
          _Section(
            icon: Icons.checklist_outlined,
            title: strings(context, 'checklistTitle'),
            children: [
              _Paragraph(strings(context, 'checklistNote')),
              const SizedBox(height: NexSpacing.sm),
              for (var i = 1; i <= 9; i++)
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    bottom: NexSpacing.sm,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          top: NexSpacing.xs + 2,
                        ),
                        child: Icon(
                          Icons.check_circle_outline,
                          size: 18,
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(width: NexSpacing.sm),
                      Expanded(
                        child: Text(
                          strings(context, 'check$i'),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: NexSpacing.xl),
        ],
      ),
    );
  }
}

/// The small «How this is calculated» disclosure the calculator carries.
/// Closed until asked; opens on the module's own motion tokens and stays
/// still when the person has asked the system for less movement.
class GoldHowCalculated extends StatelessWidget {
  const GoldHowCalculated({
    super.key,
    required this.open,
    required this.onToggle,
  });

  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = goldStrings;
    return AnimatedSize(
      duration: NexMotion.of(context, NexMotion.standard),
      curve: NexMotion.curve,
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(NexRadius.md),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: NexSpacing.sm,
                horizontal: NexSpacing.xs,
              ),
              child: Row(
                children: [
                  Icon(
                    open ? Icons.expand_less : Icons.expand_more,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: NexSpacing.sm),
                  Expanded(
                    child: Text(
                      strings(context, 'howTitle'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: NexSpacing.md,
                end: NexSpacing.xs,
                bottom: NexSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 1; i <= 5; i++)
                    _Paragraph(strings(context, 'howBody$i')),
                  _Paragraph(strings(context, 'disclaimerBody')),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = this.title;
    return Padding(
      padding: const EdgeInsets.only(bottom: NexSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              if (title != null) ...[
                const SizedBox(width: NexSpacing.sm),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: NexSpacing.sm),
          ...children,
        ],
      ),
    );
  }
}

class _Paragraph extends StatelessWidget {
  const _Paragraph(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(bottom: NexSpacing.sm),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
