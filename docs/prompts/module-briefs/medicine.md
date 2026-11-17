# Brief: Medicine, a home pharmacy (`medicine`) — «داروها» و «داروخانهٔ خانه»

**Job:** Upgrade (Soon). The code exists; finish and upgrade it.

## Who it is for

A household that keeps medicines for several people, where some medicines
are hard to find and getting dearer. The questions: "when do I take it",
"when will it run out", "what in the cabinet has expired", and "where did I
find it last time, and for how much".

## Must have

- **People:** each medicine belongs to someone in the household (me by
  default).
- **Schedule and reminders** that do not get missed: times per day, days
  of the week or every N days, start and end dates. Each reminder names the
  medicine and the person. Taken / skipped is logged with one tap.
- **Stock:** how many are left, how many are used per day from the
  schedule, and so **"runs out in about N days"**, with an early warning
  (default 10 days before, editable): "start looking for it now".
- **Boxes and expiry:** each box's expiry date; a list of what expires
  soon or has expired.
- **Where and how much:** a small log per medicine — where it was found,
  the price, the date — so the next search starts somewhere.
- **Hide on screen:** names and schedules are health data; offer to keep the
  screen out of screenshots and the app switcher (`NexSecureWindow`).

## Iran

Jalali dates; tomans; the reality of shortages, written calmly ("hard to
find lately" as a note the person can set, not a claim the module makes).

## Must not

- Recommend, change or check doses, or say anything about interactions or
  substitutes.
- Fetch anything, or name pharmacies the person did not write.

## Device checklist must include

Reminders after a restart, in Doze, and with the app closed; a missed dose
the next morning. A medicine reminder that does not ring is the worst bug
this module can have.
