import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/install_source.dart';

/// Cafe Bazaar's rules: an app downloaded from Bazaar is updated only
/// through Bazaar (REL-01). Which installer counts as which store.
void main() {
  test('the two stores are recognised by their installer package', () {
    expect(
      NexInstallSource.fromInstaller('com.farsitel.bazaar'),
      NexStore.bazaar,
    );
    expect(
      NexInstallSource.fromInstaller('ir.mservices.market'),
      NexStore.myket,
    );
  });

  test('any other source keeps the in-app updater', () {
    for (final installer in [
      null,
      'com.android.packageinstaller',
      'com.google.android.packageinstaller',
      'org.telegram.messenger',
    ]) {
      expect(NexInstallSource.fromInstaller(installer), isNull);
    }
  });
}
