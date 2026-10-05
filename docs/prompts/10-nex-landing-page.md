# Task: Design and build the Nex product page — one that people remember

You are designing and building the public product page for **Nex**, a capture
app for Android made by **DbsStudio**. It will live at
**`https://DbsStudio.ir/nex/`**. The owner will replace every image you leave
as a placeholder, so your job is the concept, the layout, the motion, the
typography, the copy placement and production-quality code. It is not stock
art.

Read this whole brief before you design anything. Section 3 matters most: it
lists what this page must **not** look like.

---

## 1. What Nex is (read this as the designer, not as a copywriter)

> **Capture in seconds. Find in seconds.**
> «ثبت در چند ثانیه. پیدا کردن در چند ثانیه.»

Nex is the **inbox for your mind**. Most note apps ask, before you may type:
which folder, which title, which template, and then a Save button. By the time
you have answered, the thought is gone. Nex asks nothing. You tap, you type or
speak or shoot, and the note already exists. There is no Save button anywhere
in the app. Organizing happens later, if ever.

> Nex is not a knowledge base, not a project manager, not another Notion or
> Obsidian. It is the fastest possible front door into whatever system you use
> to think.

### The facts the page may use

Each of these is true in the shipping app. Do not invent others.

- **Capture:** text, voice, photo (with crop), any file, checklists and links.
  No Save button: a note exists the moment it has content. Anything shared
  from another app lands the same way. A link shared from a browser becomes a
  link note with its page title.
- **Timeline:** one reverse-chronological stream with no folders, grouped by
  day.
  - Swipe a note to delete it or tag it.
  - Hold a note to pin, copy, edit, remind or delete it, or to select several
    notes and act on them together, with Undo.
- **Find:** full-text search that understands Persian.
  - Arabic and Persian «ي/ی» and «ك/ک» are treated as the same letter.
  - Diacritics and the half-space are ignored.
  - Persian and Latin digits are equivalent.
  - Tag, type and date filters sit beside the search field.
  - A search that matches nothing offers the nearest thing you actually wrote.
- **Organize later:** tags with their own colours, threads that link related
  notes, pins, and a trash that keeps deleted notes for 30 days.
- **Comes back to you:**
  - one-off and repeating reminders;
  - an optional daily nudge;
  - **Recurring**, its own page for things that come round again (rent,
    insurance, a pill every eight hours), with a calendar, a real Persian
    (Jalali) calendar and payment totals.
- **Persian first:** Persian and English, full right-to-left layout, the
  Persian calendar and Persian digits. A note mixing Persian and English lines
  keeps each line's own direction, even while it is being edited.
- **Private by design:**
  - Notes live in a database **on the phone**, not on a server.
  - No account is needed.
  - App lock, and a private vault for passwords, bank cards and private
    messages. The vault is kept out of notes, search and AI.
  - Encrypted backup to a folder you choose.
  - "Nothing leaves the phone unless you ask it to."
- **Intelligence, optional and off by default:**
  - transcription, OCR, summaries and suggested tags;
  - an assistant you can talk to about your own notes, which cites them;
  - it runs only with a provider you choose, or a model on the device;
  - every disclosure to a provider is logged where you can read it.
- **Home-screen widgets:**
  - a capture row;
  - a timeline;
  - a smart recap.

  There is also a Quick Settings tile.
- **Platform:** Android 7.0 and later. Distributed through **Cafe Bazaar
  (کافه‌بازار)** and **Myket (مایکت)**. It is **not on Google Play**: do not
  show a Play badge.
- **Maker:** DbsStudio, at `https://DbsStudio.ir`.

### The brand

- **Mark:** an **octopus**. Its line is
  **"One mind. A thousand connections." / «یک ذهن، هزار ارتباط.»**
  The app opens with an animation in which the octopus grows from its eyes and
  pulls **six scattered fragments** into its arms: a thought, a voice clip, a
  photo, a link, a checklist and a file. That gesture is the brand's whole
  story: many loose things, held by one calm mind.
