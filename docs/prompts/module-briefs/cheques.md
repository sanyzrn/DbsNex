# Brief: Cheques & instalments (`cheques`) — «چک و قسط»

**Job:** New. There is no code; the module's "On the way" entry is
`cheque-manager`. Name the folder and id `cheques`.

## Who it is for

Iranians who give and receive cheques, pay instalments on a purchase or a
loan, and need one place that shows the month's commitments together. In
spring 1405, about one cheque in ten bounced; buy-now-pay-later has
millions of users across a dozen services, and none shows the whole month.

## Must have

- **Cheques, both ways:** incoming and outgoing. Amount, due date (Jalali),
  the other party, bank, serial number, the 16-digit Sayad ID (optional),
  and a note. A status that moves along: written → registered in Sayad →
  handed over → cleared, or bounced, returned, cancelled. Each change keeps
  its date.
- **Instalment plans:** a purchase or a loan paid in parts — total, number
  of instalments, first due date, interval (monthly by default), and the
  schedule worked out from them, each instalment ticked when paid. A
  one-tap "4 monthly instalments" template for buy-now-pay-later.
- **The month:** what is to be paid and what is to be received this Jalali
  month, with totals and what is left after them.
- **A cash calendar:** the month's days, and the days where more goes out
  than comes in marked plainly.
- **Overdue and bounced** in a section of their own at the top, never mixed
  into the rest.
- **Reminders** some days before each due date (default 3, editable) and on
  the day, naming the cheque or instalment and the amount.
- **Hide amounts** on screen, one tap.

## Must not

- Connect to Sayad, a bank, or anything else.
- Give legal advice on a bounced cheque.
- Store banking passwords or card details.

## Later (describe in the README, do not build)

The app's Recurring page and a future "due radar" will read these due
dates. Describe the record shapes clearly enough for that.
