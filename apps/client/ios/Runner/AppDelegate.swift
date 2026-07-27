import Flutter
import UIKit

// FlutterImplicitEngineDelegate and FlutterImplicitEngineBridge do not exist in
// the Flutter this repository targets: .fvmrc pins 3.35.5, pubspec.yaml requires
// >=3.35.0, and every Dart package declares sdk ^3.9.0 — the Dart that ships
// with Flutter 3.35.x. They were written against a newer SDK and only compiled
// while CI floated to whatever `stable` happened to be that day. Pinning the
// SDK is what surfaced it.
@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
