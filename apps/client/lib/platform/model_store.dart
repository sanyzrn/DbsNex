import 'dart:async';
import 'dart:io';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_update.dart';

/// One downloadable piece of a model.
///
/// A model larger than 2 GiB ships split, because that is the cap on a single
/// GitHub release asset; a release accepts up to a thousand of them, so the cap
/// shapes the packaging and nothing else. A model that fits is one part, and
/// nothing downstream distinguishes the two cases — [NexModelStore.install]
/// joins and verifies a list of one exactly as it does a list of two.
class ModelPart {
  const ModelPart({
    required this.url,
    required this.filename,
    required this.sha256,
  });

  final String url;
  final String filename;

  /// Hex digest of *this part*, checked as it lands. Verifying per part rather
  /// than only at the end is what keeps a corrupted 1.3 GB half from being
  /// discovered after the other 1.3 GB has also been paid for.
  final String sha256;
}

/// A model Nex can install, as configuration rather than as code.
///
/// URLs and digests are values so that publishing a model is an edit to a
/// constant and not a change to the download logic. [NexModelStore] takes one
/// of these and knows nothing else about which model it is.
class ModelRelease {
  const ModelRelease({
    required this.id,
    required this.filename,
    required this.parts,
    required this.sha256,
    required this.sizeBytes,
    required this.licenseUrl,
    required this.licenseNotice,
  });

  /// Stable identifier, used as the on-disk directory name.
  final String id;

  /// What the joined file is called — the name LiteRT-LM is handed.
  final String filename;

  final List<ModelPart> parts;

  /// Hex digest of the *joined* file. Not redundant with the per-part digests:
  /// they prove each download arrived intact, this proves they were put back
  /// together in the right order.
  final String sha256;

  /// Total size of the finished model, for the "do you have room" check and
  /// for telling someone what they are about to spend before they spend it.
  final int sizeBytes;

  /// Where the model's licence lives, shown before anything is downloaded.
  ///
  /// Gemma is redistributable under conditions, and they are not paperwork:
  /// every recipient must be given the terms, and the use restrictions must
  /// carry forward. Nex hosts these weights, which makes Nex the distributor
  /// and makes this screen the obligation — see 09-ai.md.
  final String licenseUrl;

  /// The exact sentence the licence requires accompany a distribution.
  final String licenseNotice;
}

/// The models this build knows how to install.
///
/// A model with a URL and a digest is offered; one missing either is invisible,
/// because [NexModelStore.installable] reports false and no UI offers a
/// download that would 404 or arrive unverified. Publishing is an edit here.
abstract final class NexModels {
  /// Gemma-4-E2B-it, 2,588,147,712 bytes, split across two release assets
  /// because a single one caps at 2 GiB.
  ///
  /// The `-gpu` variant was tried first and is not usable: the runtime rejects
  /// it with `NOT_FOUND: TF_LITE_PREFILL_DECODE not found in the model`. It is
  /// a backend-specific artifact that does not carry the prefill/decode
  /// signature an engine needs, which is why `flutter_litert_lm` curates this
  /// file and not that one. It was picked because it fit under the cap without
  /// splitting — a packaging convenience, and never a reason to ship a model
  /// that cannot load.
  ///
  /// Every value below was verified against the hosted assets rather than
  /// taken on trust: both parts were streamed and hashed, and their
  /// concatenation reproduces [sha256] exactly. That check is worth the
  /// bandwidth — the first upload of this file was split at an offset taken
  /// from the model's *published* size, which is 5,062,656 bytes short of the
  /// real one, so the two parts each hashed correctly and did not rejoin into
  /// anything. Per-part digests alone would not have caught it.
  ///
  /// The parts are deliberately unequal. `part-aa` is the first
  /// 1,291,542,528 bytes and `part-ab` is everything after it, whatever that
  /// turns out to be, which is what stops a stale published size from
  /// truncating the model again.
  static const gemma4E2B = ModelRelease(
    id: 'gemma-4-e2b-it',
    filename: 'gemma-4-E2B-it.litertlm',
    sizeBytes: 2588147712,
    // Gemma's terms, not the repository's apache-2.0 badge. That badge covers
    // the conversion, not the weights, and the weights are what is being
    // redistributed here.
    licenseUrl: 'https://ai.google.dev/gemma/terms',
    licenseNotice:
        'Gemma is provided under and subject to the Gemma Terms of Use '
        'found at ai.google.dev/gemma/terms',
    sha256: '181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c',
    parts: [
      ModelPart(
        url:
            'https://github.com/sanyzrn/DbsNex-releases/releases/download'
            '/Gemma4/gemma-4-E2B-it.litertlm.part-aa',
        filename: 'gemma-4-E2B-it.litertlm.part-aa',
        sha256:
            '93330ce684caae1ac2e16f964b434f64bb8341149306516996d5a8bb52ac6a98',
      ),
      ModelPart(
        url:
            'https://github.com/sanyzrn/DbsNex-releases/releases/download'
            '/Gemma4/gemma-4-E2B-it.litertlm.part-ab',
        filename: 'gemma-4-E2B-it.litertlm.part-ab',
        sha256:
            'd1f014f2896040f7b69928fb3a892295694f43a332889a1124ad3d5c50df31b1',
      ),
    ],
  );
}

