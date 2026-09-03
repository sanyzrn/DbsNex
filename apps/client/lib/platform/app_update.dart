import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

/// A semantic version, comparable.
///
/// String comparison is not an option: "0.10.0".compareTo("0.9.0") is negative,
/// so a tenth minor release would look older than the ninth and the update
/// would never be offered.
@immutable
class NexVersion implements Comparable<NexVersion> {
  const NexVersion(this.major, this.minor, this.patch, {this.preRelease});

  final int major;
  final int minor;
  final int patch;

  /// The `-beta.1` part, or null for a final release.
  final String? preRelease;

  static final _pattern = RegExp(
    r'^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z.-]+))?$',
  );

  /// Returns null rather than throwing: the input is a tag from a remote
  /// server, so anything at all can arrive, and an unparseable tag means
  /// "no update", not "crash".
  ///
  /// `int.tryParse`, not `int.parse`, and that is the whole of the guarantee
  /// above rather than a preference. The pattern's `\d*` matches a digit run
  /// of any length, so a tag like `v99999999999999999999.0.0` — twenty digits,
  /// past what a 64-bit int holds — satisfied the regex and then threw a
  /// `FormatException` out of a method whose contract is that it never
  /// throws. One mistyped tag on one release would have broken the update
  /// check for everyone until it was renamed.
  static NexVersion? tryParse(String value) {
    final match = _pattern.firstMatch(value.trim());
    if (match == null) return null;
    final major = int.tryParse(match.group(1)!);
    final minor = int.tryParse(match.group(2)!);
    final patch = int.tryParse(match.group(3)!);
    if (major == null || minor == null || patch == null) return null;
    return NexVersion(major, minor, patch, preRelease: match.group(4));
  }

  bool get isPreRelease => preRelease != null;

  @override
  int compareTo(NexVersion other) {
    for (final pair in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      final result = pair.$1.compareTo(pair.$2);
      if (result != 0) return result;
    }
    // Semver: a pre-release sorts *below* the release it leads to, so
    // 1.0.0-beta < 1.0.0. Two pre-releases fall back to identifier order.
    if (preRelease == null && other.preRelease == null) return 0;
    if (preRelease == null) return 1;
    if (other.preRelease == null) return -1;
    return preRelease!.compareTo(other.preRelease!);
  }

  bool operator >(NexVersion other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is NexVersion &&
      other.major == major &&
      other.minor == minor &&
      other.patch == patch &&
      other.preRelease == preRelease;

  @override
  int get hashCode => Object.hash(major, minor, patch, preRelease);

  @override
  String toString() =>
      '$major.$minor.$patch${preRelease == null ? '' : '-$preRelease'}';
}

enum UpdateStatus {
  /// The installed build is the newest published release.
  upToDate,

  /// A newer release exists and carries an asset this platform can install.
  available,

  /// The check itself did not complete — offline, rate-limited, a server
  /// error. Deliberately distinct from [upToDate]: telling someone they are
  /// current when nothing was actually checked is a lie.
  unavailable,
}

@immutable
class UpdateCheck {
  const UpdateCheck._(
    this.status, {
    this.version,
    this.downloadUrl,
    this.assetName,
    this.checksumsUrl,
    this.checksumSha256,
    this.sizeBytes,
    this.notes,
  });

  const UpdateCheck.upToDate() : this._(UpdateStatus.upToDate);

  const UpdateCheck.unavailable() : this._(UpdateStatus.unavailable);

  const UpdateCheck.available({
    required NexVersion version,
    required String downloadUrl,
    String? assetName,
    String? checksumsUrl,
    String? checksumSha256,
    int? sizeBytes,
    String? notes,
  }) : this._(
         UpdateStatus.available,
         version: version,
         downloadUrl: downloadUrl,
         assetName: assetName,
         checksumsUrl: checksumsUrl,
         checksumSha256: checksumSha256,
         sizeBytes: sizeBytes,
         notes: notes,
       );

  final UpdateStatus status;
  final NexVersion? version;
  final String? downloadUrl;

  /// The release asset's own name, e.g. `Nex-0.3.0-universal.apk` — not
  /// [downloadUrl], which is opaque, and not the local install filename from
  /// [nexInstallerFilename], which is not what `SHA256SUMS` lists it under.
  final String? assetName;

  /// The `SHA256SUMS` asset's URL, when the release published one.
  final String? checksumsUrl;

  /// [assetName]'s expected SHA-256, once fetched from [checksumsUrl] — null
  /// until then, and null forever for a release built before this existed.
  final String? checksumSha256;

  final int? sizeBytes;
  final String? notes;

