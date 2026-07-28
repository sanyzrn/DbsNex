import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Identity and content-hash helpers.
///
/// These lived in packages/data next to the SQLite repository, which forced
/// packages/core to import the storage layer just to mint an id. They depend on
/// nothing but `uuid` and `crypto`, both already core dependencies.

/// Time-ordered id. v7 keeps the timeline's primary key monotonic, so inserts
/// land at the end of the B-tree instead of scattering across it.
String newUuidV7() => _uuid.v7();

/// A name-derived id, identical on every device for the same name.
///
/// The starter tags are created independently on each device. With random ids
/// two devices' "Work" are two different tags, and syncing them yields a
/// duplicate the user never made. A v5 UUID is a hash of the name, so both
/// devices arrive at the same id and the rows merge instead of piling up.
String stableUuidV5(String name) =>
    _uuid.v5(Namespace.url.value, 'nex:tag:${name.toLowerCase()}');

String sha256OfBytes(Uint8List bytes) => sha256.convert(bytes).toString();

String? sha256OfFile(String? path) {
  if (path == null) return null;
  final file = File(path);
  if (!file.existsSync()) return null;
  return sha256OfBytes(file.readAsBytesSync());
}
