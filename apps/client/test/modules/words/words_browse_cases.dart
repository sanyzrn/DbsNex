part of 'words_widget_test.dart';

void _registerBrowseCases(
  NexTestHarness Function() getHarness,
  Widget Function(Widget, {Locale locale}) host,
  Widget Function() wordsScreen,
  Finder Function() scrollable,
  Future<void> Function(WidgetTester, Key, String) enterAt,
) {
  testWidgets('search and the status filters find what is there', (
    tester,
  ) async {
    final store = NexModuleStore(getHarness().services, 'words');
    Future<void> add(String id, String word, String meaning, String due) =>
        store.put('card', id, {
          'schema': 1,
          'headword': word,
          'language': 'English',
          'meaning': meaning,
          'createdAt': '2026-10-01T10:00:00',
          'due': due,
          'lastReview': due.isEmpty ? '' : '2026-10-01T09:00:00',
          'log': due.isEmpty
              ? []
              : [
                  {'at': '2026-10-01T09:00:00', 'g': 'good'},
                ],
        });
    await add('a', 'zephyr', 'a soft west wind', '2026-12-01');
    await add('b', 'harbor', 'a safe port', ''); // new
    await add('c', 'lantern', 'a light to carry', '2026-10-01'); // overdue
    await add('d', 'pausable', 'can be paused', '2026-11-01');
    await store.put('card', 'd2', {
      'schema': 1,
      'headword': 'rest',
      'language': 'English',
      'createdAt': '2026-10-01T10:00:00',
      'due': '2026-11-01',
      'paused': true,
      'lastReview': '2026-10-01T09:00:00',
      'log': [
        {'at': '2026-10-01T09:00:00', 'g': 'good'},
      ],
    });

    await tester.pumpWidget(host(WordsScreen(store: store)));
    await tester.pumpAndSettle();
    expect(find.text('1 due now · 1 new today'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('words-card-d2')),
      200,
      scrollable: scrollable(),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.pause_circle_outline), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('words-search')),
      -200,
      scrollable: scrollable(),
    );
    await tester.pumpAndSettle();

    // Search across the fields.
    await tester.enterText(find.byKey(const ValueKey('words-search')), 'port');
    await tester.pump();
    expect(find.text('harbor'), findsOneWidget);
    expect(find.text('zephyr'), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('words-search')), 'zeph');
    await tester.pump();
    expect(find.text('zephyr'), findsOneWidget);

    // The filters.
    await tester.enterText(find.byKey(const ValueKey('words-search')), '');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('words-filter-filterNew')));
    await tester.pumpAndSettle();
    expect(find.text('harbor'), findsOneWidget);
    expect(find.text('zephyr'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('words-filter-filterDue')));
    await tester.pumpAndSettle();
    expect(find.text('lantern'), findsOneWidget);
    expect(find.text('harbor'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('words-filter-filterPaused')));
    await tester.pumpAndSettle();
    expect(find.text('rest'), findsOneWidget);
    expect(find.text('lantern'), findsNothing);

    // A filter with nothing to show says so — about the filter, not the day.
    await tester.tap(find.byKey(const ValueKey('words-filter-filterLearned')));
    await tester.pumpAndSettle();
    expect(find.text('No words match these filters.'), findsOneWidget);
    expect(find.text('rest'), findsNothing);
  });

  testWidgets('Persian reads right to left with an English headword intact', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        WordsScreen(store: NexModuleStore(getHarness().services, 'words')),
        locale: const Locale('fa'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('واژه به واژه'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('واژه به واژه'))),
      TextDirection.rtl,
    );
    expect(find.byKey(const ValueKey('words-hero')), findsNothing);
    expect(
      find.text(
        'هنوز واژه‌ای نیست. اولی را اضافه کنید — یک واژه، یک عبارت، هرچه '
        'می‌خوانید.',
      ),
      findsOneWidget,
    );

    // An English headword keeps its own direction inside the Persian UI.
    await tester.tap(addButton('words-add', 'words-empty-add'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('words-field-headword')),
      'serendipity',
    );
    await tester.enterText(
      find.byKey(const ValueKey('words-field-language')),
      'English',
    );
    await enterAt(
      tester,
      const ValueKey('words-field-meaning'),
      'یافتنِ خوش‌سُرپرست',
    );
    await tester.tap(find.byKey(const ValueKey('words-card-save')));
    await tester.pumpAndSettle();

    // An English headword keeps its own left-to-right direction inside
    // the right-to-left interface — that is the point of the surface.
    final headwordDirection = Directionality.of(
      tester.element(find.text('serendipity')),
    );
    expect(headwordDirection, TextDirection.ltr);
    final row = tester.widget<NexTextSurface>(
      find.byType(NexTextSurface).first,
    );
    expect(row.text, 'serendipity');
    expect(find.text('یافتنِ خوش‌سُرپرست'), findsOneWidget);
  });

  testWidgets('dark, small and twice the size still works', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: ThemeData(brightness: Brightness.dark),
        darkTheme: ThemeData(brightness: Brightness.dark),
        themeMode: ThemeMode.dark,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => child == null
            ? const SizedBox()
            : Builder(
                builder: (inner) => MediaQuery(
                  data: MediaQuery.of(
                    inner,
                  ).copyWith(textScaler: TextScaler.linear(2.0)),
                  child: child,
                ),
              ),
        home: WordsScreen(
          store: NexModuleStore(getHarness().services, 'words'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // At twice the size the empty state's button sits below the fold of a
    // scrolling page; it is reached by scrolling, not lost.
    await tester.dragUntilVisible(
      addButton('words-add', 'words-empty-add'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    expect(addButton('words-add', 'words-empty-add'), findsOneWidget);
  });

  testWidgets('nothing leaks in from other modules', (tester) async {
    await storeWord(
      getHarness(),
      module: 'gold',
      kind: 'quote',
      body: {'title': 'Wedding ring'},
    );
    await storeWord(
      getHarness(),
      module: 'other',
      kind: 'card',
      body: {'headword': 'not mine'},
    );

    await tester.pumpWidget(wordsScreen());
    await tester.pumpAndSettle();
    expect(find.text('not mine'), findsNothing);
    expect(await getHarness().services.moduleRecords('words', 'card'), isEmpty);
    expect(
      await getHarness().services.moduleRecords('gold', 'quote'),
      hasLength(1),
    );
  });

  testWidgets('storage reload: a reopen finds everything where it was', (
    tester,
  ) async {
    final store = NexModuleStore(getHarness().services, 'words');
    await store.put('card', 'c1', {
      'schema': 1,
      'headword': 'zephyr',
      'language': 'English',
      'createdAt': '2026-10-01T10:00:00',
    });
    await store.put('card', 'c2', {
      'schema': 1,
      'headword': 'lantern',
      'language': 'English',
      'createdAt': '2026-10-02T10:00:00',
    });
    await store.put('settings', 'settings', {'schema': 1, 'newPerDay': 5});

    // First open.
    await tester.pumpWidget(host(WordsScreen(store: store)));
    await tester.pumpAndSettle();
    expect(find.text('zephyr'), findsOneWidget);
    expect(find.text('lantern'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('words-review-settings')));
    await tester.pumpAndSettle();
    expect(find.text('5 a day'), findsOneWidget);

    // Reopen: a fresh screen over the same store.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(host(WordsScreen(store: store)));
    await tester.pumpAndSettle();
    expect(find.text('zephyr'), findsOneWidget);
    expect(find.text('lantern'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('words-review-settings')));
    await tester.pumpAndSettle();
    expect(find.text('5 a day'), findsOneWidget);
    expect(find.text('0 due now · 2 new today'), findsOneWidget);
  });
}
