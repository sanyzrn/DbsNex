part of 'app.dart';

extension _NexAppDownloadNotices on _NexAppState {
  /// Puts the download in the notification shade, where it can be watched
  /// without this app being open.
  ///
  /// Here rather than in the service because the strings are localised and
  /// the service has no `BuildContext` — and should not grow one to post a
  /// notification. The messenger's context sits under [MaterialApp], which is
  /// as much as `AppLocalizations` needs.
  ///
  /// A stopped download takes its entry down rather than replacing it with a
  /// second kind of notification: resuming lives on the update screen, and a
  /// shade entry that only says "something went wrong" is noise.
  void _showDownloadNotification(NexDownloadStatus status) {
    final context = _messengerKey.currentContext;
    if (context == null) return;
    final l10n = AppLocalizations.of(context);
    final reminders = widget.services.reminders;
    switch (status.stage) {
      case NexDownloadStage.running:
        unawaited(
          _reportDownload(l10n.updateDownloadingTitle, status.percent ?? 0),
        );
      case NexDownloadStage.done:
        // The service goes first: its notification is the progress bar, and
        // the one below is the tappable "ready to install" that has to
        // outlive it.
        unawaited(NexDownloadNotice.hide());
        unawaited(
          reminders.showDownloadReady(
            title: l10n.updateReadyTitle,
            body: l10n.updateReadyBody,
          ),
        );
      case NexDownloadStage.stopped:
        unawaited(NexDownloadNotice.hide());
        unawaited(reminders.clearDownloadNotification());
    }
  }

  /// Puts the progress in the shade, by whichever half of the app can.
  ///
  /// On Android that is a foreground service, because the notification is not
  /// the point of it — keeping the process running while the transfer
  /// continues is, and only a service does that. Where there is no service,
  /// the app posts the notification itself, which is all this ever was.
  Future<void> _reportDownload(String title, int percent) async {
    // The percentage in the app's digits (LOC-07), formatted here where the
    // language is known; the native side only shows it.
    final context = _messengerKey.currentContext;
    final persian =
        context != null && Localizations.localeOf(context).languageCode == 'fa';
    final body = persian
        ? '${nexDigits('$percent', persian: true)}٪'
        : '$percent%';
    if (await NexDownloadNotice.show(
      title: title,
      percent: percent,
      body: body,
      channel: NexReminders.channelText.updates,
      channelAbout: NexReminders.channelText.updatesAbout,
    )) {
      return;
    }
    await widget.services.reminders.showDownloadProgress(
      title: title,
      percent: percent,
      body: body,
    );
  }

  /// Says so, once, when an installer finishes arriving.
  ///
  /// The download survives leaving the update screen now, which means it
  /// usually finishes while the user is somewhere else — and something that
  /// completes invisibly may as well not have happened. This is the one place
  /// the update flow is allowed to speak unprompted, and it is a toast that
  /// fades on its own rather than anything that has to be dismissed.
  void _announceDownload() {
    if (!_updates.hasUnannouncedDownload) return;
    final context = _messengerKey.currentContext;
    if (context == null) return;
    _updates.markAnnounced();
    nexShowBanner(
      context,
      message: AppLocalizations.of(context).updateDownloadedToast,
      haptics: widget.preferences.haptics,
    );
  }
}
