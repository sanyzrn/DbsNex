# Home-screen widgets: the data contract

The four home-screen widgets — Capture, Timeline, Recap and the two Cycle
shapes — are native Android views that render from files this document
defines. A widget provider is a broadcast receiver with about ten seconds
to live and no Flutter engine behind it, so everything it can ever show is
written down before it is asked. This file is the contract between the
writer (`apps/client/lib/platform/nex_widget.dart`,
`cycle_widget.dart`) and the reader (the Kotlin under
`apps/client/android/app/src/main/kotlin/com/sanyzrn/nex/`), so that the
two halves cannot drift apart silently.

## The pipeline

```
Dart (NexWidgetBridge)                      Kotlin (the providers)
─────────────────────                       ─────────────────────
timelineStream / cycleChanges ─┐
app-lock gate ─────────────────┤
recap filed ───────────────────┴─▶ debounce 300ms
                                    │
                                    ▼
                    write <file>.tmp, flush, rename   ──▶ atomic
                                    │
                                    ▼
                    pushWidgets on `nex/os_capture`
                                    │
                                    ▼
                    MainActivity saves locale/accent,
                    NexWidgetActions.refreshAll() ──▶ one explicit
                        APPWIDGET_UPDATE broadcast per provider
                                    │
                                    ▼
                    each provider re-renders; the list
                    factories re-read on data-set change
```

`updatePeriodMillis` is 0 for Capture, Timeline and Recap: nothing they
show is allowed to go stale, because the app re-renders the moment its own
data moves. The two Cycle widgets wake every three hours instead, because
what they show — "day 12 of the cycle" — changes with the calendar and
not with the data.

## The files

Both files live in `filesDir` (Dart's `getApplicationSupportDirectory()`,
where `nex.sqlite` itself sits): app-private storage, same UID as the
providers, no content provider for anything else to reach.

### `nex_widget_snapshot.json`

Written by `NexWidgetSnapshot.build`; read by `NexWidgetSnapshot.read`.

| field | since | meaning |
| --- | --- | --- |
| `version` | 1 | the schema version; a reader rejects anything newer than itself and reads anything older field by field |
| `appLock` | 1 | the locked marker: when true, `notes` and `recap` are empty in the file, not merely hidden |
| `generatedAt` | 1 | epoch ms; when the app wrote the snapshot (not shown: the file is rewritten only when the data changes, so its age says nothing about whether it is current) |
| `notes[]` | 1 | `id`, `type` (wire name), `preview` (≤200 chars, whitespace collapsed), `updatedAt`; at most 15 rows, timeline order |
| `recap` | 2 | the assistant's brief, as the lines the recap card is showing; empty string, never a missing field |

### `nex_cycle_widget.json`

Written by `NexCycleWidgetSnapshot.build`; read by `NexCycleSnapshot.read`.
One `state` word — `off`, `locked`, `setup` or `ready` — and, when `ready`,
dates and averages only (`lastStart`, `periodEnd`, `nextStart`,
`averageCycle`, `averagePeriod`, the fertile window, `ovulation`, and
`pregnancyStart` in pregnant mode). Every "days until" figure is computed
on the device at render time, so it stays right on days the app is not
opened. Never a day log, a symptom, a mood or a sentence.

## The privacy rules

Three facts, and the order they are asked in is the whole rule:

1. no lock — nothing to hide from;
2. a lock the user told the widget to ignore — their home screen, their
   decision (`widgetShowWhenLocked`);
3. otherwise, notes show exactly while the lock is *open*.

Privacy is enforced at **write time**, not read time: while the rule hides
notes, the file is rewritten empty and the write path never queries the
library at all. The lock *closing* is written straight through without the
debounce, and a lock that closes while a write is in flight is checked
again before the rename — no event-loop gap between the check and the
publish.

## What the widgets may never do

- Read SQLite. The schema is a Dart-side contract; a second reader across
  a process boundary would be the app's most fragile database client.
- Ask a model anything. The Recap widget's refresh opens the app, because
  the app is the only process that can write a brief.
- Refresh on a timer for data freshness. Timers cost battery; the data
  pushes itself.

## Fonts and the launcher

Widget layouts are inflated by the *launcher*, with the launcher's
configuration — which is why every user-visible word is set
programmatically from a context localized with the app's saved locale
(`NexWidgetAppearance.localized`). Fonts cannot travel that way
(RemoteViews carries no font action), so Persian typography rides on a
`values-fa-v26` style override pointing at `res/font/vazirmatn.xml`: a
Persian *device* draws its widgets in the app's own Persian face, which is
the only configuration the launcher resolves those styles under. The one
exception is the Cycle ring's centre number — a bitmap we draw ourselves,
so it follows the app's saved locale rather than the device's.

## Preview layouts

Android 12+ inflates `previewLayout` in the picker *instead of*
`previewImage`. The live Timeline and Recap layouts hold ListViews that
bind nothing until a provider runs, so their `previewLayout`s are
dedicated static layouts (`widget_timeline_preview.xml`,
`widget_recap_preview.xml`) carrying sample rows from string resources —
real-looking content, in the device's language, never "Lorem ipsum".

## Reading the snapshot

Every provider and list factory reads the file on a push. `NexWidgetSnapshot.read`
and `NexCycleSnapshot.read` keep the last parse keyed on the file's text, in one
volatile field, so a push parses once. The key is the text rather than the file's
(modified time, length): on some Android versions the clock's resolution is a
second, and a same-length edit inside it would serve the old snapshot.

## Not shown, on purpose

- **How long ago the snapshot was written.** It is rewritten only when the data
  changes, and a widget renders only when pushed, so a label would either call a
  current list "3 h ago" or say "now" for hours.
- **Cycle content in the picker's preview.** The picker is open to anyone holding
  the phone; the Recap preview's sample lines are neutral.

