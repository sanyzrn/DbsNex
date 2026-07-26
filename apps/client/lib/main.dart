import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'bootstrap_host.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AIAdapterBinding.bind(const OnDeviceAIAdapter());
  runApp(const NexBootstrapHost());
}