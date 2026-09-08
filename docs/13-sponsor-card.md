# The sponsor card

Nex is free. There is no paid tier, no account, and nothing held back. The
timeline can instead carry **one** card, the size of one note card and marked
`SPONSORED`, whose entire content is a file on a server.

There is no ad network, no identifier and no profile. The request says only
that a copy of Nex asked; the answer is the same for everyone who asks.

## Publishing one

Commit a file named `banner.json` to the root of the releases repository —
the same host the updater already reads:

```
https://raw.githubusercontent.com/sanyzrn/DbsNex-releases/main/banner.json
```

Taking a card down is deleting that file. A 404 is not an error: it is how a
campaign ends, and the app clears its cache when it sees one.

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
| `id` | yes | Remembered when somebody hides the card. **Reusing an id brings a dismissed card back for everyone who hid it** — a new campaign wants a new id. |
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
- The file is cached on the device, replaced in place, and deleted when the
  campaign ends.
- **A card whose picture cannot be fetched is not shown at all.** A banner
  with a hole where its design was is worse than an empty space.

## When nothing appears

By design, all of these are the same outcome — no card, no gap, no
placeholder, no error:

- no `banner.json`, or a 404
- a file that is not valid JSON, or has no `id` or `title`
- an HTML error page from a captive portal or proxy
- a picture that is missing, too large, or not a picture
- the device is offline, or has been for more than 48 hours (the card only
  shows while the last **successful** fetch is recent — an old campaign must
  not live on in the timeline of a phone that has been off the network)
- the card's dates have passed, or it is for another language
- the reader has hidden it

## Cadence

Checked at most once a day. A failed request deliberately does **not** record
the attempt, so the next launch tries again rather than waiting out the day.
