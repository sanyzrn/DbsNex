# 35 · Asset book module audit — 2.8.18

> Implemented and tested for the 2.8.18 line. The module keeps its one-row-per
> purchase storage shape: no field was added, renamed or migrated.

## 1. The short answer

The ledger arithmetic was sound — whole rials, `BigInt` products, gold valued
as `18k rate × net grams × fineness / 750`, unknown fields kept on edit. What
did not hold up was the book around the arithmetic: a future-dated price
disappeared from the screen and could not be corrected, the price picker only
offered what was already held, editing a lot moved it to the top of the page,
a scroll followed by a reload could crash an open details tile, and nothing
said that a price was old in a market where the 18k gram moves every week.

This branch fixes those and adds the everyday Iranian surfaces a private
ledger needs — mithqal beside grams, karat presets with a live 18k
equivalent, a share bar by kind, filters for a long book, gain percentages,
price age with one-tap refresh, and a three-step first run — without changing
one byte of an existing record.

## 2. What was wrong

| Finding | Effect | Fix |
| --- | --- | --- |
| `Valuation.history` dropped quotes dated after today | The record stayed stored but vanished from Prices, so it could never be seen or corrected; only older records or hand-edited data could contain one | History keeps every observation. Valuation uses only prices up to today; the future one is shown with a warning, and editing it moves the date back into range |
| The price picker was built from gold, USD, held and already-quoted assets only | A person could not record today's euro or a coin before buying it | `priceCatalogue` offers 18k gold, every standard coin, the common currencies, and everything already in the book |
| `store.list` order (most recently saved first) reached the screen | Editing a lot moved it above its neighbours, scattering one asset's purchases | Stable order by kind, asset and purchase day, then record id |
| `ExpansionTile` inside the `PageStorageKey` list had no key of its own | Scrolling stored a `double` offset; the next rebuild cast it to `bool?` and threw `_TypeError` while opening the details | Each lot's tile has `PageStorageKey('assets-details-<id>')` |
| No price age or stale warning | A total from a month ago read like today's value | Age in words, a stale marker after 7 days, and one refresh prompt for the oldest priced rate |
| An unpriced lot was only a chip | Its cost was in the book but its value silently missing | A prompt names the count, explains the exclusion and opens the first price sheet |
| No kind totals, filter or gain percentage | “How much of this is gold?” and “is this lot up?” meant mental arithmetic | Share bar and per-kind rows, kind filters at 4+ lots, and percentages on the total and each lot |
| Gold fineness was a bare thousandth number | People say 18 karat; pieces of different purity are hard to compare | Karat presets and a live 18k-equivalent weight; mithqal beside grams |
| One generic error under a long form | “Check the amount and required fields” pointed at no field | Specific errors beside the field; date, custody and label behind `NexMoreDetails` for a new lot |
| Delete asked only “Delete this entry?” | A person could not tell whether the price history or the holding would go | The dialog names what is removed and what stays; destructive action in the error colour |
| The unit control was an unlabelled swap icon | Toman or rial was not visible in the app bar | A labelled unit button with “Show in rials/tomans” |
| A second price for the same day was silent | The newer save silently won the tie | The price sheet says the day already has a price; both observations are kept |
| The screen did not listen to its own store | A backup restore, an Undo or a quick-view write left the page stale until it was reopened | `store.changes` reloads while revealed and not writing |
| Neither the price tab nor the holdings prompt opened the sheet directly | “Record a price” meant selecting the asset again in another tab | A benchmark's edit action, a lot's `Update price` and the prompt open the quote sheet for that asset |
| The cover label said “Retry” while the secure window was still being acquired | A disabled button read as a failed one | A spinner and “Preparing…” until the window answers |

Also tightened: the damaged-record notice is a panel, the empty book is a
three-step starting point with one button, the custom-name field explains
that prices match by name, the allocation bar is excluded from semantics and
its rows are read instead, and the goal progress bar carries a screen-reader
label and percentage.

## 3. New and rethought

- **A complete price catalogue.** The picker is no longer a mirror of the
  book. It is the module's own catalogue (`priceCatalogue`), ordered gold,
  standard coins, common currencies, then named assets. A custom asset is
  still matched by its normalised name.
- **Freshness, not guessing.** `priceFreshDays = 7` is a nudge. The date and
  the age are always shown; the prompt prioritises an unpriced lot, then the
  oldest priced rate, and only one prompt is drawn. Nothing is fetched.
- **A share of the book.** `Valuation.byType` sums priced value per kind;
  the holding page draws a segmented bar and one row per kind with its
  percentage and value. The bar is `ExcludeSemantics`; the rows carry the
  same information for a screen reader.
- **Filters that do not hide the truth.** Kind chips appear at four or more
  lots; counts include unpriced lots, while the allocation still reflects
  only priced value. A filter that no longer has a lot resets after a
  reload.
- **Gold in the units people use.** Karat presets map 999/916/875/750/705/
  585/375, `karatOf` rounds to the name a shop says, and
  `normalizedGoldMg` shows the 18k-equivalent live. `mesghalMilli` converts
  milligrams with the market's 4.6083 g mithqal. Both are BigInt-exact
  before formatting.
