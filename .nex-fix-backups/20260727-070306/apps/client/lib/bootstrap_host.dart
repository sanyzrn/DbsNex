import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';
import 'app.dart';
import 'platform/nex_preferences.dart';
import 'platform/nex_services.dart';
import 'platform/os_capture_bridge.dart';
import 'restart_scope.dart';

class NexBootstrapHost extends StatefulWidget {
  const NexBootstrapHost({super.key});
  @override
  State<NexBootstrapHost> createState() => _NexBootstrapHostState();
}

class _NexBootstrapHostState extends State<NexBootstrapHost> {
  late Future<_Ready> _future = _start();
  _Ready? _ready;

  Future<_Ready> _start() async {
    final preferences = await NexPreferences.load();
    final services = await NexServices.bootstrap(preferences: preferences);
    services.applyAiPreferences(preferences);
    final bridge = OsCaptureBridge(services);
    await bridge.start();
    return _ready = _Ready(preferences, services, bridge);
  }

  void _restart() {
    _ready?.bridge.dispose();
    _ready?.services.dispose();
    _ready = null;
    setState(() => _future = _start());
  }

  @override
  void dispose() {
    _ready?.bridge.dispose();
    _ready?.services.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_Ready>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            final value = snapshot.requireData;
            return NexRestartScope(
              restart: _restart,
              child: NexApp(
                services: value.services,
                preferences: value.preferences,
                osCapture: value.bridge,
              ),
            );
          }
          if (snapshot.hasError) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: nexLightTheme(),
              darkTheme: nexDarkTheme(),
              home: Scaffold(
                body: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Nex', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 16),
                          const Text('Nex could not open your local library. Your files were not changed.'),
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: () => setState(() => _future = _start()),
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: nexLightTheme(),
            darkTheme: nexDarkTheme(),
            home: const Scaffold(
              body: Center(
                child: Semantics(
                  label: 'Nex is opening',
                  child: Text('Nex', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          );
        },
      );
}

class _Ready {
  const _Ready(this.preferences, this.services, this.bridge);
  final NexPreferences preferences;
  final NexServices services;
  final OsCaptureBridge bridge;
}