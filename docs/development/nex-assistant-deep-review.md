# Assistant deep review — on top of Nex 2.6.19

> Scope: the whole assistant chain, line by line — the chat sheet and its
> seven parts, the send pipeline and its generation guards, retrieval
> (fused search, the guide, Cycle), the three cloud wire formats and the
> on-device LiteRT path, action parsing and execution, chat history —
> against `main` at `83e4c52f` (PR #434).

## Applied fixes

- **Stop everywhere, on-device included.** The stop button only existed for
  provider-backed answers; with the model on the phone the sheet offered no
  way out of a wait that can run to minutes on a cold load, and the composer
  showed a disabled button over it. Stop is now wired for every answer in
  flight: it drops the wait, keeps the question under Retry, and the reply a
  native call produces anyway — the runtime has no cancellation — is
  discarded by the generation guard, the same abandonment closing the sheet
  already caused.
- **Captioned notes name themselves.** The About line and the citation chips
  fell through to the note's kind when the note's only words were a caption,
  because the labels listed fields by hand and missed it. Both now read
  `Note.displayText` — the same source the note's own card headlines — which
  knows a photo's caption is the person's line on it and a checklist's items
  are its words.
- **The lookup round fails in its own words.** A failure on the assistant's
  follow-up lookup (the request after a `search`/`tags`/… action) collapsed
  into "no answer came back", whatever had actually happened. It now gets
  the same classification the first request of the exchange gets: timeout,
  network, rate limit, key rejected, context limit, service error, and the
  local runtime's own words for an on-device model that would not start.
- **A stale contract comment.** The `listBriefWaiting` ordering comment still
  described the pre-merge "dated first" order while the query (correctly,
  since PR #434) puts urgent notes first so a limit can never drop them.
  The comment now says what the ORDER BY does.

## Reviewed and deliberately left alone

- The send pipeline's generation guards, the bounded lookup rounds, the
  invalid-action correction pass, and `ChatHistory`'s caps and atomic write.
- The synchronous media reads at sheet open (`_imagesFor`, `_fileText`): an
  awaited read was implemented and reverted — real file IO cannot complete
  inside a pumping test zone, and the determinism of "the attachment is
  there the moment the capability flips" is worth more than the frame an
  8 MB read once cost. The size caps (8 MB image, 512 KB text) bound the
  worst case, and a `.docx` already goes to its own isolate.
- `_readCycleFirst`'s retry guard is effectively unreachable (a retry trims
  back to the question before it runs); the behaviour it guards against
  would be harmless anyway — a retry re-reads a fresh summary. Left as belt
  and braces, noted here rather than churned.

## Tests

- New `assistant_deep_review_test.dart`: on-device stop (the late reply is
  discarded and a fresh question still answers), the caption About line and
  chip, and the rate-limited lookup failure.
- Existing suites re-run on the patched tree: full `apps/client` suite
  (all chunks), `packages/core` 283, `packages/data` 366 (+14 skips),
  `packages/ai` 258; `flutter analyze` and `dart format` clean.

## Risks

- Stopping an on-device answer does not cancel the native call — nothing
  can; it finishes in the background and its reply is dropped. A question
  sent immediately after a stop queues behind that call in the adapter's
  serial chain, as it already did after a failure.
- The caption change touches one label source used in three places (About
  line, grounding chips, action-card note lists); all three read the same
  `displayText` getter the timeline cards use, so a regression there would
  be visible far outside the chat.
