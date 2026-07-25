import 'package:flutter/material.dart';

import 'app.dart';
import 'platform/nex_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await NexServices.bootstrap();
  runApp(NexApp(services: services));
}
