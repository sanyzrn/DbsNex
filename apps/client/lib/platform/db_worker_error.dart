import 'dart:io';
import 'package:nex_core/nex_core.dart'
    show AiUnavailableException, AiFailureKind;
import 'package:nex_data/nex_data.dart' show NewerLibraryException;

enum DbFailureKind { newerLibrary, format, fileSystem, other }

class DbWorkerException extends StateError {
  DbWorkerException(
    this.kind,
    this.sourceType,
    String detail, {
    String prefix = 'nex-db worker failed',
    this.aiFailure,
  }) : super('$prefix: $detail');
  final DbFailureKind kind;
  final String sourceType;
  final AiFailureKind? aiFailure;

  factory DbWorkerException.from(
    Object error, {
    String prefix = 'nex-db worker failed',
  }) => DbWorkerException(
    switch (error) {
      NewerLibraryException() => DbFailureKind.newerLibrary,
      FormatException() => DbFailureKind.format,
      FileSystemException() => DbFailureKind.fileSystem,
      _ => DbFailureKind.other,
    },
    error.runtimeType.toString(),
    '$error',
    prefix: prefix,
    aiFailure: error is AiUnavailableException ? error.kind : null,
  );
}