  UpdateCheck _withChecksum(String hash) => UpdateCheck._(
    status,
    version: version,
    downloadUrl: downloadUrl,
    assetName: assetName,
    checksumsUrl: checksumsUrl,
    checksumSha256: hash,
    sizeBytes: sizeBytes,
    notes: notes,
  );
}

/// Which release asset a platform installs.
///
/// The names are a contract with the release workflow, which builds exactly
/// these. Android matches the running process's own ABI — `Abi.current()` is
/// the architecture Dart is actually compiled for, no device query or plugin
/// needed — to one of the per-ABI splits the workflow already builds, rather
/// than always taking the much larger universal APK. [UpdateChecker.check]
/// falls back to universal if a release is ever missing that exact split.
String? _assetNameSuffix() {
  if (Platform.isAndroid) return _androidAbiSuffix(Abi.current());
  if (Platform.isWindows) return '.exe';
  return null;
}

@visibleForTesting
String androidAbiSuffixForTest(Abi abi) => _androidAbiSuffix(abi);

String _androidAbiSuffix(Abi abi) => switch (abi) {
  Abi.androidArm64 => '-arm64-v8a.apk',
  Abi.androidArm => '-armeabi-v7a.apk',
  Abi.androidX64 => '-x86_64.apk',
  // 32-bit x86 and anything future the release workflow does not split for.
  _ => '-universal.apk',
};

/// What a downloaded installer is called on disk.
///
/// One definition, because it is a fact two places have to agree on: the
/// service names the file it fetches, and the service's own "already on disk"
/// check has to find that same name again. It was written inline in both,
/// which is exactly the shape of thing that stays right until a platform is
/// added — and the tests had a third copy that hardcoded `.apk`, so on Windows
/// they wrote a file the code would never look for and then asserted it had
/// been found.
String nexInstallerFilename(NexVersion version) =>
    'Nex-$version${Platform.isWindows ? '.exe' : '.apk'}';

/// Asks GitHub whether a newer release exists.
///
/// This is the only outbound request the app makes outside sync, it happens
/// only when the user asks for it, and it sends nothing but the request —
/// no note content, no identifier, no telemetry.
class UpdateChecker {
  UpdateChecker({
    required this.currentVersion,
    http.Client? client,
    // A separate, public repo — never the source repo, which the release
    // workflow now publishes to instead (see release.yml). GitHub's release
    // API and asset URLs both need authentication once a repo is private,
    // and shipping a token in the client to provide it would mean anyone
    // could pull it back out of the built app.
    this.repository = 'sanyzrn/DbsNex-releases',
    this.assetSuffix,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final String currentVersion;
  final String repository;

  /// Overridable so tests can exercise the asset matching without depending on
  /// the platform the test happens to run on.
  final String? assetSuffix;

  final http.Client _client;
  final bool _ownsClient;

  Uri get _latestUri =>
      Uri.parse('https://api.github.com/repos/$repository/releases/latest');

  Future<UpdateCheck> check() async {
    final installed = NexVersion.tryParse(currentVersion);
    if (installed == null) return const UpdateCheck.unavailable();
    final suffix = assetSuffix ?? _assetNameSuffix();
    if (suffix == null) return const UpdateCheck.unavailable();
    // Only the real ABI-detected suffix gets a fallback — a suffix a test
    // supplied on purpose should match exactly or not at all.
    final fallbackSuffix =
        assetSuffix == null && Platform.isAndroid && suffix != '-universal.apk'
        ? '-universal.apk'
        : null;

    try {
      final response = await _client
          .get(
            _latestUri,
            headers: const {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return const UpdateCheck.unavailable();
      final result = _parse(
        response.body,
        installed: installed,
        suffix: suffix,
        fallbackSuffix: fallbackSuffix,
      );
      if (result.status != UpdateStatus.available ||
          result.checksumsUrl == null ||
          result.assetName == null) {
        return result;
      }
      // A release built before this shipped has no SHA256SUMS asset at all —
      // that is [checksumsUrl] being null, handled above. This fetch failing
      // (offline, a flaky GitHub Pages-style CDN blip) is different: the asset
      // itself is fine, only this one extra request came back empty. Either
      // way the download proceeds unverified rather than being blocked on a
      // side channel the actual update does not depend on.
      final hash = await _fetchChecksum(
        result.checksumsUrl!,
        result.assetName!,
      );
      return hash == null ? result : result._withChecksum(hash);
    } on TimeoutException {
      return const UpdateCheck.unavailable();
    } catch (_) {
      // Offline, DNS failure, TLS failure, malformed body — all the same
      // outcome to the user, and none of them should reach the UI as a crash.
      return const UpdateCheck.unavailable();
    }
  }

  /// Looks up [assetName]'s line in the `SHA256SUMS` text file at [url].
  ///
  /// The format is `sha256sum`'s own: a hex digest, whitespace, the filename —
  /// so this reads it the same way a person running `sha256sum -c` would.
  Future<String?> _fetchChecksum(String url, String assetName) async {
    try {
      final response = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      for (final line in const LineSplitter().convert(response.body)) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length >= 2 && parts.last == assetName) {
          return parts.first.toLowerCase();
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  UpdateCheck parseForTest(
    String body, {
    required NexVersion installed,
    required String suffix,
    String? fallbackSuffix,
  }) => _parse(
    body,
    installed: installed,
    suffix: suffix,
    fallbackSuffix: fallbackSuffix,
  );

  UpdateCheck _parse(
    String body, {
    required NexVersion installed,
    required String suffix,
    String? fallbackSuffix,
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return const UpdateCheck.unavailable();
    }
    if (decoded is! Map<String, dynamic>) {
      return const UpdateCheck.unavailable();
    }

    // A draft is not published to users, and a pre-release is opt-in — neither
    // should be pushed at someone who tapped "check for update".
    if (decoded['draft'] == true || decoded['prerelease'] == true) {
      return const UpdateCheck.upToDate();
    }

    final latest = NexVersion.tryParse('${decoded['tag_name']}');
    if (latest == null) return const UpdateCheck.unavailable();
    if (latest.isPreRelease) return const UpdateCheck.upToDate();
    if (!(latest > installed)) return const UpdateCheck.upToDate();

    final assets = decoded['assets'];
    if (assets is! List) return const UpdateCheck.unavailable();
    String? matchedUrl;
    String? matchedName;
    int? matchedSize;
    // Only used if the exact suffix (an ABI split) never turns up — a
    // release built without this feature, or one where the split failed to
    // build, still has a universal APK the device can install.
    String? fallbackUrl;
    String? fallbackName;
    int? fallbackSize;
    String? checksumsUrl;
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = asset['name'];
      final url = asset['browser_download_url'];
      if (name is! String || url is! String) continue;
      if (name == 'SHA256SUMS') {
        checksumsUrl = url;
        continue;
      }
      final size = asset['size'];
      if (matchedUrl == null && name.endsWith(suffix)) {
        matchedUrl = url;
        matchedName = name;
        matchedSize = size is int ? size : null;
      } else if (fallbackSuffix != null &&
          fallbackUrl == null &&
          name.endsWith(fallbackSuffix)) {
        fallbackUrl = url;
        fallbackName = name;
        fallbackSize = size is int ? size : null;
      }
    }
    final downloadUrl = matchedUrl ?? fallbackUrl;
    // A newer release with nothing this platform can install is not an update.
    if (downloadUrl == null) return const UpdateCheck.upToDate();
    return UpdateCheck.available(
      version: latest,
      downloadUrl: downloadUrl,
      assetName: matchedUrl != null ? matchedName : fallbackName,
      checksumsUrl: checksumsUrl,
      sizeBytes: matchedUrl != null ? matchedSize : fallbackSize,
      notes: decoded['body'] is String ? decoded['body'] as String : null,
    );
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

/// Streams the installer to disk, reporting progress.
///
/// Downloads to a temporary name and renames on completion, so an interrupted
/// download can never be handed to the package installer as if it were whole.
/// Thrown when a download stops because it was asked to, not because it broke.
///
/// Carries no message and is caught rather than shown: the `.part` file is
/// intact, the bytes are banked, and the next call picks up where this left
/// off. A paused download reported as "download failed" is how someone
/// concludes the feature is broken and stops using it.
class DownloadPaused implements Exception {
  const DownloadPaused();

  @override
  String toString() => 'DownloadPaused';
}

class UpdateDownloader {
  UpdateDownloader({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  Future<File> download({
    required String url,
    required Directory into,
    required String filename,
    void Function(double? progress)? onProgress,

    /// Raw counters beside the fraction. A percentage is the wrong unit for a
    /// two-gigabyte download on a metered connection: what someone needs to
    /// decide whether to keep going is how much has arrived and how much is
    /// left, in bytes they recognise.
    void Function(int received, int? total)? onBytes,

    /// Polled once per chunk. Returning true stops the download where it is
    /// and throws [DownloadPaused] — the `.part` file stays on disk, so a
    /// later call resumes by range rather than starting over. Distinct from a
    /// failure on purpose: pausing is something the user asked for, and must
    /// not be reported to them as an error.
    bool Function()? isCancelled,
    // Null for a release published before SHA256SUMS existed, or when
    // fetching it failed — see UpdateChecker._fetchChecksum. Verification is
    // best-effort on top of the length check just below, not a replacement
    // for it: an installer that is the right size but the wrong bytes is
    // exactly what this catches.
    String? expectedSha256,
  }) async {
    final partial = File('${into.path}${Platform.pathSeparator}$filename.part');
    final target = File('${into.path}${Platform.pathSeparator}$filename');
    // Every installer, not only this one's name. Cleanup used to be scoped to
    // the in-flight download, so each previous version — 40 to 70 MB of
    // universal APK — sat in the cache directory forever under a filename that
    // never matched the delete. A user who updates monthly quietly accrues
    // hundreds of megabytes, in an app whose Settings screen reports storage.
    await _sweepInstallers(into, keep: filename);
    if (target.existsSync()) target.deleteSync();

    // A `.part` left by an interrupted attempt used to be deleted here
    // unconditionally, so a dropped connection or a killed app meant the
    // whole thing — tens of megabytes — started over from zero. Asking for
    // it by Range instead means only the part that's missing crosses the
    // network again.
    var received = partial.existsSync() ? partial.lengthSync() : 0;
    final request = http.Request('GET', Uri.parse(url));
    if (received > 0) {
      request.headers[HttpHeaders.rangeHeader] = 'bytes=$received-';
    }
    var response = await _client.send(request);

    int? total;
    FileMode mode;
    if (response.statusCode == 206) {
      // The server honoured the range: what's already on disk plus whatever
      // this response streams in is the whole file.
      total =
          _totalFromContentRange(response.headers['content-range']) ??
          (response.contentLength == null
              ? null
              : received + response.contentLength!);
      mode = FileMode.append;
    } else if (response.statusCode == 200) {
      // No partial honoured — a server that ignores Range, or nothing to
      // resume in the first place. Either way this response is the whole
      // file from byte zero, so anything already on disk has to go.
      received = 0;
      total = response.contentLength;
      mode = FileMode.write;
    } else if (response.statusCode == 416) {
      // The range asked for is already past the end of the file — the
      // partial is at least as long as the real thing, which means it is
      // stale (a previous release under the same name) rather than
      // finishable. Drop it and fetch the whole file fresh.
      if (partial.existsSync()) partial.deleteSync();
      response = await _client.send(http.Request('GET', Uri.parse(url)));
      if (response.statusCode != 200) {
        throw HttpException(
          'Download failed (${response.statusCode})',
          uri: request.url,
        );
      }
      received = 0;
      total = response.contentLength;
      mode = FileMode.write;
    } else {
      throw HttpException(
        'Download failed (${response.statusCode})',
        uri: request.url,
      );
    }

    final sink = partial.openWrite(mode: mode);
    try {
      await for (final chunk in response.stream) {
        if (isCancelled != null && isCancelled()) {
          // Flushed inside the finally below, so the bytes already read are on
          // disk and count towards the resume. Throwing rather than returning
          // keeps the verification and rename below unreachable for a file
          // that is deliberately incomplete.
          throw const DownloadPaused();
        }
        sink.add(chunk);
        received += chunk.length;
        // Null when the server sends no Content-Length: the UI shows an
        // indeterminate bar rather than a fabricated percentage.
        onProgress?.call(total == null || total == 0 ? null : received / total);
        onBytes?.call(received, total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (total != null && total > 0 && received != total) {
      // Left in place rather than deleted: a retry resumes from here instead
      // of paying for these bytes again.
      throw const HttpException('Download ended early');
    }
    if (expectedSha256 != null) {
      final digest = await sha256.bind(partial.openRead()).first;
      if ('$digest' != expectedSha256.toLowerCase()) {
        // Deleted, not left for a retry: unlike a truncated download, a
        // resume can only ever reproduce these same wrong bytes again.
        await partial.delete();
        throw const HttpException(
          'Downloaded file failed checksum verification',
        );
      }
    }
    partial.renameSync(target.path);
    return target;
  }

  /// The `<total>` out of a `Content-Range: bytes <start>-<end>/<total>`
  /// header — the authoritative size for a resumed download, since the
  /// response's own Content-Length is only the length of this one chunk.
  static int? _totalFromContentRange(String? header) {
    if (header == null) return null;
    final match = RegExp(r'/(\d+)$').firstMatch(header.trim());
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  /// Deletes stale `Nex-*.apk` / `.exe` files, leaving [keep] alone.
  static Future<void> _sweepInstallers(
    Directory dir, {
    required String keep,
  }) async {
    final pattern = RegExp(r'^Nex-.*\.(apk|exe)(\.part)?$');
    try {
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (name == keep || name == '$keep.part') continue;
        if (!pattern.hasMatch(name)) continue;
        try {
          await entity.delete();
        } catch (_) {
          // A file the system installer still holds open is not worth failing
          // the download over.
        }
      }
    } catch (_) {
      // An unreadable cache directory is not a reason to refuse an update.
    }
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
