## Measure Catalog
Each measure, a plain-English definition, and any gotcha in its filter behaviour. All measures live in a dedicated `_Measures` table (a blank Enter Data table with `Column1` hidden) so they are collected in one place rather than scattered across fact tables.

---

### `Total Orders`
```dax
Total Orders = COUNTROWS ( Orders )
```
**Plain English:** how many delivered orders are visible in the current context.

**Verified:** 96,478 unfiltered.

**Note:** `Orders` inside a measure does not mean "all 96,478 rows" — it means the table *as the current filter context leaves it*. In a card that is everything; in a row for São Paulo it is only São Paulo's orders. The measure never re-filters anything; it sees what the visual already narrowed.

Written explicitly rather than dragging `Order ID` in with Count, which would create an **implicit measure** — unnamed, invisible in the field list, and impossible to reference from another measure.

---

### `Late Orders`
```dax
Late Orders =
CALCULATE (
    [Total Orders],
    Orders[Is Late] = TRUE ()
)
```
**Plain English:** orders delivered after their estimated delivery date.

**Verified:** 6,534, matching the Phase 1 baseline.

**Filter behaviour:** `CALCULATE` evaluates its expression under a *modified* filter context. The filter **combines** with what the visual already applied — in a São Paulo row this gives late orders in São Paulo. But a filter argument naming a column **overwrites** the visual's filter on that same column: if a slicer had `Is Late = FALSE`, this measure would still return late orders.

---

### `Reviewed Orders`
```dax
Reviewed Orders =
CALCULATE (
    [Total Orders],
    NOT ISBLANK ( Orders[Review Score] )
)
```
**Plain English:** delivered orders that carry a review score.

**Verified:** 95,832, against 646 delivered orders with no review (D26).

**Note:** blank in DAX is a distinct state meaning "no value" — not zero, and not SQL's null. It propagates quietly through arithmetic, so `ISBLANK` is the explicit way to test for it.

---

### `Late Delivery Rate`
```dax
Late Delivery Rate =
DIVIDE (
    [Late Orders],
    [Total Orders]
)
```
**Plain English:** the share of visible orders that arrived late.

**Verified:** 6.77%, reproducing the Phase 1 baseline through four layers — SQL, Power Query, the model, and DAX.

**`DIVIDE` over `/`:** the `/` operator raises an error on divide-by-zero, and that error is not contained — one state with zero orders can break a whole matrix. `DIVIDE` returns blank instead.

**Third argument deliberately omitted.** `DIVIDE(..., ..., 0)` would show 0% for a state with no orders, which reads as a state that performed perfectly. Blank says "no data", which is true. Reserve the alternate result for cases where zero is genuinely the right answer.

**Format set at the measure** (Percentage, 2 dp), not per visual — `DIVIDE` returns 0.0677 and the format string handles display everywhere.

**Composition:** references `[Late Orders]` and `[Total Orders]` rather than repeating their logic. Redefining "late" changes one measure and everything above it follows.

---

### `Late Orders by Seller`
```dax
Late Orders by Seller =
CALCULATE (
    [Late Orders],
    CROSSFILTER ( 'Order Items'[Order ID], Orders[Order ID], BOTH )
)
```
**Plain English:** late orders involving each seller, usable when slicing by a seller attribute.

**Why it exists:** `Sellers → Order Items` is one-to-many so the filter propagates, but `Order Items → Orders` is many-to-one and filters do not travel from the many side to the one side. Without this, slicing `Late Orders` by `Sellers[State]` returns 6.77% on every row — the grand total repeated (D28).

**`CROSSFILTER` is a modifier, not a filter.** It filters no rows; it changes how a named relationship behaves for the duration of one `CALCULATE`. The two column arguments identify the relationship by naming both ends; `BOTH` makes it temporarily bidirectional.

**Why this is acceptable where the model-level toggle was not:** D28 rejected bidirectionality because it applies to every query in the model and creates ambiguous filter paths resolved by invisible rules. `CROSSFILTER` scopes the exception to one measure, leaves the rest of the model single-direction, and makes the exception visible in code a reviewer can read.

**⚠ NON-ADDITIVE — read before using in any total.** Every seller on a late order is charged with that lateness (D25), so summing across sellers double-counts multi-seller orders.

**Non-additivity depends on the dimension, not just the measure:**

| Sliced by | Sum of rows | True count | Overshoot |
|---|---:|---:|---:|
| Seller | ~6,880 | 6,534 | ~5% |
| Seller State | 6,537 | 6,534 | 0.05% |

Multi-seller orders overwhelmingly involve sellers in the *same* state (São Paulo dominates the seller base), so state-level allocation collapses to nearly additive while seller-level does not.

**Separately: a total row is not the sum of the rows above it.** Every cell in a matrix — including the total — is the measure re-evaluated in its own filter context. The total row carries no `Sellers[State]` filter, so it returns 6,534 rather than adding anything up. This is the origin of "my totals don't add up", and nothing is broken when it happens. Making a total equal the sum of its rows.

---

### `Avg Review Score`
```dax
Avg Review Score = AVERAGE ( Orders[Review Score] )
```
**Plain English:** mean review score across visible orders.

