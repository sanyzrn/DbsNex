import 'dart:async';
import 'dart:io';

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
  /// The GPU-targeted build of Gemma-4-E2B-it, 2.01 GB.
  ///
  /// Two things about this constant are temporary and are marked as such.
  ///
  /// The URL points at Hugging Face, which is where the weights already are.
  /// That is a testing shortcut and cannot ship: HF is not reachable from Iran,
  /// which is the audience this whole feature exists for. Before release the
  /// URL becomes the self-hosted asset; nothing else about this changes, which
  /// is the reason the URL was made a value in the first place.
  ///
  /// And it is the `-gpu` artifact rather than the general one the seven
  /// Persian prompts were actually run against. It is smaller, needs no split,
  /// and is the obvious thing to test first — but it is a backend-specific
  /// build, so the adapter's CPU fallback may not be able to load it at
  /// all. Whether a device with no working OpenCL path gets a slow answer or no
  /// answer is exactly what the first install on real hardware settles.
  static const gemma4E2B = ModelRelease(
    id: 'gemma-4-e2b-it',
    filename: 'gemma-4-E2B-it-gpu.litertlm',
    sizeBytes: 2008432640,
    // Gemma's terms, not the repository's apache-2.0 badge. That badge covers
    // the conversion, not the weights, and the weights are what is being
    // redistributed here.
    licenseUrl: 'https://ai.google.dev/gemma/terms',
    licenseNotice:
        'Gemma is provided under and subject to the Gemma Terms of Use '
        'found at ai.google.dev/gemma/terms',
    sha256: 'a53a59001894c58e6bdb5b9b227709f91a2e3e556baa7d85acf9c55402ba5cf5',
    parts: [
      ModelPart(
        url:
            'https://github.com/sanyzrn/DbsNex-releases/releases/download'
            '/model-gemma-4-e2b-gpu/gemma-4-E2B-it-gpu.litertlm',
        filename: 'gemma-4-E2B-it-gpu.litertlm.part-aa',
        // One part, so this is the digest of the whole file and [sha256] above
        // is the same string. Not redundant in general — for a split model the
        // two prove different things — and cheap enough to leave symmetrical
        // rather than special-casing the single-part shape.
        sha256:
            'a53a59001894c58e6bdb5b9b227709f91a2e3e556baa7d85acf9c55402ba5cf5',
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
    this.joining = false,
  });

  final int partIndex;
  final int partCount;

  /// Overall completion across every part, 0–1, or null when a server declined
  /// to say how big its response is.
  final double? fraction;

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
  static Future<NexModelStore> open({http.Client? client}) async {
    final support = await getApplicationSupportDirectory();
    final root = Directory(p.join(support.path, 'models'));
    await root.create(recursive: true);
    return NexModelStore(root: root, client: client);
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
  }) async {
    if (!installable(model)) {
      throw StateError('${model.id} has no published download yet');
    }
    final target = fileFor(model);
    if (target.existsSync()) return target;

    final dir = _dirFor(model);
    await dir.create(recursive: true);

    final parts = <File>[];
    for (var i = 0; i < model.parts.length; i++) {
      final part = model.parts[i];
      final onDisk = File(p.join(dir.path, part.filename));
      // A part that is already here and already correct is not downloaded
      // again. Over a 2.6 GB install on a connection that drops, this is the
      // difference between resuming and starting over.
      if (onDisk.existsSync() && await _digestOf(onDisk) == part.sha256) {
        parts.add(onDisk);
        onProgress?.call(
          ModelInstallProgress(
            partIndex: i,
            partCount: model.parts.length,
            fraction: (i + 1) / model.parts.length,
          ),
        );
        continue;
      }
      parts.add(
        await _downloader.download(
          url: part.url,
          into: dir,
          filename: part.filename,
          expectedSha256: part.sha256,
          onProgress: (fraction) => onProgress?.call(
            ModelInstallProgress(
              partIndex: i,
              partCount: model.parts.length,
              fraction: fraction == null
                  ? null
                  : (i + fraction) / model.parts.length,
            ),
          ),
        ),
      );
    }

    onProgress?.call(
      ModelInstallProgress(
        partIndex: model.parts.length,
        partCount: model.parts.length,
        fraction: 1,
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

  /// Removes a model and anything left over from installing it.
  Future<void> delete(ModelRelease model) async {
    final dir = _dirFor(model);
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  static Future<String> _digestOf(File file) async =>
      '${await sha256.bind(file.openRead()).first}';

  void close() => _downloader.close();
}