- **Percentages that survive rounding.** `signedRounded` rounds a loss away
  from zero, so −2.5 tenths of a percent is not shown as −2.4. A zero cost
  has no percentage, rather than an infinite one.
- **Prices as a series.** `quoteDelta` gives the change from the previous
  observation; the Prices tab says higher/lower with the percentage, or
  “unchanged”, and never relies on a colour alone.
- **A minimal first form.** A new lot asks for kind, amount and price; the
  purchase date (today), custody (home) and label are one optional-details
  button away. Correcting a saved lot opens everything.
- **Errors at the field.** Each field carries its own message, the date
  cannot be in the future, a platform requires a name, and a custom asset
  requires its name. The save button stays available; nothing is disabled
  into a dead end.
- **A destructive dialog with consequences.** Deleting a holding says its
  recorded prices stay; deleting a price says the holding and its cost stay;
  deleting a goal says holdings are untouched.
- **Prices before ownership.** The catalogue and the coin/currency pickers
  let a person research and record a price before buying, which is how many
  Iranians compare a coin or a euro before a purchase.

## 4. Data and compatibility

No storage field, kind or version changed. `holding`, `quote` and `goal`
remain `v: 1` with the same fields, and `draft` gained one UI-only key
(`details`) inside its existing envelope. Reads stay defensive: unknown
fields are kept on write, a conflicting body is refused on edit, an
unreadable row is preserved and reported, and Undo restores the exact body.

A future-dated quote is now displayed in history (with a warning) instead of
being hidden. It still does not value the book, and editing it through the
shared date picker moves it to a real past or present day.

## 5. Validation

From `apps/client` on the repository pin (Flutter 3.47.9):

| Check | Result |
| --- | --- |
| `flutter analyze --no-pub --fatal-infos lib/modules/assets test/modules/assets` | `No issues found!` |
| `flutter test --no-pub test/modules/assets` | 39 tests, all green |
| Module gate, shared rules, glance, UI consistency, guide, version, update and preview tests | 193 tests across the module and those gates, all green |
| `dart format` on module source and tests | clean |

New tests cover the price catalogue and its order, a future price in history
that does not value, stable lot ordering, percentages for gain, loss and a
zero cost, type totals, the first unpriced lot, the oldest priced rate,
quote deltas, mithqal/karat/normalisation, the empty first run, a price for a
currency before it is held, a stale prompt and its departure, an unpriced
prompt, a future price warning and edit, the same-day note, kind filters,
karat presets and the saved 999 fineness, the unit switch, the allocation
and gain percentage, the delete consequence, and a compact Persian dark run
through all three tabs with 2× text and reduced motion.

**Not run in this branch:** the whole client suite (about 4,800 tests) was
not repeated; the focused gates above are the ones this module can affect.
**Not verified on a device:** the Android capture flag on a physical phone,
real notification delivery (the module sends none), and the system font at
very large accessibility sizes. The `review/` images are rendered from the
widget test's synthetic holdings and prices.

## 6. Limitations and next steps

- No sale or transfer history: a lot can be corrected or deleted, but the
  book does not record a realised gain. This is the largest remaining
  product gap for Iranian users who sell gold.
- Coins do not contribute to the gold goal; the goal counts physical gold by
  weight and fineness. Whether a coin's documented gold content should count
  is an open product question.
- The price catalogue is curated, not the full ISO list; an uncommon
  currency appears once it is held or quoted. Extending it is a one-line
  list change, not a schema change.
- One price per market is used for the whole book; different buy/sell
  spreads, coin premiums and making charges are not modelled, because the
  module must not advise or fetch.
- No sharing or export: the book is deliberately private, and the whole-book
  cover is the only sharing control.
- The allocation bar is a simple share; a historical value chart would need
  a value series that the current record shape does not keep.

## 7. Iranian references and what the research shaped

- [TGJU coin reference](https://www.tgju.org/coin) — Emami, Bahar Azadi,
  half, quarter and gram coins, and the old-design distinction.
- [TGJU market board](https://www.tgju.org/tv/) — 18k gold per gram and the
  mithqal quote.
- [Gold Check's own note](../apps/client/lib/modules/gold/gold_strings_fa.dart)
  — the market mithqal is 4.6083 g at 705 fineness; the Asset book uses the
  weight only, never an assumed purity.
- [TGJU gold price](https://www.tgju.org/gold-chart) — the weekly movement
  that makes price age matter.

**What the research shaped.** Iranian households hold gold as a store of
value, often as 18k jewellery, melted gold, coins and a little foreign
currency, spread between home, a bank box and a platform. People speak in
karat, gram and mithqal, and they compare a piece by its 18k equivalent
rather than its raw weight. Coins are named, not numbered: Emami, Bahar,
half, quarter, gram. The module therefore leads with karat presets and a
live 18k line, shows grams and mithqal together, keeps every standard coin
as its own price series, and treats a stale price as a normal part of an
inflationary market rather than an error. It still does not fetch, advise or
claim a purity: the owner's typed price is the only source.
