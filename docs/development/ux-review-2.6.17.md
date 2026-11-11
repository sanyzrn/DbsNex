# UX review against 2.6.17

Source: nex-flutter-ux-audit.zip, baseline 2.6.16. Source-only findings were checked against the current branch rather than applied blindly.

Implemented the four groups confirmed before this change:

- UX01: trash purge follows the actual Undo overlay lifetime, including accessibility and pointer holds; leaving the page dismisses every outstanding purge banner before finalizing.
- UX02–03: reminder-transfer failures preserve the capture source and reuse the pending destination on retry; media handoff uses the same saved-text guard as ordinary close.
- UX08: a recurring notification destination is retained behind the lock and consumed on unlock.
- UX14: a compact Undo action remains available when editor height cannot accommodate the full Undo bar.

Additional requests: ordinary attachment limit raised from 100 MiB to 500 MiB in Dart and Android; native picker refusal metadata reaches a shared localized UI; the untagged filter uses a content-free database existence query across the complete visible timeline, not just its loaded page. The vault retains its separate 25 MiB limit.

Other report claims are not represented as fixed by this change. UX11 in particular conflicts with the intentional keyboard dismissal policy.
