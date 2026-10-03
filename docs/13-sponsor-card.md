# The sponsor card

Nex is free. There is no paid tier, no account, and nothing held back. The
timeline can instead carry **one** card, the size of one note card and marked
`SPONSORED`, whose entire content is a file on a server.

There is no ad network, no identifier and no profile. The request says only
that a copy of Nex asked; the answer is the same for everyone who asks.

## Publishing one

Put a file named `banner.json` at the root of the maker's site:

```
https://saeedzarrini.ir/banner.json
```

Taking a card down is deleting that file. A 404 is not an error: it is how a
campaign ends, and the app clears its cache when it sees one.

The card's picture may be hosted anywhere. A picture on
`raw.githubusercontent.com`, which is filtered on many networks in Iran, is
fetched from jsDelivr's copy of the same file when GitHub cannot be reached;
jsDelivr caches for up to 12 hours. (Until 1.90 the card itself lived in the
releases repository and used the same fallback.)

## The file

`docs/banner.example.json` is a working card, ready to copy:

```json
{
  "id": "2026-09-nexahr",
  "title": "NexaHR — منابع انسانی، بدون کاغذبازی",
  "body": "حضور و غیاب، مرخصی و حقوق در یک جا",
  "color": "#2FBF8F",
  "url": "https://nexahr.example",
  "starts": "2026-09-01T00:00:00Z",
  "ends": "2026-12-31T00:00:00Z",
  "locales": ["fa"]
}
```

| field | required | what it does |
|---|---|---|
| `id` | yes | What a dismissal is recorded against, so hiding one campaign says nothing about the next. A new campaign wants a new id. |
| `title` | yes | One line. Also the screen-reader label for a card that is all picture. |
| `body` | no | A second line, under the title. Dropped on a card with a picture, which has no room for it. |
| `color` | no | `#RRGGBB`. Tints the wordy card; ignored when there is a picture. Defaults to the app's accent. |
| `image` | no | A picture to fill the card. See below. |
| `url` | no | Opened on tap. `https` and `http` only — anything else is ignored. A card with no link is still a card. |
| `starts` / `ends` | no | ISO-8601. Outside the window, nothing appears. |
| `locales` | no | Language codes, e.g. `["fa"]`. Empty or absent means everyone. A card written in Persian has no business appearing for an English reader. |

## Pictures

`image` is an absolute `https` url to a **JPEG, PNG, WebP, GIF, or the
animated forms of the last two**. Everything on that list is decoded by
Flutter with no extra dependency, which is why the list stops there: a video
decoder is a large thing to carry for a card the height of one note.

- **At most 512 KB.** Checked before the bytes are kept, not after.
- **Design for a wide strip.** The card is exactly one note card: full width,
  about 80dp tall. The picture fills it, cropped to cover, with a scrim on
  the leading edge so the label and title stay legible.
- The file is cached on the device under a name taken from its contents, so a
  new picture replaces the old one on screen straight away; the old file is
  deleted, and the last one goes when the campaign ends.
- **Save `banner.json` as UTF-8.** The app reads it as UTF-8 whatever the
  server's `Content-Type` says, and ignores a byte-order mark.
- **A card whose picture cannot be fetched is shown in words.** Its `title`
  (and `body`) are drawn on the plain card instead, so write a title that
  stands on its own even for a picture-led campaign. (It used to be hidden
  altogether, which on a network that blocks the picture's host meant the
  card never appeared.)

## When nothing appears

By design, all of these are the same outcome — no card, no gap, no
placeholder, no error:

- no `banner.json` (a 404 or 410) — this is the one answer that takes a card
  down; any other failure below leaves the last card in place until it ages
  out
- a file that is not valid JSON, or has no `id` or `title`
- an HTML error page from a captive portal, a filter or a proxy, or a 403 or
  5xx from the host
- a picture that is missing, too large, or not a picture
- the device is offline, or has been for more than 48 hours (the card only
  shows while the last **successful** fetch is recent — an old campaign must
  not live on in the timeline of a phone that has been off the network)
- the card's dates have passed, or it is for another language
- the reader hid it in the last 24 hours (while hiding is on — see below)

## Hiding a card

**Currently off.** Since 1.93.2 the card has no close button and stored
dismissals are not applied, so every phone shows the card while its display is
being tested. `NexSponsorService.dismissibleByDefault` turns it back on; the
rules below then apply again unchanged.

The close button means **not now**, not never. A dismissal is recorded against
the card's `id` with the time it happened, and holds for 24 hours — so it is
gone for the rest of the session and the evening after it, however many times
Android restarts the app in between, and back the next day if the campaign is
still running.

It used to mean never: one tap and that card was gone from that phone for
good. That is more than anyone intends by a close button, and for the one card
paying for a free app it is an expensive thing to get wrong.

Dismissals that have run out are dropped the next time one is recorded, so the
stored map holds what is still in force and not a row per campaign this phone
has ever seen.

## Cadence

Checked at most once a day. A failed request deliberately does **not** record
the attempt, so the next launch tries again rather than waiting out the day.
