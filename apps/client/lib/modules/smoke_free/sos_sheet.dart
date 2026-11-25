import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'craving_sheet.dart';
import 'craving_rating.dart';
import 'draft_guard.dart';
import 'form_draft.dart';
import 'module.dart';
import 'quit_model.dart';
import 'sos_breathing.dart';
import 'sos_clock.dart';

Future<void> showSosSheet(
  BuildContext context,
  NexModuleStore store,
  QuitAttempt attempt,
) => nexShowSheet<void>(
  context: context,
  dismissible: false,
  swipeToClose: true,
  builder: (_) => _SosSheet(store: store, attempt: attempt),
);

enum _Mode { breathe, wait, distract }

class _SosSheet extends StatefulWidget {
  const _SosSheet({required this.store, required this.attempt});
  final NexModuleStore store;
  final QuitAttempt attempt;
  @override
  State<_SosSheet> createState() => _SosSheetState();
}

class _SosSheetState extends State<_SosSheet> with WidgetsBindingObserver {
  _Mode _mode = _Mode.breathe;
  int _before = 2;
  int? _after;
  int _minutes = 10, _left = 600;
  DateTime? _deadline;
  Timer? _timer;
  bool _loading = true, _failed = false, _leaving = false;
  late DateTime _helpAt;
  late final _draft = FormDraft(
    widget.store,
    'sos:${widget.attempt.key}',
    {
      'attempt': widget.attempt.id,
      'startedAt': widget.attempt.startedAt.toIso8601String(),
    },
    const {},
    () => {
      'at': _helpAt.toIso8601String(),
      'before': _before,
      'after': _after,
      'mode': _mode.name,
      'minutes': _minutes,
      'left': _left,
      'deadline': _deadline?.toIso8601String(),
    },
  );

