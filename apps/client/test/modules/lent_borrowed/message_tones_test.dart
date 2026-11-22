import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/lent_borrowed/irr_unit.dart';
import 'package:nex_client/modules/lent_borrowed/loan_math.dart';
import 'package:nex_client/modules/lent_borrowed/loan_message.dart';
import 'package:nex_client/modules/lent_borrowed/loan_model.dart';
import 'package:nex_client/modules/module_api.dart';

import '../../support/nex_harness.dart';

/// The reminder message: short, polite, and in three tones — never a demand.
/// It offers the other person the timing, and it says nothing the app does
/// not know.
void main() {
  late NexTestHarness harness;

  setUp(
    () async => harness = await NexTestHarness.create(name: 'nex_lent_msg_'),
  );
  tearDown(() => harness.dispose());

  Loan loan({
    LoanKind kind = LoanKind.money,
    String? due = '2026-10-15',
    String person = 'Sara',
    String what = 'Blue backpack',
    // An item's amount is its count, not a sum of money.
    int amount = 500000,
  }) => Loan(
    id: 'l1',
    direction: LoanDirection.lent,
    person: person,
    kind: kind,
    amount: amount,
    what: kind == LoanKind.item ? what : '',
    issued: '2026-10-01',
    due: due,
    note: '',
  );

  Future<BuildContext> pumpHost(WidgetTester tester, Locale locale) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return captured;
  }

  Future<String> message(
    WidgetTester tester,
    Locale locale,
    MessageTone tone, {
    Loan? record,
  }) async {
    final context = await pumpHost(tester, locale);
    final l = record ?? loan();
    return loanMessage(
      context,
      l,
      LoanMath.standing(l, const [], today: DateTime(2026, 10, 10)),
      IrrUnit.toman,
      tone,
    );
  }

  testWidgets('English: friendly, neutral and formal, each its own voice', (
    tester,
  ) async {
    final friendly = await message(
      tester,
      const Locale('en'),
      MessageTone.friendly,
    );
    expect(friendly, startsWith('Hi Sara!'));
    expect(friendly, contains('50,000 tomans'));
    expect(friendly, contains('whenever it suits you'));
    expect(friendly, contains(', due '));

    final neutral = await message(
      tester,
      const Locale('en'),
      MessageTone.neutral,
    );
    expect(neutral, contains('A gentle reminder'));
    expect(neutral, contains('No rush'));

    final formal = await message(
      tester,
      const Locale('en'),
      MessageTone.formal,
    );
    expect(formal, startsWith('Dear Sara,'));
    expect(formal, contains('May I ask'));
  });

  testWidgets('Persian: warm, unhurried, and it asks for their timing', (
    tester,
  ) async {
    final friendly = await message(
      tester,
      const Locale('fa'),
      MessageTone.friendly,
      record: loan(person: 'سارا'),
    );
    expect(friendly, contains('سلام سارا جان'));
    expect(friendly, contains('۵۰٬۰۰۰ تومان'));
    expect(friendly, contains('هر وقت راحت بودی'));
    expect(friendly, contains('چه زمانی برات مناسبه'));

    final neutral = await message(
      tester,
      const Locale('fa'),
      MessageTone.neutral,
      record: loan(person: 'سارا'),
    );
    expect(neutral, contains('یادآوری آرام'));
    expect(neutral, contains('عجله‌ای نیست'));

    final formal = await message(
      tester,
      const Locale('fa'),
      MessageTone.formal,
      record: loan(person: 'سارا'),
    );
    expect(formal, startsWith('سارا عزیز'));
    expect(formal, contains('شرمنده‌ام'));
  });

  testWidgets('a message never pushes: no demand, no accusation', (
    tester,
  ) async {
    for (final locale in [const Locale('en'), const Locale('fa')]) {
      for (final tone in MessageTone.values) {
        final text = await message(tester, locale, tone);
        for (final harsh in [
          'must',
          'immediately',
          'owe you',
          'باید',
          'فوراً',
          'حتماً',
        ]) {
          expect(
            text.toLowerCase(),
            isNot(contains(harsh)),
            reason: '$locale $tone should stay kind',
          );
        }
      }
    }
  });

  testWidgets('an item is a thing, not a currency and not a count', (
    tester,
  ) async {
    final english = await message(
      tester,
      const Locale('en'),
      MessageTone.friendly,
      record: loan(kind: LoanKind.item, amount: 2),
    );
    // How many is part of what is owed: «2 × Blue backpack». The count used
    // to be dropped from the sentence, so two things read as one.
    expect(english, contains('2 × Blue backpack'));
    expect(english, isNot(contains('toman')));

    final persian = await message(
      tester,
      const Locale('fa'),
      MessageTone.friendly,
      record: loan(kind: LoanKind.item, what: 'کوله‌پشتی آبی', amount: 2),
    );
    expect(persian, contains('کوله‌پشتی'));
    expect(persian, contains('۲ عدد'));
  });

  testWidgets('no due date means no date is claimed', (tester) async {
    final text = await message(
      tester,
      const Locale('en'),
      MessageTone.friendly,
      record: loan(due: null),
    );
    expect(text, isNot(contains('due ')));
  });
}
