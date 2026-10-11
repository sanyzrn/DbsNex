# Task: The Nex page — a site that is one day of notes

You are designing and building the public page for **Nex**, a quick-capture
notes app for Android by **DbsStudio**. It will live at
**`https://DbsStudio.ir/nex/`**. It should be short, minimal and unmistakably
its own. Most of the craft is left to you. This brief gives you the idea, the
facts and a few hard limits, and nothing more.

---

## The idea

**The website is a Nex timeline.**

It is not a page *about* the app with screenshots of a timeline. The page
itself is the timeline: a single narrow column of note cards under day
headings, read top to bottom, exactly as the app shows notes. Each card is one
thing the visitor needs to know, written as a note someone jotted to
themselves. The visitor understands the app by reading it in the app's own
form.

- **The pinned note at the top is the download.** Pinned notes sit first in
  Nex, so the page's one call to action is simply the note that is pinned.
  There is no hero, no headline block and no button row.
- **Under «امروز» (Today)** are a handful of notes, five to seven at most. Each
  is a different kind of note, and together they cover what Nex is:
  - a text note: what Nex is in one line;
  - a voice note, as a waveform: the line you would say out loud;
  - a checklist: what it does, a few items, some ticked;
  - a photo note: one screenshot placeholder;
  - a link note;
  - and so on.

  The form of each card carries part of the message. Choose which fact goes on
  which kind of note.
- **One card is real.** It is an empty note where the visitor can type. What
  they write becomes a card in the timeline at once, with no Save button,
  stored only in their own browser. This is the whole argument for the app in
  one gesture.
- **Scrolling down goes back in time.** Under «دیروز» (Yesterday) and older
  days, the notes quietly answer the doubts a visitor has: privacy, Persian,
  offline use, where to get it. The last day heading is the first day: the
  maker, DbsStudio, and the line «یک ذهن، هزار ارتباط.»

It should be over in about three phone screens. If a card does not earn its
place, delete it.

What these cards look like is up to you: their wording and voice, how much
the page should resemble the real app, motion, and any small surprises. The
first two seconds should make someone smile, and the last card should make
them want to install it.

---

## Facts you may use (and nothing else)

- **Capture.** Text, voice, photo, any file, checklists and links, and things
  shared from other apps. There is no Save button anywhere: a note exists the
  moment it has content.
- **One timeline.** No folders. Tags, threads, pins and reminders are there
  for later, if you want them.
- **Search that understands Persian.** «ك/ک» and «ي/ی», the half-space and
  Persian or Latin digits are all treated as the same, and a search with no
  match offers the closest thing you wrote.
- **Recurring.** Rent, insurance, a pill every eight hours, with a real
  Persian calendar.
- **Private.** Notes stay on the phone. There is no account. There is an app
  lock, and a private vault for passwords, cards and messages. Backups are
  encrypted, to a folder you choose. Nothing leaves the phone unless you ask
  it to.
- **Intelligence is optional and off by default.** It works with a provider
  you choose or a model on the phone, and every request sent out is logged
  for you to read.
- **Persian first.** Full right-to-left layout, Jalali dates and Persian
  digits. A line mixing Persian and English keeps its direction.
- **Platform and distribution.** Android 7.0 and later, through **Cafe
  Bazaar** and **Myket**. It is **not on Google Play.**
- **Brand.**
  - The mark is an octopus: «یک ذهن، هزار ارتباط» / "One mind. A thousand
    connections."
  - The wordmark is a lowercase "nex".
  - One blue: `#0084F7` in light mode, `#74BCFB` in dark mode, on quiet
    neutrals.
  - Type is **Vazirmatn** and **Inter**, both self-hosted.

If you need a number or a claim that is not listed here, write
`[[TODO: …]]`. Never invent one: no ratings, download counts or testimonials.

---

## Hard limits

- **Persian is the original.** `/nex/` is Persian and right-to-left; `/nex/en/`
  is a natural English version, not a literal translation. Use real
  half-spaces, Persian digits and «».
- **Avoid the generic landing page:**
  - a centred hero with two buttons;
  - gradients and glowing blobs;
  - glass effects;
  - feature grids and bento boxes;
  - sparkle "AI" badges;
  - emoji icons;
  - carousels;
  - scroll-jacking.
- **Static and private:**
  - HTML, CSS and a little vanilla JavaScript; the folder deploys by copying.
  - Nothing is loaded from any third party: no fonts, analytics or CDNs.
    Several of these are unreliable from Iran, and it is a privacy product.
- **It works everywhere:**
  - without JavaScript, where the cards are simply static;
  - with reduced motion;
  - at 320 px width;
  - in light and dark mode;
  - from the keyboard.

  It should be fast on a mid-range Android phone.
- **Placeholders are easy to replace.**
  - Every image lives in `assets/img/` at its final file name and size, drawn
    as a plain hatched box that names itself.
  - `assets/img/PLACEHOLDERS.md` lists each slot: what it should show, its
    size and where it appears.
  - Store links are `#`, each with a `TODO`.

---

## Deliver

- A `nex-site/` folder ready to upload, containing:
  - the two pages;
  - CSS, JavaScript and fonts (with their licences);
  - the placeholders and their manifest;
  - icons and an OG image;
  - `robots.txt` and `sitemap.xml`.
- A short `README.md` covering:
  - how to deploy;
  - how to edit the copy and replace images;
  - every `TODO` left for the owner;
  - in a few lines, the choices you made and why.
