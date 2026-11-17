import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'studio_home.dart';
import 'studio_strings.dart';

class PromptStudioModule extends NexStoredModule {
  const PromptStudioModule();
  @override
  String get id => 'prompt_studio';
  @override
  IconData get icon => Icons.auto_fix_high_outlined;
  @override
  NexHue get hue => NexHue.violet;
  @override
  NexModuleStrings get strings => studioStrings;
  @override
  Widget screen(NexModuleStore store) => StudioHome(store: store);
}