/// How far along an install is, for the screen watching it.
class ModelInstallProgress {
  const ModelInstallProgress({
    required this.partIndex,
    required this.partCount,
    required this.fraction,
    this.receivedBytes = 0,
    this.totalBytes,
    this.joining = false,
  });

  final int partIndex;
  final int partCount;

  /// Overall completion across every part, 0–1, or null when a server declined
  /// to say how big its response is.
  final double? fraction;

  /// Bytes on disk for this model so far, across every part.
  ///
  /// Shown beside the bar because a percentage is the wrong unit here. On a
  /// metered connection the question is not "how far along" but "how much of
  /// my data has this spent and how much is left", and only these two numbers
  /// answer it.
  final int receivedBytes;

  /// The whole model's size, or null while no server has said. Falls back to
  /// the release constant in the UI rather than showing nothing.
  final int? totalBytes;

  /// True during the join-and-verify pass, which moves gigabytes on disk and
  /// reports no byte-level progress of its own.
  final bool joining;
}

/// Downloads, verifies, assembles and deletes on-device model weights.
///
/// Deliberately built on [UpdateDownloader] rather than beside it. That class
/// already does the hard parts — Range-resumed downloads, `Content-Range`
/// handling, SHA-256 verification, and the distinction between a truncated
/// file worth resuming and a corrupt one worth deleting — and a second
/// implementation of all that would be a second set of the same bugs. Its
/// installer sweep is scoped to `Nex-*.{apk,exe}`, so it never touches these.
class NexModelStore {
  NexModelStore({required this.root, http.Client? client})
    : _downloader = UpdateDownloader(client: client);

  /// Opens the store at the one directory the whole app agrees on.
  ///
  /// Both the "ai" flavor's entry point and the screen that manages downloads
  /// need this path, and they must not each construct it — two nearly-equal
  /// strings would mean a model downloaded to one place and looked for in
  /// another, with nothing to show why.
  /// Shared because the screen and the install controller must not each hold
  /// their own. They used to: the screen closed its store on dispose, which
  /// was correct until the download outlived the screen, and then closing it
  /// would have cut the download's own client out from under it. Opening a
  /// second one instead leaks an HTTP client per visit. One instance is
  /// neither.
  static NexModelStore? _shared;

  static Future<NexModelStore> open({http.Client? client}) async {
    final existing = _shared;
    // A caller that supplies its own client wants its own store — that is
    // only tests, and they must not be handed the process-wide one.
    if (existing != null && client == null) return existing;
    final support = await getApplicationSupportDirectory();
    final root = Directory(p.join(support.path, 'models'));
    await root.create(recursive: true);
    final store = NexModelStore(root: root, client: client);
    if (client == null) _shared = store;
    return store;
  }

  /// Where models live. A directory of Nex's own, not the media directory:
  /// these are not the user's files, they are replaceable and enormous, and
  /// nothing that backs up notes should ever pick them up.
  final Directory root;

  final UpdateDownloader _downloader;

