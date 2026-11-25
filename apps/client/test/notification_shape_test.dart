import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/notification_text.dart';
import 'package:nex_client/platform/reminders.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stands in for the plugin and keeps exactly what it was handed — the only
/// way to see the words and the style a reminder really produces.
class _FakePlugin implements FlutterLocalNotificationsPlugin {
  final scheduled = <Map<Symbol, dynamic>>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    switch (invocation.memberName) {
      case #initialize:
        return Future<bool?>.value(true);
      case #zonedSchedule:
        scheduled.add(Map.of(invocation.namedArguments));
        return Future<void>.value();
      case #pendingNotificationRequests:
        return Future<List<PendingNotificationRequest>>.value([
          for (final request in scheduled)
            PendingNotificationRequest(request[#id] as int, null, null, null),
        ]);
      case #getNotificationAppLaunchDetails:
        return Future<NotificationAppLaunchDetails?>.value();
      case #resolvePlatformSpecificImplementation:
        return null;
      case #cancel:
        return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }

  Map<Symbol, dynamic> get last => scheduled.last;
}

/// The words and the shape every system notification is built from, in one
/// place — the audit behind 2.9.0's notification pass.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('words', () {
    test('a body that only repeats the title is dropped', () {
      final words = nexNotificationWords('Walk', '  Walk \n');
      expect(words.title, 'Walk');
      expect(words.body, isNull);
    });

    test('blank edges go, and doubled blank lines fold into one', () {
      final words = nexNotificationWords(
        '  Medicine  ',
        '\n\nOne tablet\n\n\n\n09:00\n\n',
      );
      expect(words.title, 'Medicine');
      expect(words.body, 'One tablet\n\n09:00');
    });

    test('an empty or whitespace body is no body at all', () {
      expect(nexNotificationWords('Nex', '').body, isNull);
      expect(nexNotificationWords('Nex', '   \n\t').body, isNull);
      expect(nexNotificationWords('Nex', null).body, isNull);
    });

    test('a differing body is kept whole', () {
      final words = nexNotificationWords('Walk', 'Fifteen minutes');
      expect(words.body, 'Fifteen minutes');
    });
  });

  group('expanded text', () {
    test('blank edges are not drawn as blank lines', () {
      final html = nexAndroidNotificationText('One tablet\n\n', phone: null);
      expect(html, isNot(endsWith('<br>')));
      expect(html.trim(), '\u200eOne tablet');
    });

    test('markup is escaped once, not twice', () {
      final html = nexAndroidNotificationText('<b> & ', phone: null);
      expect(html, '\u200e&lt;b&gt; &amp;');
    });

    test('the style carries the same clean words', () {
      final style =
          nexNotificationStyle('\nMedicine\n\n') as BigTextStyleInformation;
      expect(style.bigText, '\u200eMedicine');
      expect(
        nexNotificationStyle('  \n ').runtimeType,
        DefaultStyleInformation,
      );
    });
  });

  group('what a reminder is handed', () {
    late _FakePlugin plugin;
    late NexReminders reminders;
    final at = DateTime.utc(2027, 3, 2, 22, 30);

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      NexReminders.debugSupported = true;
      plugin = _FakePlugin();
      reminders = NexReminders(plugin: plugin);
    });
    tearDown(() => NexReminders.debugSupported = null);

    test('a module reminder with a body expands to it', () async {
      await reminders.scheduleModule(
        'medicine',
        'med:1',
        at: at,
        title: 'Medicine',
        body: 'One tablet\n\n',
      );
      // The test host is not Android, so the words reach the plugin as they
      // are; the style is built directly and carries the paragraph mark.
      expect(plugin.last[#title], 'Medicine');
      expect(plugin.last[#body], 'One tablet');
      final details = plugin.last[#notificationDetails] as NotificationDetails;
      // The regression this covers: a body was passed but the style was
      // built for no body, so the expanded shade showed one cut line.
      final style = details.android!.styleInformation;
      expect(style, isA<BigTextStyleInformation>());
      expect((style as BigTextStyleInformation).bigText, '\u200eOne tablet');
    });

    test(
      'a module reminder saying the same thing twice says it once',
      () async {
        await reminders.scheduleModule(
          'habits',
          'habit:walk',
          at: at,
          title: 'Walk',
          body: 'Walk',
        );
        expect(plugin.last[#body], isNull);
        final details =
            plugin.last[#notificationDetails] as NotificationDetails;
        expect(
          details.android!.styleInformation,
          isA<DefaultStyleInformation>(),
        );
      },
    );
  });

  group('habit buttons', () {
    List<AndroidNotificationAction> actions({
      required bool counted,
      required NexChannelText text,
    }) => NexHabitNotificationActions.details(
      body: 'Walk',
      counted: counted,
      secret: false,
      text: text,
    ).android!.actions!;

    test('in English, in the words the rest of the shade uses', () {
      final plain = actions(counted: false, text: NexChannelText.en);
      expect(plain.first.title, 'Done');
      expect(plain.last.title, 'Remind later');
      expect(
        actions(counted: true, text: NexChannelText.en).first.title,
        'Log progress',
      );
    });

    test('in Persian, from the same place as Done and In an hour', () {
      final plain = actions(counted: false, text: NexChannelText.fa);
      expect(plain.first.title, 'انجام شد');
      expect(plain.last.title, 'بعداً یادآوری کن');
      expect(
        actions(counted: true, text: NexChannelText.fa).first.title,
        'ثبت پیشرفت',
      );
    });
  });
}