  @override
  void initState() {
    super.initState();
    _helpAt = DateTime.now();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  Future<void> _load() async {
    final body = await _draft.load();
    if (!mounted) return;
    if (_draft.loadFailed) {
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }
    if (body != null) {
      final before = body['before'], after = body['after'];
      if (before is int && before >= 1 && before <= 3) _before = before;
      if (after is int && after >= 1 && after <= 3) _after = after;
      _mode =
          _Mode.values.where((m) => m.name == body['mode']).firstOrNull ??
          _Mode.breathe;
      if ([2, 5, 10].contains(body['minutes'])) {
        _minutes = body['minutes'] as int;
      }
      _left = body['left'] is int
          ? (body['left'] as int).clamp(0, _minutes * 60)
          : _minutes * 60;
      _deadline = DateTime.tryParse('${body['deadline'] ?? ''}');
      final restoredAt = DateTime.tryParse('${body['at'] ?? ''}');
      if (restoredAt != null) _helpAt = restoredAt;
      if (_deadline != null) _sync();
    }
    _draft.start();
    setState(() {
      _loading = false;
      _failed = false;
    });
    if (_deadline != null && _left > 0) _arm();
  }

  void _change(VoidCallback action) {
    setState(action);
    _draft.changed();
  }

  void _sync() {
    final end = _deadline;
    if (end == null) return;
    final clockLeft = sosSecondsLeft(end, DateTime.now());
    if (clockLeft < _left) _left = clockLeft;
  }

  void _arm() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      // The monotonic tick keeps progress smooth if wall time moves backwards;
      // the deadline catches up after delayed callbacks or a background pause.
      if (_left > 0) _left--;
      _sync();
      if (_left == 0) {
        _timer?.cancel();
        _draft.changed();
      }
      if (mounted && _mode == _Mode.wait) setState(() {});
    });
  }

  void _start() {
    _change(() {
      _left = _minutes * 60;
      _deadline = DateTime.now().add(Duration(minutes: _minutes));
    });
    _arm();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _sync();
      if (mounted) setState(() {});
      if (_deadline != null && _left > 0) _arm();
    } else {
      _timer?.cancel();
      _draft.changed();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _draft.close();
    super.dispose();
  }

  Future<void> _record() async {
    if (_leaving || _loading || _failed) return;
    setState(() => _leaving = true);
    final navigator = Navigator.of(context);
    final coping = switch (_mode) {
      _Mode.breathe => 'deepBreath',
      _Mode.wait => 'waited',
      _Mode.distract => 'distraction',
    };
    // Keep the SOS checkpoint until the editable log owns a durable draft.
    // Opening the form never creates a craving or infers a success.
    _draft.changed();
    if (!await _draft.finish()) {
      _draft.resume();
      if (mounted) {
        setState(() => _leaving = false);
        nexShowBanner(
          context,
          message: smokeFreeStrings(context, 'saveError'),
          kind: NexBannerKind.failed,
        );
      }
      return;
    }
    if (!mounted) return;
    navigator.pop();
    await showCravingSheet(
      navigator.context,
      widget.store,
      habit: widget.attempt.key,
      initialIntensity: _before,
      initialCoping: coping,
      afterIntensity: _after,
      at: _helpAt,
    );
    try {
      await _draft.clear();
    } catch (_) {
      // The craving is durable; a checkpoint that cannot be cleared is
      // stale, not a reason to surface a failure after the log is saved.
    }
  }

  Widget _ratings({required bool after}) => CravingRating(
    key: ValueKey(after ? 'sos-after' : 'sos-before'),
    label: smokeFreeStrings(context, after ? 'afterRating' : 'beforeRating'),
    value: after ? _after : _before,
    optional: after,
    onChanged: (value) => _change(() {
      if (after) {
        _after = value;
      } else {
        _before = value!;
      }
    }),
  );

  Widget _wait() {
    final strings = smokeFreeStrings;
    final shown = nexDigits(
      '${(_left ~/ 60).toString().padLeft(2, '0')}:${(_left % 60).toString().padLeft(2, '0')}',
      persian: NexModuleStrings.persian(context),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NexAdaptiveSegments<int>(
          segments: [
            for (final n in [2, 5, 10])
              ButtonSegment(
                value: n,
                label: Text(strings(context, 'waitMinutes', {'n': n})),
              ),
          ],
          selected: {_minutes},
          onSelectionChanged: (value) => _change(() {
            _timer?.cancel();
            _deadline = null;
            _minutes = value.first;
            _left = _minutes * 60;
          }),
        ),
        const SizedBox(height: NexSpacing.md),
        Text(
          _deadline == null
              ? strings(context, 'waitHint')
              : _left == 0
              ? strings(context, 'waitDone')
              : strings(context, 'waitLeft', {'time': shown}),
          key: ValueKey(
            _deadline != null && _left == 0 ? 'sos-wait-done' : 'sos-wait-left',
          ),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        if (_deadline != null) ...[
          const SizedBox(height: NexSpacing.md),
          LinearProgressIndicator(value: 1 - _left / (_minutes * 60)),
        ],
        const SizedBox(height: NexSpacing.md),
        FilledButton(
          key: const ValueKey('sos-wait-start'),
          onPressed: _start,
          child: Text(
            _deadline == null
                ? strings(context, 'waitBegin')
                : strings(context, 'waitReset'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = smokeFreeStrings;
    final plan = widget.attempt.nextStep.trim();
    final why = widget.attempt.why.trim();
    return DraftGuard(
      draft: _draft,
      busy: () => _loading || _leaving,
      child: _failed
          ? NexEmptyState(
              icon: Icons.refresh,
              message: strings(context, 'draftReadFailed'),
              action: TextButton(
                onPressed: () {
                  setState(() => _loading = true);
                  unawaited(_load());
                },
                child: Text(strings(context, 'retry')),
              ),
            )
          : AbsorbPointer(
              absorbing: _loading || _leaving,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(NexSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      strings(context, 'sosTitle'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: NexSpacing.xs),
                    Text(strings(context, 'sosIntro')),
                    if (why.isNotEmpty || plan.isNotEmpty) ...[
                      const SizedBox(height: NexSpacing.md),
                      NexPanel(
                        key: const ValueKey('sos-why'),
                        icon: Icons.favorite_border,
                        title: strings(
                          context,
                          plan.isNotEmpty ? 'planTitle' : 'remember',
                        ),
                        child: NexTextDirection(
                          text: plan.isNotEmpty ? plan : why,
                          child: Text(plan.isNotEmpty ? plan : why),
                        ),
                      ),
                    ],
                    const SizedBox(height: NexSpacing.md),
                    _ratings(after: false),
                    const SizedBox(height: NexSpacing.md),
                    NexAdaptiveSegments<_Mode>(
                      key: const ValueKey('sos-modes'),
                      segments: [
                        for (final pair in [
                          (_Mode.breathe, 'tabBreathe'),
                          (_Mode.wait, 'tabWait'),
                          (_Mode.distract, 'tabDistract'),
                        ])
                          ButtonSegment(
                            value: pair.$1,
                            label: Text(strings(context, pair.$2)),
                          ),
                      ],
                      selected: {_mode},
                      onSelectionChanged: (value) =>
                          _change(() => _mode = value.first),
                    ),
                    const SizedBox(height: NexSpacing.md),
                    switch (_mode) {
                      _Mode.breathe => const SosBreathing(),
                      _Mode.wait => _wait(),
                      _Mode.distract => const _Tips(),
                    },
                    const SizedBox(height: NexSpacing.md),
                    _ratings(after: true),
                    const SizedBox(height: NexSpacing.md),
                    TextButton.icon(
                      key: const ValueKey('sos-log'),
                      icon: const Icon(Icons.edit_note_outlined),
                      label: Text(strings(context, 'logIt')),
                      onPressed: _record,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _Tips extends StatelessWidget {
  const _Tips();
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final (i, icon) in const [
        Icons.water_drop_outlined,
        Icons.directions_walk,
        Icons.chat_bubble_outline,
        Icons.face_outlined,
        Icons.back_hand_outlined,
      ].indexed)
        ListTile(
          leading: Icon(icon),
          title: Text(smokeFreeStrings(context, 'tip${i + 1}')),
        ),
    ],
  );
}
