import 'package:flutter/widgets.dart' show runApp;
import 'package:nex_core/nex_core.dart';

import 'bootstrap_host.dart';
import 'entry_bootstrap.dart';

Future<void> main() async {
  await bootstrapEntry();
  AIAdapterBinding.bind(const OnDeviceAIAdapter());
  runApp(const NexBootstrapHost());
}
