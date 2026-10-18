import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/entry_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.linux,
  ]) {
    testWidgets(
      'portrait request on $platform',
      (tester) async {
        final calls = <MethodCall>[];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          calls.add(call);
          return null;
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );
        await lockNexPhoneOrientation();
        final orientation = calls.where(
          (call) => call.method == 'SystemChrome.setPreferredOrientations',
        );
        if (platform == TargetPlatform.linux) {
          expect(orientation, isEmpty);
        } else {
          expect(orientation.single.arguments, [
            'DeviceOrientation.portraitUp',
          ]);
        }
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }
}
