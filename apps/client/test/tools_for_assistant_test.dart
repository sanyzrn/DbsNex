import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations_en.dart';
import 'package:nex_client/modules/module_shared.dart';
import 'package:nex_client/modules/parking/parking_models.dart';
import 'package:nex_client/modules/nex_module_store.dart';
import 'package:nex_client/platform/tools_for_assistant.dart';

import 'support/nex_harness.dart';

/// 2.8.5: what the assistant is told about the tools — only when allowed,
/// and never a money or health detail.
void main() {
  final now = DateTime(2026, 11, 18, 10);

  ModuleDue due(
    String id,
    String title,
    DateTime at, {
    bool private = false,
    bool done = false,
    String kind = 'due',
  }) => ModuleDue(
    id: id,
    recordKind: 'r',
    recordId: id,
    at: at,
    title: title,
    kind: kind,
    private: private,
    done: done,
  );

  test('money and health tools are a count, the rest by name', () {
    final text = nexToolsContext([
      NexToolReport(
        id: 'cheques',
        title: 'Cheques',
        glance: const ModuleGlance(headline: '3 cheques · 12,000,000 toman'),
        dues: [
          due('a', 'Rent cheque to Ali', DateTime(2026, 11, 20), private: true),
          due('b', 'Car loan', DateTime(2026, 11, 25), private: true),
        ],
      ),
      NexToolReport(
        id: 'medicine',
        title: 'Medicine',
        glance: const ModuleGlance(headline: 'Metformin at 20:00'),
      ),
      NexToolReport(
        id: 'warranty',
        title: 'Warranties',
        glance: const ModuleGlance(
          headline: '2 covered',
          detail: 'TV ends soon',
        ),
        dues: [
          due('t', 'TV', DateTime(2026, 11, 16), kind: 'coverage-end'),
          due('x', 'Old', DateTime(2026, 11, 19), done: true),
        ],
        dueLabel: (kind) => kind == 'coverage-end' ? 'coverage ends' : null,
      ),
    ], now);
    expect(text, contains('Cheques: 2 item(s) due, earliest 2026-11-20'));
    expect(text, isNot(contains('Ali')));
    expect(text, isNot(contains('12,000,000')));
    // Nothing coming up: not even named.
    expect(text, isNot(contains('Medicine')));
    expect(text, isNot(contains('Metformin')));
    expect(
      text,
      contains(
        '- Warranties: 2 covered — TV ends soon; coming up: '
        'TV (coverage ends) 2026-11-16 (overdue)',
      ),
    );
    expect(text, isNot(contains('Old')));
  });

  test('a private date in any tool stays a count', () {
    final text = nexToolsContext([
      NexToolReport(
        id: 'occasions',
        title: 'Occasions',
        dues: [
          due('m', 'Father memorial', DateTime(2026, 11, 22), private: true),
          due('b', 'Sara birthday', DateTime(2026, 11, 21)),
        ],
      ),
    ], now);
    expect(text, contains('Sara birthday 2026-11-21, 1 private item(s)'));
    expect(text, isNot(contains('memorial')));
  });

  test('nothing to say is nothing sent; a long list is cut', () {
    expect(nexToolsContext(const [], now), isEmpty);
    final long = nexToolsContext(
      [
        for (var i = 0; i < 40; i++)
          NexToolReport(
            id: 'words',
            title: 'Tool $i',
            glance: ModuleGlance(headline: 'headline number $i ' * 3),
          ),
      ],
      now,
      budget: 600,
    );
    expect(long.length, lessThan(700));
    expect(long, endsWith('- (more tools not listed)'));
  });

  group('from the tools that are on', () {
    late NexTestHarness h;
    setUp(() async => h = await NexTestHarness.create(name: 'ai_tools_'));
    tearDown(() => h.dispose());

    test('off by default: nothing at all', () async {
      expect(h.preferences.aiUseTools, isFalse);
      final text = await nexToolsForAssistant(
        services: h.services,
        preferences: h.preferences,
        l10n: AppLocalizationsEn(),
        now: now,
      );
      expect(text, isEmpty);
    });

    test('on: a parked car is in what it reads', () async {
      await h.preferences.setAiUseTools(true);
      await h.preferences.setModuleOn('parking', true);
      await NexModuleStore(h.services, 'parking').put(
        ParkingModels.session,
        's1',
        ParkingModels.sessionBody(
          vehicle: 'Pride',
          place: 'Tirajeh mall',
          floor: '-2',
          spot: 'B14',
          landmark: '',
          startedAt: now.subtract(const Duration(minutes: 40)),
          expiresAt: now.add(const Duration(minutes: 80)),
        ),
      );
      final text = await nexToolsForAssistant(
        services: h.services,
        preferences: h.preferences,
        l10n: AppLocalizationsEn(),
        now: now,
      );
      expect(text, contains('Tirajeh mall · -2 · B14'));
    });
  });
}
