# Several attachments on one note: proposal

Status: **decided, scheduled for 2.0.** Written at the owner's request in
1.93.2, so the work can start from a decided shape later. In 1.93.3 the
owner approved the shape below, with two changes from the first draft, and
the work was moved to 2.0 to keep the release close:

- **The note's own file stays where it is.** It is not copied into the new
  table.
- **Sync of attachments waits for media sync (W1.3).**

## What is asked

- **A photo note can hold several photos.**
- **A file note can hold several files.**
- **A text note can carry a photo or a file.**

## Is it worth doing

Yes. "A note with a few photos" is one of the most common capture shapes:
- a receipt and its invoice;
- three angles of something broken;
- the pages of a document.

Today the user has to make one note per picture and tie them together with a
thread, which is the right tool for a story over time and the wrong one for
"these belong to each other".

It is not a small change. Every note holds **at most one media file** today:
the `media_uri`, `media_hash` and `duration_ms` columns on `notes`. That
assumption runs through every part of the app:

- capture;
- the card;
- the detail sheet;
- copy and share;
- search, through the OCR and transcript text;
- the export archive;
- the full backup;
- media garbage collection;
- sync's change tracking;
- the widget snapshot.

The design below keeps that assumption true for every existing note: no
existing row is rewritten, and no file moves.

## The shape

### Data

A new table. It is not more columns on `notes`, and not new note types:

```sql
CREATE TABLE note_attachments (
  id          TEXT PRIMARY KEY NOT NULL,   -- UUIDv7, like every row
  note_id     TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
  position    INTEGER NOT NULL,            -- 1 first; 0 is the note's own file
  kind        TEXT NOT NULL,               -- photo | voice | file
  media_uri   TEXT NOT NULL,
  media_hash  TEXT NOT NULL,               -- content address, as today
  mime_type   TEXT,
  duration_ms INTEGER,
  caption     TEXT,                        -- each picture can say what it is
  ocr_text    TEXT,                        -- derived text belongs to its file
  transcript_text TEXT,
  created_at  TEXT NOT NULL,
  updated_at  TEXT NOT NULL,
  deleted_at  TEXT,                        -- tombstone, for sync later
  device_id   TEXT NOT NULL,
  rev         INTEGER NOT NULL,
  sync_state  TEXT NOT NULL
);
CREATE INDEX idx_attachments_note ON note_attachments(note_id, position);
```

- **The note's type stays what it is.** A photo note with three photos is
  still a photo note, and a text note with a picture is still a text note.
  Types decide how a note reads, and attachments are what it carries.
- **The note's own file is attachment 0, where it already is.** Its
  `media_uri`, `media_hash`, caption, OCR and transcript stay on `notes`,
  written by the code that writes them today. The new table holds only the
  files *after* the first, from position 1. A text note has no file of its
  own, so its attachments all live in the table, also from position 1.

  This replaced the first draft, which copied every existing file into the
  table as attachment 0 and kept both copies in step. It is decided this way
  for three reasons:
  - **No migration.** The upgrade only creates an empty table, so no
    existing library is rewritten.
  - **One home per fact.** Nothing is stored twice, so nothing can drift.
  - **Older builds keep working.** An older build, or an export reader,
    sees exactly the first file it sees today.
- **Reading a note's files** is "the note's own file, if any, then the
  table's rows by position". One repository method answers it, and every
  screen asks that method instead of reading `media_uri` directly.
- **Content-addressed media stays as it is.** The same photo attached twice
  is still one file on disk, and garbage collection counts references across
  both `notes` and `note_attachments`.

### Sync and backup

- **The full backup needs no change for the rows.** It copies
  `nex.sqlite`, so the table rides along. The media it packs is chosen by
  reference, so that query gains the new table.
- **The export archive (v3) carries the table.** An older build importing a
  v3 archive takes the note's own file and says how many it left out.
- **Sync waits for media sync (W1.3).** Today's sync carries a note's text
  and tags and no files at all, nor captions, OCR or transcripts. Syncing
  attachment rows before their files would put on the other device a
  reference to a file it does not have.
  - The table is shaped for sync from the start: `rev`, `device_id`, a
    tombstone and `sync_state`, like `commitments` and `threads`.
  - When W1.3 lands, attachments join sync as their own rows. Removing one
    photo from a note is then one change, not an edit of the whole note.
  - At that point the merge rules (`spec/` and the conformance test) gain
    the table. A note deleted on one device and given an attachment on
    another follows the existing rule for tombstones.

### Search and AI

- Each attachment's caption, OCR and transcript text go into the note's FTS
  row and its embedding, so a word in the third photo finds the note.
- The assistant and the brief read the same joined text they read today.

### The interface

- **Capture:**
  - the photo capture gains "add another" before saving;
  - the system picker allows several photos;
  - sharing several images into Nex makes one note, not one per image;
  - the file picker and share-in allow several files.
- **Text note:** an "attach" action in the editor and in the detail sheet
  adds a photo or a file to the note.
- **Card:** the first picture, plus a small `+3` mark.
  - A text note with an attachment shows a paperclip and the count.
  - A file note shows the first file's name and the count.
- **Detail sheet:** a horizontal strip of attachments under the body. A tap
  opens one full screen (photos swipe), and a hold reorders or removes.
  Each item has its own caption and its own OCR or transcript copy button.
- **Copy and share:**
  - Copy follows today's rule: the note's own words first. A note with only
    pictures copies their captions, and then their OCR text.
  - Share sends every file plus the note's text, with metadata stripped from
    photos as today (SEC-08).
- **Widgets and the timeline widget:** the first attachment only, as today.

## Order of work

1. **Data first, behind no UI.** This step is the most sensitive, because it
   touches the database schema and the compatibility of backups. Review it
   with the owner before it starts. It covers:
   - the table, created empty;
   - repository methods, including "a note's files in order";
   - garbage-collection reference counting;
   - export v3, and the media the full backup packs.

   It ships with tests that open an older database, upgrade it, and
   round-trip it through backup and export.
2. **Several photos on a photo note:** capture, the card mark, the detail
   strip and share.
3. **Attachments on a text note.**
4. **Several files on a file note**, and multi-file share-in.
5. **Later:** voice clips as attachments, and per-attachment AI actions.

## What it deliberately does not do

- **Folders or nested notes.** An attachment is a file on a note, not a note
  of its own. If it needs its own tags or reminder, it should be its own note
  in a thread.
- **Mixing kinds as a new note type.** Type stays the reading mode, and
  attachments stay the payload.
