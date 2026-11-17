# Brief: Asset book (`assets`) — «دفتر دارایی»

**Job:** New. There is no code. It is a separate module from Gold Check
(`gold`), which works out a single purchase or sale; this one keeps what
you own. Do not import from `gold/`: copy any small calculation you need,
and say so.

## Who it is for

Someone in Iran who keeps savings as gold, coins and foreign currency,
spread between home, a bank box and several online platforms, with
inflation around two-thirds a year, and who wants one private place that
says what it is all worth.

## Must have

- **Holdings,** each with a kind:
  - gold by weight and fineness (750 = 18 karat, and others);
  - coins: full Emami, half, quarter, gram coin (سکهٔ گرمی), and others;
  - currency: dollar, euro, dirham, lira and others;
  - other, with a name.
- For each: quantity, purchase date, price paid per unit, and where it is
  kept (home, bank box, a platform the person names).
- **Prices typed in by the person,** per kind, with their date ("today's
  price"), and kept as a history. Never fetched. The screen says when each
  price was last updated.
- **What it is worth:** the total at the last prices, profit or loss per
  holding and overall, and the total expressed **in grams of 18-karat gold
  and in dollars** (from the prices entered), not only in tomans.
- **Goals:** "reach 10 grams", with progress.
- **Private by default:** amounts hidden until tapped, and the screen kept
  out of screenshots and the app switcher (`NexSecureWindow`).

## Must not

- Fetch prices, link to platforms, or advise buying or selling.

## Platform requests to expect

Live prices need the network, which modules do not have: ask for it, and
explain that the module is complete without it.
