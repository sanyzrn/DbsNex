import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The one "add" action of a module page: the floating button once there is
/// something on the page, the empty state's own button before that.
Finder addButton(String fab, String empty) => find.byWidgetPredicate(
  (w) => w.key == ValueKey(fab) || w.key == ValueKey(empty),
  description: 'the add action ($fab or $empty)',
);