  Directory _dirFor(ModelRelease model) =>
      Directory(p.join(root.path, model.id));

  /// The finished model file, whether or not it exists yet.
  File fileFor(ModelRelease model) =>
      File(p.join(_dirFor(model).path, model.filename));

  /// Whether this build has somewhere to download this model *from*.
  ///
  /// False while the release constant is still a placeholder. The UI asks this
  /// before offering anything, so an unpublished model is invisible rather than
  /// a button that fails.
  static bool installable(ModelRelease model) =>
      model.sha256.isNotEmpty &&
      model.parts.isNotEmpty &&
      model.parts.every(
        (part) => part.url.isNotEmpty && part.sha256.isNotEmpty,
      );

  bool isInstalled(ModelRelease model) => fileFor(model).existsSync();

  /// Bytes this model currently occupies, finished or half-downloaded.
  ///
  /// Counts parts too: an interrupted install is invisible in the file list and
  /// very visible in the storage figure, and a Settings screen that reports one
  /// without the other is the reason people think an app is lying to them.
  int installedBytes(ModelRelease model) {
    final dir = _dirFor(model);
    if (!dir.existsSync()) return 0;
    var total = 0;
    for (final entity in dir.listSync()) {
      if (entity is File) total += entity.lengthSync();
    }
    return total;
  }

  /// Downloads every part, verifies each, joins them, verifies the whole, and
  /// leaves exactly one file behind.
  ///
  /// Safe to call again after a failure: finished parts are kept and skipped,
  /// and a half-finished one resumes by range.
  Future<File> install(
    ModelRelease model, {
    void Function(ModelInstallProgress progress)? onProgress,

    /// Polled per chunk. See [UpdateDownloader.download] — true stops the
    /// install and throws [DownloadPaused], leaving every downloaded byte
    /// where it is so the next call resumes.
    bool Function()? isCancelled,
  }) async {
    if (!installable(model)) {
      throw StateError('${model.id} has no published download yet');
    }
    final target = fileFor(model);
    if (target.existsSync()) return target;

    final dir = _dirFor(model);
    await dir.create(recursive: true);

    final parts = <File>[];
    // Bytes finished by whole parts, so a per-part counter can be added to it
    // without either number having to know about the other.
    var done = 0;
    for (var i = 0; i < model.parts.length; i++) {
      final part = model.parts[i];
      final onDisk = File(p.join(dir.path, part.filename));
      // A part that is already here and already correct is not downloaded
      // again. Over a 2.6 GB install on a connection that drops, this is the
      // difference between resuming and starting over.
      if (onDisk.existsSync() && await _digestOf(onDisk) == part.sha256) {
        parts.add(onDisk);
        done += onDisk.lengthSync();
        onProgress?.call(
          ModelInstallProgress(
            partIndex: i,
            partCount: model.parts.length,
            fraction: (i + 1) / model.parts.length,
            receivedBytes: done,
            totalBytes: model.sizeBytes,
          ),
        );
        continue;
      }
      final finishedBefore = done;
      parts.add(
        await _downloader.download(
          url: part.url,
          into: dir,
          filename: part.filename,
          expectedSha256: part.sha256,
          isCancelled: isCancelled,
          onProgress: (fraction) => onProgress?.call(
            ModelInstallProgress(
              partIndex: i,
              partCount: model.parts.length,
              fraction: fraction == null
                  ? null
                  : (i + fraction) / model.parts.length,
              // Bytes banked by earlier parts plus this one's own count, so
              // the figure never restarts at zero when a part boundary is
              // crossed — which on a two-part model looked like the download
              // having thrown away the first half.
              receivedBytes: done,
              totalBytes: model.sizeBytes,
            ),
          ),
          onBytes: (received, _) => done = finishedBefore + received,
        ),
      );
      done = finishedBefore + onDisk.lengthSync();
    }

    onProgress?.call(
      ModelInstallProgress(
        partIndex: model.parts.length,
        partCount: model.parts.length,
        fraction: 1,
        receivedBytes: done,
        totalBytes: model.sizeBytes,
        joining: true,
      ),
    );
    return _join(model, parts, target);
  }

