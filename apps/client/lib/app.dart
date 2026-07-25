import 'package:flutter/material.dart';

/// The Nex application shell.
///
/// Phase 0: an intentionally **empty screen**. No Timeline, no capture action,
/// no search, no settings — those arrive in Phase 1 under `lib/screens/`.
///
/// The only styling applied is the `bg-primary` token pair from
/// `05-design.md` (Light `#FFFFFF` / Dark `#0A0A0A`), so that the empty screen
/// is verifiably rendering the app's own surface rather than a framework
/// default. The full token set (including Comfort Mode) ships in Phase 1.7.
class NexApp extends StatelessWidget {
  const NexApp({super.key});

  static const Color _bgPrimaryLight = Color(0xFFFFFFFF);
  static const Color _bgPrimaryDark = Color(0xFF0A0A0A);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nex',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: _bgPrimaryLight,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _bgPrimaryDark,
      ),
      home: const Scaffold(body: SizedBox.expand()),
    );
  }
}
