import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  static NexVersion? tryParse(String value) {
    final match = _pattern.firstMatch(value.trim());
    if (match == null) return null;
    return NexVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      preRelease: match.group(4),
    );
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
  const UpdateCheck._(this.status, {this.version, this.downloadUrl, this.sizeBytes, this.notes});

  const UpdateCheck.upToDate() : this._(UpdateStatus.upToDate);

  const UpdateCheck.unavailable() : this._(UpdateStatus.unavailable);

  const UpdateCheck.available({
    required NexVersion version,
    required String downloadUrl,
    int? sizeBytes,
    String? notes,
  }) : this._(
          UpdateStatus.available,
          version: version,
          downloadUrl: downloadUrl,
          sizeBytes: sizeBytes,
          notes: notes,
        );

  final UpdateStatus status;
  final NexVersion? version;
  final String? downloadUrl;
  final int? sizeBytes;
  final String? notes;
}

/// Which release asset a platform installs.
///
/// The names are a contract with the release workflow, which builds exactly
/// these. Android takes the universal APK because the app cannot know the
/// device's ABI before downloading, and installing the wrong split silently
/// fails.
String? _assetNameSuffix() {
  if (Platform.isAndroid) return '-universal.apk';
  if (Platform.isWindows) return '.exe';
  return null;
}

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
    this.repository = 'sanyzrn/DbsNex',
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

    try {
      final response = await _client.get(
        _latestUri,
        headers: const {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return const UpdateCheck.unavailable();
      return _parse(response.body, installed: installed, suffix: suffix);
    } on TimeoutException {
      return const UpdateCheck.unavailable();
    } catch (_) {
      // Offline, DNS failure, TLS failure, malformed body — all the same
      // outcome to the user, and none of them should reach the UI as a crash.
      return const UpdateCheck.unavailable();
    }
  }

  @visibleForTesting
  UpdateCheck parseForTest(
    String body, {
    required NexVersion installed,
    required String suffix,
  }) =>
      _parse(body, installed: installed, suffix: suffix);

  UpdateCheck _parse(
    String body, {
    required NexVersion installed,
    required String suffix,
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return const UpdateCheck.unavailable();
    }
    if (decoded is! Map<String, dynamic>) return const UpdateCheck.unavailable();

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
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = asset['name'];
      final url = asset['browser_download_url'];
      if (name is! String || url is! String) continue;
      if (!name.endsWith(suffix)) continue;
      final size = asset['size'];
      return UpdateCheck.available(
        version: latest,
        downloadUrl: url,
        sizeBytes: size is int ? size : null,
        notes: decoded['body'] is String ? decoded['body'] as String : null,
      );
    }
    // A newer release with nothing this platform can install is not an update.
    return const UpdateCheck.upToDate();
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

/// Streams the installer to disk, reporting progress.
///
/// Downloads to a temporary name and renames on completion, so an interrupted
/// download can never be handed to the package installer as if it were whole.
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
  }) async {
    final partial = File('${into.path}${Platform.pathSeparator}$filename.part');
    final target = File('${into.path}${Platform.pathSeparator}$filename');
    // Every installer, not only this one's name. Cleanup used to be scoped to
    // the in-flight download, so each previous version — 40 to 70 MB of
    // universal APK — sat in the cache directory forever under a filename that
    // never matched the delete. A user who updates monthly quietly accrues
    // hundreds of megabytes, in an app whose Settings screen reports storage.
    await _sweepInstallers(into, keep: filename);
    if (partial.existsSync()) partial.deleteSync();
    if (target.existsSync()) target.deleteSync();

    final request = http.Request('GET', Uri.parse(url));
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      throw HttpException('Download failed (${response.statusCode})', uri: request.url);
    }

    final total = response.contentLength;
    var received = 0;
    final sink = partial.openWrite();
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        // Null when the server sends no Content-Length: the UI shows an
        // indeterminate bar rather than a fabricated percentage.
        onProgress?.call(total == null || total == 0 ? null : received / total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (total != null && total > 0 && received != total) {
      partial.deleteSync();
      throw const HttpException('Download ended early');
    }
    partial.renameSync(target.path);
    return target;
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