  /// Concatenates the parts in order and checks the result.
  ///
  /// Written through a staging file rather than straight to [target]: a join
  /// interrupted halfway would otherwise leave a file of the right name and
  /// the wrong length, which [isInstalled] would call installed and LiteRT-LM
  /// would fail to load with nothing pointing at why.
  Future<File> _join(ModelRelease model, List<File> parts, File target) async {
    final staging = File('${target.path}.joining');
    if (staging.existsSync()) await staging.delete();
    final sink = staging.openWrite();
    try {
      for (final part in parts) {
        await sink.addStream(part.openRead());
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (await _digestOf(staging) != model.sha256) {
      // The parts each verified and the whole did not, which means they were
      // assembled wrong rather than downloaded wrong. Deleting the join and
      // keeping the parts makes a retry cost disk time instead of 2.6 GB of
      // someone's data.
      await staging.delete();
      throw const HttpException('Assembled model failed checksum verification');
    }

    await staging.rename(target.path);
    // Only once the whole file is verified and in place. Until this line a
    // failure anywhere above leaves every downloaded byte on disk to resume
    // from; after it they are 1.3 GB each of pure duplication.
    for (final part in parts) {
      try {
        await part.delete();
      } catch (_) {}
    }
    return target;
  }

  /// Installs from bytes the user already has, instead of downloading them.
  ///
  /// Takes a stream rather than a [File] on purpose, and the reason is not
  /// taste. Android hands a picked document to an app as a `content://` URI,
  /// and the obvious way to turn that into a path — `file_selector` — reads
  /// the whole document into a Java `byte[]` sized from an `int` before
  /// copying it to the cache. For a 2.5 GB model that either overflows the
  /// int or exhausts the heap, and the app dies before this method is ever
  /// reached. A stream never materialises the file twice and never sizes
  /// anything by an int.
  ///
  /// The digest is what makes this safe to offer at all. Accepting arbitrary
  /// bytes someone picked and handing them to a native runtime would be a way
  /// to load anything; checking against the release constant first means the
  /// only thing accepted is byte-for-byte what would have been downloaded. So
  /// it is computed here, while writing, and the file is only put in place if
  /// it matches — one pass over 2.5 GB rather than two.
  Future<File> installFromStream(
    ModelRelease model,
    Stream<List<int>> source, {
    void Function(ModelInstallProgress progress)? onProgress,
  }) async {
    final target = fileFor(model);
    if (target.existsSync()) return target;

    await _dirFor(model).create(recursive: true);
    // Through a staging name for the same reason the join is: an interrupted
    // copy would otherwise leave a file of the right name and the wrong
    // length, which isInstalled would call installed.
    final staging = File('${target.path}.copying');
    if (staging.existsSync()) await staging.delete();

    final digest = AccumulatorSink<Digest>();
    final hasher = sha256.startChunkedConversion(digest);
    final sink = staging.openWrite();
    var written = 0;
    try {
      await for (final chunk in source) {
        hasher.add(chunk);
        sink.add(chunk);
        written += chunk.length;
        onProgress?.call(
          ModelInstallProgress(
            partIndex: 0,
            partCount: 1,
            fraction: model.sizeBytes == 0
                ? null
                : (written / model.sizeBytes).clamp(0, 1),
            receivedBytes: written,
            totalBytes: model.sizeBytes,
          ),
        );
      }
      await sink.flush();
    } finally {
      await sink.close();
      hasher.close();
    }

    if ('${digest.events.single}' != model.sha256) {
      await staging.delete();
      throw const FileSystemException(
        'That file is not this model — its checksum does not match',
      );
    }
    await staging.rename(target.path);
    return target;
  }

  /// Convenience over [installFromStream] for a file with a real path.
  Future<File> installFromFile(
    ModelRelease model,
    File source, {
    void Function(ModelInstallProgress progress)? onProgress,
  }) => installFromStream(model, source.openRead(), onProgress: onProgress);

  /// Removes a model and anything left over from installing it.
  Future<void> delete(ModelRelease model) async {
    final dir = _dirFor(model);
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  static Future<String> _digestOf(File file) async =>
      '${await sha256.bind(file.openRead()).first}';

  void close() => _downloader.close();
}
