import 'dart:async';
import 'dart:io';

import 'package:nex_core/nex_core.dart';

import '../l10n/app_localizations.dart';
import '../platform/db_worker_error.dart';

/// Show only a verified category; an unknown cause stays unknown.
String nexAiFailureMessage(Object? error, AppLocalizations l10n) {
  final kind = switch (error) {
    AiFailureKind() => error,
    AiUnavailableException() => error.kind,
    DbWorkerException() => error.aiFailure,
    TimeoutException() => AiFailureKind.timeout,
    SocketException() => AiFailureKind.network,
    _ => null,
  };
  return switch (kind) {
    AiFailureKind.network => l10n.aiFailureNetwork,
    AiFailureKind.timeout => l10n.aiFailureTimeout,
    AiFailureKind.rateLimit => l10n.aiFailureRateLimit,
    AiFailureKind.credentials => l10n.aiFailureCredentials,
    AiFailureKind.unsupported => l10n.aiFailureUnsupported,
    AiFailureKind.tooLarge => l10n.aiFailureTooLarge,
    AiFailureKind.incomplete => l10n.aiIncompleteReply,
    AiFailureKind.unreadableImage => l10n.aiImageUnreadable,
    AiFailureKind.noSpeech => l10n.aiAudioNoSpeech,
    AiFailureKind.missingFile => l10n.aiFailureMissingFile,
    _ => l10n.aiFailureUnknown,
  };
}
