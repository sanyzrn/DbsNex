# Brief: Maintenance, with My car (`maintenance`) — «نگهداری» و «خودروی من»

**Job:** Upgrade (Soon). The code exists; finish and upgrade it. The car
becomes its first-class case.

## Who it is for

Anyone who looks after things that need servicing — above all a car, and
also a boiler, a cooler, an air conditioner, a water filter. The question
is always "when is the next one due, and what did the last one cost?".

## Must have

- **Things to look after**, each with its service history (date, odometer
  or hours, what was done, cost, who did it, notes).
- **Rules for what is due:** every N kilometres *or* every M months,
  whichever comes first (oil change), or by date only (filter). The next
  due is worked out and shown plainly.
- **My car** — a car is a thing with more:
  - odometer readings (a quick "today it reads 84,200");
  - third-party insurance (بیمهٔ شخص ثالث) expiry and technical inspection
    (معاینهٔ فنی) expiry, each with a reminder some days before (default
    14, editable);
  - a fuel log: date, litres, price paid, and which rate it was bought at;
  - the monthly fuel quota: litres used against the quota at each rate, and
    what this month's fuel cost.
- **Fuel rates and quotas are settings the person edits.** They change by
  government decision; never hard-code them as facts. Example values may be
  filled in, clearly marked as examples to check.
- **A service record to hand over:** the car's full history as one text
  («شناسنامهٔ سرویس») to share when selling it.
- **Reminders** for what falls due, in their own words ("Oil change for the
  Pride: 5,000 km since the last one").

## Iran

Jalali dates; tomans; insurance and inspection named as Iranians name them;
the multi-rate fuel quota as described.

## Must not

- Fetch prices or rates; claim a rate is official.
- Give mechanical or legal advice.

## Later (describe in the README, do not build)

Insurance and inspection dates will appear on the app's "due radar".
Describe how they are stored so they can be read from there.
