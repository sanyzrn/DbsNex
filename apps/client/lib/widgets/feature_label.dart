import 'package:flutter/widgets.dart';

/// Bilingual labels for the self-contained tools and recurring surfaces.
String nexLabel(BuildContext context, String en, String fa) =>
    Localizations.localeOf(context).languageCode == 'fa' ? fa : en;
