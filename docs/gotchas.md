## Gotchas encountered

### G1 — Translation table does not cover every product category
The `product_category_name_translation` lookup is missing rows for some categories that appear in the products table. A plain `LEFT JOIN` leaves nulls on real product rows, which then collapse into a silent null bucket in every category visual.

**Fix:** fall back to the original name rather than dropping to null.

```sql
COALESCE(t.product_category_name_english, p.product_category_name)
```

**Root cause class:** assuming a lookup table is complete because it is *supposed* to be. Verify coverage with an anti-join before trusting any reference join.

**Confirmed by profiling:** exactly 2 categories have no translation — `portateis_cozinha_e_preparadores_de_alimentos` (10 products) and `pc_gamer` (3 products). Zero translation rows match no product, so the gap is one-way.

### G2 — Encoding must be stated explicitly on load
psql on Windows negotiates client encoding from the console code page, typically WIN1252. The Olist files are UTF-8 and full of Portuguese (`são paulo`, `condições`, 40k free-text review comments). Without `ENCODING 'UTF8'` on the `\copy`, multi-byte characters are reinterpreted byte-by-byte into mojibake — **with no error raised**. The failure surfaces weeks later as `são paulo` and
`são paulo` appearing as two separate values in a slicer.

**Root cause class:** inheriting an environment default instead of stating a requirement. Handled preemptively; never observed.

### G3 — `count(DISTINCT col)` silently excludes NULLs
`count(DISTINCT product_category_name)` returned 73, which reads like "there are 73 categories" and hides the fact that 610 products have no category at all.

**Idiom:** `count(*) - count(col)` gives the null count for `col`, because `count(*)` counts rows and `count(col)` counts non-null values.

### G4 — Cardinality does not tell you about overlap
Repeatedly tempting and always wrong: comparing two counts (99,441 orders vs 99,440 payment orders) and concluding "one is missing". Two sets of those sizes are equally consistent with zero matches. Only an anti-join answers the question, and it must be run in **both** directions — orphans hide on either side.

### G5 — 610 products carry no category
They cannot be dropped: their order items are real revenue. They need an explicit "Unknown" bucket rather than being allowed to fall into a silent null group in every category visual.

### G6 — When two columns are subtracted, the anomaly may be in either one
A lateness of −147 days looks like a delivery-date problem. It wasn't: the order was purchased 2018-03-06 and delivered 2018-03-09 — a normal three-day delivery against an estimate five months out. The corrupt column was the *estimate*.

**Root cause class:** a derived metric carries no information about which of its inputs is wrong. Always inspect the source columns individually before concluding anything about the difference between them.

### G7 — A metric can be contaminated for one question and clean for another
The same implausible-estimate rows leave the **late rate** completely unaffected (no rule turns a three-day delivery into a late one) while distorting **average days early**. Contamination is per-metric, not per-row. Deciding to drop rows because "the data is bad" throws away rows that were fine for most of what you were going to ask.

### G8 — Verify your verification
A check written to confirm the translation fallback tested `product_category = product_category_pt` and reported 2,058 products, against an expected 13. It looked like a data problem. It was a measurement problem: many Olist categories are spelled identically in Portuguese and English (`audio`, `pet_shop`, `cool_stuff`), so string equality does not mean "no translation was found". The correct test asks whether a translation row *exists*, via `NOT EXISTS` against the lookup.

**Root cause class:** a green result from a query that asks the wrong question is worse than no check at all, because it buys false confidence. When a check returns an unexpected number, suspect the check before suspecting the data.

### G9 — Power Query previews are samples, not the data
The editor streams roughly the first 1,000 rows and renders those. The status bar shows `999+`, not a row count — it is designed not to know. Column profiling also defaults to **top 1000 rows**; a 0% null rate there says nothing about the other 111,650.

**Fixes:** switch profiling to *entire data set* (status bar, bottom left). For an actual row count use Transform → **Count Rows**, read it, then delete the step — it replaces the query with the number.

**Root cause class:** in SQL, "what's on screen" and "what's in the data" are the same. In Power Query they are different by default. Know which one you are looking at.

### G10 — Off-by-one usually means a population difference, not a bug
`Is Late` showed 6,535 true against a Phase 1 baseline of 6,534. The calculation was correct: the SQL baseline had `WHERE order_status = 'delivered'` while Power Query had not yet applied that filter. **Six orders were delivered and then cancelled** (returns or post-delivery refunds), and one of them was late.

Consequence for Phase 4: "late rate" must be defined over **delivered** orders, not over all orders carrying a delivery date.

Without the baselines table this would have shipped as 6,535 and never been noticed.

