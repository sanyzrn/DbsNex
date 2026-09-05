import 'dart:convert';
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

/// The same hash, for a file that will not fit in memory.
///
/// Read in chunks rather than with `readAsBytes`. A note's attachment is
/// whatever the person shared into the app, and a two-gigabyte video is an
/// ordinary thing to share: reading one to hash it needs two gigabytes of
/// heap that a phone does not have, and the process dies. That is not
/// hypothetical — it was reported, and the app fell over on launch trying to
/// finish the share.
///
/// Asynchronous for the same reason. There is no way to stream a file without
/// awaiting it, and the synchronous version could only ever have been the
/// whole-file read this exists to avoid.
Future<String?> sha256OfFile(String? path) async {
  if (path == null) return null;
  final file = File(path);
  if (!file.existsSync()) return null;
  // `dart:convert`'s own sink rather than `package:convert`'s
  // `AccumulatorSink`, which would be a new dependency in the one package
  // that is not allowed them.
  Digest? result;
  final input = sha256.startChunkedConversion(
    ChunkedConversionSink<Digest>.withCallback((digests) {
      result = digests.single;
    }),
  );
  // `openRead` hands over whatever the platform read — typically 64 KiB — so
  // the peak is a rounding error whatever the file weighs.
  await for (final chunk in file.openRead()) {
    input.add(chunk);
  }
  input.close();
  return result?.toString();
}
