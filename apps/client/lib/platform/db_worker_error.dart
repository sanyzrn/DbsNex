import 'dart:io';
import 'package:nex_data/nex_data.dart' show NewerLibraryException;

enum DbFailureKind { newerLibrary, format, fileSystem, other }

class DbWorkerException extends StateError {
  DbWorkerException(
    this.kind,
    this.sourceType,
    String detail, {
    String prefix = 'nex-db worker failed',
  }) : super('$prefix: $detail');
  final DbFailureKind kind;
  final String sourceType;

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
  );
}
