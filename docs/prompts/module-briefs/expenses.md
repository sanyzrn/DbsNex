# Brief: Expenses (`expenses`) — «هزینه‌ها»

**Job:** Upgrade (Soon). The code exists; finish and upgrade it.

## Who it is for

Someone who wants to know where the month's money went, without a
spreadsheet and without giving a bank app their data. With prices rising
fast, "how much did we spend on groceries this month, compared with last"
is the question.

## Must have

- **A payment written down in seconds:** amount, category, and today by
  default. Everything else optional. The amount field takes Persian or
  English digits and shows grouping as it is typed.
- **The month at a glance:** total, total per category, and the change
  from last month per category ("groceries +18%"). A month is a Jalali
  month in Persian.
- **Budgets per category, calm:** how much is left, and a quiet mark when a
  budget is passed. No red alarms, no guilt.
- **Recurring payments** (rent, internet, a subscription): kept as
  templates; on their day the module offers "log this month's" with one
  tap. It never logs one by itself.
- **Income** as an optional second kind, so the month can show what is
  left.
- **Find a payment:** by words, category or amount range.
- **Share a month** as text: the totals per category, for a partner or a
  family group.

## Iran

Tomans and rials as the app's money modules show them; Jalali months;
categories that fit an Iranian household out of the box (groceries, rent,
bills, transport, health, children, gifts), editable.

## Must not

- Read SMS, connect to banks or fetch anything.
- Tell anyone how to spend.

## Later (describe in the README, do not build)

The recurring payments will feed the app's Recurring page and a "due
radar". Describe the record shape a recurring template has, so it can be
read from there.
