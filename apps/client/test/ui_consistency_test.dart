import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The register behind `docs/26-ui-consistency.md`.
///
/// The app is being brought to one look — one set of corners, cards, menus,
/// pickers, banners, buttons — a family at a time. Each line below counts the
/// ways of doing a thing that the shared component replaces, with the number
/// that existed when the family was registered. The count may only go down:
/// fix one and lower its number here (the failure says so), and a new one in
/// the old way fails the build instead of becoming the next thing to fix.
///
/// A family reaching 0 is finished: it then stays at 0 for good.
void main() {
  final files = [
    for (final f in Directory('lib').listSync(recursive: true))
      if (f is File &&
          f.path.endsWith('.dart') &&
          !f.path.replaceAll(r'\', '/').startsWith('lib/l10n/'))
        (f.path.replaceAll(r'\', '/'), f.readAsStringSync()),
  ];

  int count(RegExp pattern, {Set<String> except = const {}}) => [
    for (final (path, text) in files)
      if (!except.contains(path)) ...pattern.allMatches(text),
  ].length;

  void ratchet(String family, int now, int baseline, String use) {
    expect(
      now,
      lessThanOrEqualTo(baseline),
      reason:
          '$family: $now now, $baseline allowed. $use '
          '(docs/26-ui-consistency.md)',
    );
    if (now < baseline) {
      fail(
        '$family went down to $now — lower its baseline from $baseline to '
        '$now in test/ui_consistency_test.dart so it cannot creep back.',
      );
    }
  }

  test('corner radii come from NexRadius', () {
    // What is left are 2–3 px bars and dots (a handle, a progress track):
    // shapes rather than the corners of a component.
    ratchet(
      'a number in BorderRadius.circular / Radius.circular',
      count(RegExp(r'(?<![A-Za-z])(Border)?Radius\.circular\(\s*[0-9]')),
      8,
      'Use NexRadius.xs/sm/md/lg/xl.',
    );
  });

  test('times and dates are asked with the shared pickers', () {
    ratchet(
      'a raw showTimePicker / showDatePicker',
      // The dialogs themselves too: Expenses built a TimePickerDialog by
      // hand, which this did not see until 2.6.27.
      count(
        RegExp(r'\b(show(Time|Date)Picker|(Time|Date)PickerDialog)\s*\('),
        except: {'lib/widgets/nex_time_picker.dart'},
      ),
      0,
      'Use nexPickTime / nexPickDate (Jalali-aware, platform text scale).',
    );
  });

  test('dialogs are NexAlertDialog through nexShowDialog', () {
    ratchet(
      'a stock SimpleDialog( / AlertDialog(',
      count(RegExp(r'(?<![A-Za-z_])(SimpleDialog|AlertDialog)\s*\(')),
      0,
      'Use NexAlertDialog (with NexDialogBody for a list of choices).',
    );
  });

  test('text fields take their outline from the theme', () {
    // Material's own OutlineInputBorder() — a 4 px corner in the default
    // grey — was passed in 33 places just to get an outline, and became what
    // every one of those fields drew when disabled (2.6.27).
    ratchet(
      'a default OutlineInputBorder()',
      count(RegExp(r'OutlineInputBorder\(\s*\)')),
      0,
      'Leave border unset: the theme draws resting, focus, error and disabled.',
    );
  });

  test('menus are nexMenuItem (also enforced in menu_rule_test.dart)', () {
    ratchet(
      'a stock PopupMenuButton / PopupMenuItem / showMenu',
      count(
        RegExp(
          r'(?<![A-Za-z_.])(PopupMenuButton|PopupMenuItem|showMenu)\s*[<(]',
        ),
      ),
      0,
      'Use NexPopupMenuButton and nexMenuItem.',
    );
  });

  test('messages always use the top capsule', () {
    // The banner (nexShowBanner) is the app's one message surface; a SnackBar
    // is the Material one, at the bottom, over the bottom bar. Move them a
    // screen at a time.
    ratchet(
      'a SnackBar(',
      count(RegExp(r'\bSnackBar\(|\.showSnackBar\s*\(')),
      0,
      'Use nexShowBanner.',
    );
  });

  test('buttons and cards: stock Material ones still to review', () {
    ratchet(
      'an OutlinedButton( / ElevatedButton(',
      count(RegExp(r'\b(OutlinedButton|ElevatedButton)\(')),
      5,
      'Use FilledButton / FilledButton.tonal / TextButton per the design language.',
    );
    ratchet(
      'a Card(',
      count(RegExp(r'\bCard\(')),
      3,
      'Use NexPanel or the shelf widgets (tokens for corners, surface, padding).',
    );
  });
}