### G11 — Auto-detected relationships defaulted to bidirectional
Power BI's auto-detect created `Order Items → Orders` and `Orders → Customers` with **both** cross-filter directions on load. Confirming each relationship *exists* is not the same as confirming its *direction*, and the direction is the part auto-detect gets wrong.

**Why it hid:** bidirectional relationships make things appear to work. Nothing errors, every visual populates, numbers look plausible. The damage is ambiguous filter paths that surface later as the same measure disagreeing between pages. It only became visible when a `CROSSFILTER` measure produced no change — because the path it was meant to open was already open for everything.

**Check:** double-click each relationship line and confirm Many-to-one (\*:1) with cross-filter **Single**, one at a time. Do not trust the model diagram at a glance.

### G12 — A measure and a baseline only compare if they cover the same population
`Avg Review Score` returned 4.16 against a recorded baseline of 4.0873 — far too large a gap to be rounding. Neither number was wrong. The baseline covered all 98,673 review rows; the measure covered 95,832 delivered orders, because D4's delivered filter was applied upstream.

This is the third appearance of the same species of problem (see G13 and the cardinality-vs-overlap trap in G4): **filters applied upstream silently move every downstream number.** When a figure disagrees with a baseline, check the population before checking the arithmetic.

**Practice adopted:** every baseline in this document states its population. Where two scopings exist for one quantity, both are recorded and labelled.

### G13 — A Date-to-DateTime relationship joins on nothing, silently
Every `Date` field grouped into a **single blank row** while measures returned their correct unfiltered totals. The `Date` table had all 1,096 rows and the relationships existed and were active.

**Cause:** `CALENDAR` produces `Date[Date]` as **Date** (midnight). Postgres timestamps arrived as **Date/Time**. The relationship joins on exact values including the time component, so `2017-03-04 14:22:31` never equals `2017-03-04 00:00:00`. Every row failed to match and fell into the blank.

**Fix:** in Power Query, set `Purchase Date`, `Delivery Date`, `Estimated Delivery Date`, `Approved Date` and `Carrier Date` to **Date** type. No analysis here uses time-of-day, and D19 already established lateness is measured in whole days against a promise that was only ever a date.

**Root cause class — the important part:** both columns were *individually* correct. Date/Time is the right type for a Postgres timestamp, and the Phase 2 type audit confirmed exactly that. The defect existed only in the **relationship between two correctly-typed columns**. Column-level validation cannot catch this; only exercising the relationship in a visual can.

**Symptom to recognise:** one blank grouping row plus correct grand totals means the join is failing, not the measure.

### G14 — Step order matters for folding only until folding breaks
Refinement of D20. The type-conversion step was placed last in the `Orders` query, after `Money and Freight to Fixed Decimal` had already broken folding. Everything past that point runs locally regardless of order, so placement there costs nothing and should be chosen for readability.

Placement starts mattering again the moment steps are reordered to restore folding further down the chain.

### G15 — Text date columns sort as text, everywhere they are used
The trend line came out ordered by *value*, not chronologically. Two separate causes stacked: the visual's Sort axis defaulted to the measure, **and** `Year Month` is a text column with no Sort by column set.

Two-digit month padding (`2018-09`) masks the second problem — until it does not. `Month` and `Weekday` were given sort columns in D27; `Year Month` was missed. Fix: add `"Year Month Number", YEAR([Date]) * 100 + MONTH([Date])` and sort by it.

**Same class as G19:** a column that is individually correct but wrong in use.

### G16 — A title is a claim and must be verified before it is written
The seller table was titled "A small number of sellers drive a large share of lateness" before anyone had measured whether that was true. It happened to be — 1,274 sellers have late orders and the top 20 account for 24.7% — but it could as easily have been 3%.

**Practice:** every finding-style title on the dashboard is checked in SQL first, and states a number rather than an adjective. "Top 20 of 1,274 sellers involved in 25% of late orders" is both stronger and falsifiable.

### G17 — Trim partial periods from trend charts, and say so
Olist starts September 2016 with a handful of orders and ends mid-October 2018. Both ends produce wild rates on tiny denominators that dominate the axis and hide the real pattern. The trend visual is filtered to 2017-01 – 2018-08, with the exclusion stated in the subtitle rather than hidden.

### G18 — `psql` vs PowerShell: the prompt tells you who is listening
`PS C:\...>` is PowerShell (filesystem, `psql`, OS commands). `olist=#` is psql (SQL, and backslash meta-commands). Also: `COPY` is server-side and resolves paths as the PostgreSQL service account, which cannot read `C:\Users\...`; `\copy` is client-side and reads as you. Use `\copy`. Two terminal windows, one of each, avoids the whole class of confusion.