- **Wordmark:** "nex", lowercase. The sub-line is "AI Second Memory".
- **Accent:** one blue only.
  - Light: `#0084F7`, with `#006DCC` for strong use.
  - Dark: `#74BCFB`, with `#A7D4FB` for strong use.
- **Neutrals:**
  - Light: background `#F5F6F6`, card `#FFFFFF`, text `#262626`, secondary
    `#5C5C5C`.
  - Dark: background `#131312`, card `#1E1E1E`, text `#F2F2F3`, secondary
    `#ABABAB`.
- **Type:** **Vazirmatn** for Persian and **Inter** for Latin, both SIL OFL.
  Self-host both (section 6).
- **Voice:** calm, plain and specific. Short sentences. Polite «شما» in
  Persian. No hype words: "revolutionary", "supercharge", "unleash",
  "seamless", "next-level", "game-changer", «انقلابی», «بی‌نظیر».

---

## 2. The audience and the one job of the page

Persian-speaking Android users first, and English speakers second. They are
people with a full head: students, freelancers, parents, people who write
notes to themselves in a chat app because their notes app is too slow.

The page has **one job**: in under ten seconds, a visitor should *feel* how
little Nex asks of them, and then install it. Every section either makes that
feeling stronger or answers an objection (privacy, Persian support, "is it
free", "does it work offline"). Cut anything that does neither.

---

## 3. Make it unmistakably not an "AI-generated landing page"

Visitors have seen the same page a thousand times. **None of the following may
appear.** Treat this as a checklist you verify before delivering.

- ❌ A centred hero with a headline, a sub-line, two buttons ("Get started" /
  "Learn more") and a tilted phone mockup floating on a gradient blob.
- ❌ Purple, violet or blue-to-pink gradients; aurora or mesh-gradient
  backgrounds; glowing orbs; noise-grain overlays as decoration.
- ❌ Glassmorphism cards; frosted panels on blurred blobs.
- ❌ The three-column "feature grid": an icon in a rounded square, a bold
  title, two lines of grey text, repeated six or nine times.
- ❌ Bento grids.
- ❌ Logo walls, "Trusted by" strips, invented testimonials, star ratings,
  invented download counts, or any other social proof that does not exist.
- ❌ Emoji as icons. Generic stock icon sets used as decoration.
- ❌ Auto-playing carousels and sliders.
- ❌ "✨ AI-powered" badges or sparkle icons. Intelligence is one quiet section,
  and it is off by default.
- ❌ Fake browser chrome, fake terminal windows, or a dashboard screenshot with
  lorem ipsum.
- ❌ Scroll-jacking, parallax for its own sake, a cursor-follow glow, or
  confetti.
- ❌ Copy that could describe any app: "Your all-in-one productivity
  workspace", "Organize your life", «همه‌چیز در یک جا».

Ask yourself of every section: *could this section appear unchanged on the
page of a different app?* If yes, redesign it.

---

## 4. The concept: the page behaves like Nex

The memorable idea is that **the page itself is the product's argument**. It
asks nothing of the visitor, it captures instantly, and it holds scattered
things together the way the octopus does. Build these four signature moments.
They are the reason someone will remember this page.

### 4.1 The hero *is* a capture field

There is no headline-and-buttons hero. The first screen is almost empty, like
the inside of Nex:

- At the top, small: the "nex" wordmark and a language switch (فا / EN).
- The headline, set very large in Vazirmatn:
  «ثبت در چند ثانیه. پیدا کردن در چند ثانیه.»
- Under it, a **real, focused text field** with the placeholder
  «هر چه می‌خواهید بنویسید…» / "Write anything…". It has no label, no button
  and no Save.
- **The interaction:**
  - When the visitor types and presses Enter, or simply pauses for 1.2
    seconds, the text becomes a **note card** that drops softly into a short
    timeline below the field, under a day heading «امروز».
  - The card shows the time, «همین حالا», and a tiny line:
    «ذخیره شد — بدون دکمهٔ ذخیره.»
  - Voice and photo chips sit beside the field as visual hints only. They do
    not need to work.
- **Privacy is part of the demo.** The demo notes live only in this browser
  (`localStorage`, wrapped in try/catch) and are **never sent anywhere**. Say
  so in one line under the field: «این‌ها فقط در همین مرورگر می‌مانند.»
- **Without JavaScript,** the field still shows, a static example card sits
  below it, and the page still reads well.
- **Mobile:** the field is the first thing under the headline, thumb-reachable,
  and does not trigger an unwanted zoom (font-size at least 16 px).

The primary download action is **not** a big button in the hero. It is a calm
text link in the top bar («دریافت نکس» / "Get Nex") that jumps to the download
section. The field is the invitation.

### 4.2 "There is no *where*. There is only *now*."

A short scroll sequence about the problem:

1. As the visitor scrolls in, four "questions" from other note apps appear one
   by one, drawn as **plain, slightly dull system UI**:
   - a folder picker: «کجا ذخیره شود؟»;
   - a title field: «عنوان یادداشت»;
   - a template chooser;
   - a grey **Save** button.
2. As the scroll continues, these pieces lose their meaning and **fall away
   or fold flat**, one by one, leaving a single blinking caret.
3. Then the line: «هیچ "کجا"یی در کار نیست. فقط "الان".» /
   "There is no *where*. There is only *now*."

This must be driven by scroll position with CSS (scroll-driven animations
where supported, with an `IntersectionObserver` fallback). It must **never**
hijack or slow scrolling. With reduced motion, show the final state statically.

### 4.3 One mind, a thousand connections

This is the brand moment, and it echoes the app's opening animation.

- Six **fragments** are scattered loosely across the section:
  - a line of handwritten-looking text («ایدهٔ اسم کافه…»);
  - a voice waveform;
  - a photo tile;
  - a link chip (`example.com`);
  - a small checklist (three items, one ticked);
  - a file chip (`قرارداد.pdf`).
- As the section scrolls into the centre, the fragments drift and **settle
  into the arms of the octopus mark**. Use the placeholder for it
  (section 5). If it has not been replaced, draw a simple placeholder ring
  with six anchor points.
- The line underneath: «یک ذهن، هزار ارتباط.» / "One mind. A thousand
  connections."
- Each fragment, once settled, reveals one plain sentence about that capture
  type. This replaces the forbidden feature grid: the content is the same, but
  it is held by one gesture instead of laid out in boxes.
- With reduced motion, the fragments start in their settled positions.

### 4.4 Search that understands Persian (interactive)

A small, honest demo of something no generic note app does:

- A search field pre-filled with `كتاب`, written with an **Arabic kaf**.
- Below it, three demo notes. The one containing «کتاب‌های امسال», written
  with a **Persian kaf** and a half-space, is highlighted as a match.
- A one-line caption: «ك و ک، ي و ی، اعداد فارسی و لاتین، نیم‌فاصله — همه یکی
  حساب می‌شوند.»
- The visitor can type. Implement a tiny client-side fold for the demo:
  - map `ي→ی` and `ك→ک`;
  - strip diacritics `[ً-ْ]`;
  - remove ZWNJ `‌` and tatweel `ـ`;
  - map Persian and Arabic-Indic digits to ASCII.

  Matching against the demo notes, show «نزدیک‌ترین یادداشت» when nothing
  matches.

---

## 5. Placeholders: exact list and how they must look

Every image is a placeholder that the owner will replace. Make replacement
trivial and impossible to get wrong.

- **One folder** holds them all: `assets/img/`.
- **Each placeholder is a real file** at its final path and size. Use a
  lightweight SVG, or a tiny PNG for raster slots. Draw it as a neutral box
  with diagonal hatching in the theme's border colour, centred text showing
  its **file name and pixel size**, and a one-line description of what goes
  there, for example `screen-timeline-fa.png — 1080×2340 — timeline with
  pinned notes, Persian UI`. When the owner drops a real file with the same
  name over it, it appears with no code change.
- **Markup:** every `<img>` has explicit `width` and `height` (no layout
  shift), `loading="lazy"` except the first screen, `decoding="async"`, and a
  meaningful `alt` in the page's language.
- **Manifest:** add `assets/img/PLACEHOLDERS.md`. It is a table of every slot
  with file name, size, aspect ratio, format, where it appears, and what the
  picture should show. Write it so the owner can brief a designer from it
  directly.

**Required slots** (adjust sizes only if your layout truly needs it, and
update the manifest):

| File | Size | Use |
|---|---|---|
| `octopus-mark.svg` | vector, square | The octopus in §4.3, with six arm anchor points marked in a comment |
| `logo-wordmark-light.svg`, `logo-wordmark-dark.svg` | vector | Top bar and footer |
| `screen-timeline-fa.png` / `-en.png` | 1080×2340 | The timeline with day headings and pinned notes |
| `screen-capture-fa.png` / `-en.png` | 1080×2340 | The capture sheet, mid-typing |
| `screen-search-fa.png` / `-en.png` | 1080×2340 | Search with filter chips |
| `screen-recurring-fa.png` / `-en.png` | 1080×2340 | The Recurring calendar |
| `screen-vault-fa.png` / `-en.png` | 1080×2340 | The private vault (blurred values) |
| `screen-widgets-fa.png` | 1080×2340 | The home screen with Nex widgets |
| `photo-hands.jpg` | 1600×1200 | Optional: a real moment of quick capture (hand, phone, street or kitchen) |
| `badge-bazaar.svg`, `badge-myket.svg` | per the stores' brand kits | Download section |
| `og-image.png` | 1200×630 | The social share preview |
| `favicon.svg`, `apple-touch-icon.png` (180×180), `icon-512.png` | — | Icons |

**Phone screens:**
- Do not wrap screenshots in a glossy 3D phone mockup. Show them flat, with
  the device's corner radius and a hairline border, or in a thin neutral frame
  that you draw in CSS.
- Show `-fa` images on the Persian page and `-en` images on the English page.

---

## 6. Structure of the whole page

The order below is a strong suggestion. Keep the four signature moments of §4
and the download section; you may merge or reorder the rest if the story reads
better.

1. **Top bar.** Wordmark, language switch, «دریافت نکس». Sticky, thin, and
   transparent until scrolled.
2. **Hero = capture field** (§4.1).
3. **The problem** (§4.2).
4. **One mind, a thousand connections** (§4.3), covering the capture types.
5. **Find** (§4.4), plus one line about filters and the nearest match.
6. **Persian first.**
   - Set this section *typographically*, with no icons: a large mixed-direction
     paragraph («جلسه با Ali دربارهٔ API ساعت ۱۰») showing each line keeping
     its own direction;
   - a Jalali date next to its Gregorian twin;
   - Persian digits.
   - Headline: «فارسی، از اول.» / "Persian, from the start."
7. **Comes back to you.**
   - Reminders and Recurring, shown as a **single calendar strip** (one Jalali
     week) with three real-looking items: rent, insurance, «قرص ساعت ۸».
   - Include one screenshot slot.
8. **Private by design.** The quietest, most serious section.
   - Plain statements, no icons:
     - «یادداشت‌ها روی گوشی خودتان می‌مانند.»
     - «حساب کاربری لازم نیست.»
     - «بخش خصوصی جدا از یادداشت‌ها، جستجو و هوش مصنوعی.»
     - «پشتیبان رمزگذاری‌شده، در پوشه‌ای که خودتان انتخاب می‌کنید.»
   - Visual idea: a phone placeholder with a thin closed outline around it, and
     **nothing** going out of it.
9. **Intelligence, if you want it.**
   - Small and honest: off by default, your provider or an on-device model, and
     a log of what was sent.
   - One screenshot slot.
   - No sparkles.
10. **On your home screen.** Widgets and the Quick Settings tile, using the
    `screen-widgets-fa.png` slot.
11. **Screens.** A **contact-sheet strip**: all screenshot slots in a single
    horizontal row that the visitor scrolls *by hand* (scroll-snap, visible
    scrollbar on desktop, keyboard-scrollable). Not a carousel. Each has a
    caption.
12. **Download.**
    - Bazaar and Myket badges (placeholders) linking to `#` with a clear
      `TODO` comment for the real URLs.
    - Note the requirement: «اندروید ۷ به بالا».
    - Say that it is free to install, but only if the owner confirms. Leave a
      `<!-- TODO owner: price wording -->` comment and neutral text in the
      meantime.
    - The current version number, read from one constant at the top of the
      script or the HTML. Default it to `1.93.4`.
13. **Short FAQ.** Five questions at most, as `<details>` elements:
    - آیا بدون اینترنت کار می‌کند؟ (Yes. Everything except the optional AI
      works offline.)
    - یادداشت‌هایم کجا ذخیره می‌شوند؟ (On your phone.)
    - چرا در گوگل‌پلی نیست؟ (Distribution is through Bazaar and Myket.)
    - آیا هوش مصنوعی اجباری است؟ (No, it is off by default.)
    - پشتیبان‌گیری چطور است؟ (An encrypted backup to a folder you choose.)
14. **Footer.**
    - DbsStudio with a link, the year, and a link to the privacy statement
      (`#privacy`, with a TODO comment).
    - The octopus line once more, small.

---

## 7. Visual direction: make deliberate, specific choices

### Typography is the hero
- Huge Persian display type: Vazirmatn at weight 800–900, with tight but legible
  line-height for display (about 1.1) and generous line-height for body (about
  1.8 for Persian).
- Pair it with small, precise UI-sized labels.
- Use a strong size contrast: display 8–14 vw on desktop, clamped. Body 17–19
  px.

### Colour
- One accent blue on neutrals, and nothing else.
- Light and dark themes both follow `prefers-color-scheme`, with a manual
  toggle remembered in `localStorage`.
- The accent marks interactive things and the single most important word of a
  section, never decoration.

### Composition
- Use asymmetry and an editorial grid: wide margins, content that sometimes
  breaks the column, and large quiet areas. Think of a well-set Persian
  magazine or a museum label, not a SaaS template.
- RTL is the default reading direction. Lay out from the right, and make sure
  the English page mirrors correctly.

### Texture and detail
- Allowed: hairline rules; the note-card shape from the app (radius 16–20
  px, soft 1 px border, no heavy shadow); and day headings like the app's.
- Optional: a very subtle paper-like warmth in light mode, using the app's
  "comfort" tones `#EFE7D8` and `#FBF6EC`, for the problem section only.

### Motion
- Few movements, and every one of them meaning something: the capture drop
  (§4.1), the questions falling away (§4.2) and the fragments settling (§4.3).
- Use spring-like easing (`cubic-bezier(.2,.8,.2,1)`), durations of 200–600 ms,
  and nothing that loops forever.
- Respect `prefers-reduced-motion` everywhere.

### Iconography
- Very few icons, drawn as simple 1.5 px strokes in SVG, inline, matching the
  app's outlined style.

Before coding, write a short **design rationale** (one page, in
`DESIGN.md`):
- the grid;
- the type scale;
- the colour usage;
- the motion list;
- for each section, the one thing a visitor should take away from it, and how
  the design avoids the clichés in §3.

---

## 8. Copy

- **The Persian page is the original.** Write the English as a natural
  English version, not a word-for-word translation.
- Keep every user-visible string in one place: `i18n/fa.json` and
  `i18n/en.json`, or two static HTML files generated from one template, so the
  owner can edit the wording without touching the layout.
- Use only the facts in §1. Where you need a number or claim that is not
  there, write `[[TODO: …]]` instead of inventing one.
- **Persian typography:**
  - real half-spaces (ZWNJ, U+200C) in «می‌خواهید», «یادداشت‌ها»,
    «کتاب‌ها»;
  - Persian digits in Persian text;
  - «» quotation marks;
  - never a Latin comma or question mark inside Persian text («،» «؟»).

---

## 9. Technical requirements

- **Stack:** static HTML, CSS and vanilla JavaScript. No framework and no
  build step are required. It must work by copying the folder to
  `DbsStudio.ir/nex/`.
  - If you choose a tiny build step (for example to generate the two language
    pages from one template), commit its output too and document it in
    `README.md`.
- **Routing:**
  - `/nex/` is Persian (`<html lang="fa" dir="rtl">`);
  - `/nex/en/` is English (`lang="en" dir="ltr"`);
  - add `hreflang` links between them;
  - the language switch preserves the current section anchor.
- **No third-party requests at runtime.**
  - No Google Fonts, analytics, CDNs, trackers or embeds. This is a privacy
    product, and several of these services are unreliable for visitors in
    Iran.
  - Self-host the WOFF2 fonts, subset to the characters used, with
    `font-display: swap`.
  - Include the font licences in `/fonts/LICENSES/`.
- **Performance budget**, on a mid-range Android phone over slow 4G:
  - LCP under 2.0 s, CLS under 0.02 and INP under 200 ms;
  - total JavaScript under 30 KB gzipped;
  - CSS under 40 KB gzipped;
  - the first screen must not wait on any image.
- **Accessibility:** WCAG 2.2 AA.
  - Contrast is checked in both themes.
  - The page is fully usable with the keyboard, with visible focus rings.
  - Interactive demos have labels.
  - Every animation has a reduced-motion equivalent.
  - The page works at 200% zoom and 320 px width.
  - Headings are in order and landmarks are used.
- **Progressive enhancement:** without JavaScript, every section reads
  correctly in its final state, and the demos show static examples.
- **SEO and sharing:**
  - a title and meta description per language;
  - Open Graph and Twitter cards using `og-image.png`;
  - a canonical URL;
  - `SoftwareApplication` JSON-LD with `operatingSystem: "Android 7.0+"`,
    `applicationCategory: "ProductivityApplication"` and no invented ratings;
  - `robots.txt` and `sitemap.xml` for both pages.
- **Browsers:** current Chrome, Samsung Internet, Firefox and Safari. Mobile
  first: design at 360 px wide before desktop.

---

## 10. What to deliver

One folder (or zip) named `nex-site/`:

```
nex-site/
├── index.html                 # Persian
├── en/index.html              # English
├── css/site.css
├── js/site.js                 # demos, theme toggle, language switch
├── i18n/fa.json, en.json      # all copy, if you template it
├── fonts/                     # Vazirmatn, Inter (woff2, subset) + LICENSES/
├── assets/img/                # every placeholder at its final name and size
│   └── PLACEHOLDERS.md        # the replacement manifest (§5)
├── favicon.svg, apple-touch-icon.png, icon-512.png, og-image.png
├── robots.txt, sitemap.xml
├── DESIGN.md                  # rationale (§7) + the §3 checklist, ticked
└── README.md                  # how to deploy, how to replace images,
                               # where the TODOs are, how to edit copy
```

Before you hand it over:

1. **Run the §3 checklist** and tick every line in `DESIGN.md`, with a
   sentence each on how the page avoids it.
2. **Run Lighthouse** (mobile) on both pages and paste the scores into
   `README.md`. If you cannot run it, say so; do not guess numbers.
3. **Test the four signature moments** with JavaScript on, JavaScript off and
   reduced motion, in both languages and both themes. List what you checked.
4. **List every `TODO`** for the owner in `README.md`: store URLs, price
   wording, privacy statement link, and any claim you were unsure of.

If something in this brief conflicts with good accessibility or with what is
true about the app, choose accessibility and truth, and say so in `DESIGN.md`.