**Verified:** 4.1565 (delivered orders only, n = 95,832).

**⚠ Baseline scoping.** This does **not** match the 4.0873 Phase 1 figure, and should not. That baseline covers `clean.reviews` — 98,673 rows, all order statuses. This measure covers delivered orders only (D4). Both are recorded in the baselines table, labelled, because comparing a measure to a baseline computed over a different population is a recurring trap (see G13, G17).

**Free finding:** undelivered orders score materially worse — 4.0873 across all statuses vs 4.1565 among delivered. Delivery failure depresses review scores, visible before splitting by lateness at all.

**`AVERAGE` skips blanks entirely** — the 646 unreviewed orders are not counted as zero and do not inflate the denominator.

---

### `Avg Review Score - Late` / `Avg Review Score - On Time`
```dax
Avg Review Score - Late =
CALCULATE ( [Avg Review Score], Orders[Is Late] = TRUE () )

Avg Review Score - On Time =
CALCULATE ( [Avg Review Score], Orders[Is Late] = FALSE () )
```
**Plain English:** mean review score, split by whether the order arrived late.

**Verified: 2.27 late vs 4.29 on time.** This is the project's headline finding — **a late delivery costs roughly two stars.**

---

### `Avg Days Late`
```dax
Avg Days Late = AVERAGE ( Orders[Days Late] )
```
**Plain English:** mean signed days late across all delivered orders. Negative means early.

**Verified:** −11.88.

**⚠ Do not use as a headline.** It averages across two genuinely different populations — 93% arriving early and 6.77% arriving late — and reports a number describing neither. "The average order arrives 12 days early" is true and answers nobody's question. Kept as a component; never shown alone.

---

### `Avg Days Late When Late`
```dax
Avg Days Late When Late =
CALCULATE (
    [Avg Days Late],
    Orders[Is Late] = TRUE ()
)
```
**Plain English:** when an order is late, how late is it?

**Verified:** 10.62 days over 6,534 late orders (SQL: 10.6201).

**Resolves the open "headline lateness metric" decision.** Paired with `Late Delivery Rate`, these two numbers characterise the distribution properly: **how often** we are late, and **how badly**. A single conditional average replaces a pooled average that described neither population.

The fix here is conditional filtering with `CALCULATE`, **not** `AVERAGEX`. `AVERAGEX` addresses a different problem — averaging a *ratio* across a dimension rather than computing the ratio over pooled rows.

---

### `Total Revenue` / `Total Order Value`
```dax
Total Revenue = SUMX ( 'Order Items', 'Order Items'[Price] )

Total Order Value =
SUMX ( 'Order Items', 'Order Items'[Price] + 'Order Items'[Freight] )
```
**Verified:** `Total Revenue` = 13,221,498.11, matching Postgres to the penny — which is the standing verification of D18's Fixed Decimal conversion.

**Iterators, explained.** `SUM(column)` is shorthand for `SUMX(table, column)`. The X versions take an **expression** rather than a column and evaluate it once per row in **row context**, then aggregate. Same for `AVERAGE`/`AVERAGEX`, `COUNT`/`COUNTX`, `MIN`/`MINX`.

**An iterator returns one number, not one per row.** The row-by-row work is internal; the output shape is identical to the non-iterator version.

**When the two genuinely diverge — the rule:** if the expression is anything other than addition or subtraction of columns, aggregating first destroys the row-level pairing.

| Expression | `SUM` approach | Iterator | Agree? |
|---|---|---|---|
| `Price + Freight` | `SUM(A) + SUM(B)` | `SUMX(t, A + B)` | yes |
| `Quantity × Price` | `SUM(Q) * SUM(P)` — meaningless | `SUMX(t, Q * P)` — correct | **no** |

The iterator is also what lets a per-row calculation exist without a calculated column, which Tier 1 bans.

**Locale note:** this file renders numbers in Indian grouping (lakhs/crores), inherited from the machine that created it. Power BI fixes locale at file creation — Options → Regional settings only affects new files. Left as-is deliberately: the target audience is the India market, so this is the grouping a hiring manager there reads natively.

---

### `Late Orders by Delivery Date`
```dax
Late Orders by Delivery Date =
CALCULATE (
    [Late Orders],
    USERELATIONSHIP ( Orders[Delivery Date], Date[Date] )
)
```
**Plain English:** late orders bucketed by *when they were delivered* rather than when they were purchased.

**Why both exist:** "when were things delivered late?" is a different question from "when were late-delivered orders purchased?" An order bought in December and delivered in January belongs to December on one axis and January on the other. Both are legitimate and answer different things.

**`USERELATIONSHIP` is a modifier, not a filter** — same species as `CROSSFILTER`. It activates an inactive relationship for the duration of one `CALCULATE` and deactivates whichever relationship between those tables was active. Outside that `CALCULATE` the model is untouched.

**Constraints:** only valid inside `CALCULATE`/`CALCULATETABLE` — it modifies a context, so a context must exist — and it cannot activate a relationship that would create ambiguity.

**Verified:** both measures total **6,534**. Same orders, different time buckets, so the total is invariant while every row differs. 2016-09 shows purchases with no deliveries; 2016-11 shows deliveries with no purchases.