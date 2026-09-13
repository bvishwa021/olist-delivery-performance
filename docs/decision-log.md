## Decision Logs
Every non-obvious choice, the alternative rejected, and why.

### D1 — Source layer is Postgres, not CSVs read directly by Power BI
**Rejected:** pointing Power Query straight at the CSV files.
**Why:** Two things a relational source buys that flat files cannot.

1. *Query folding.* Against Postgres, Power Query translates filter and column-removal steps into native SQL and pushes them to the database, so the work happens at the source instead of in the BI engine on already-loaded data. This is provable in the UI (`View Native Query` on a step). Folding is impossible by construction against a CSV.
2. *Type and constraint enforcement at load.* Declaring delivery timestamps as `timestamp` in Postgres forces null-heavy cancelled orders to surface during load rather than silently at report time.

**Cost accepted:** the `.pbix` points at `localhost:5432`, so it cannot be refreshed by anyone who clones the repo, and refresh in the Power BI Service would need an on-premises gateway. Import mode makes this near-theoretical — the data is cached in the model, and Olist is a frozen 2016–2018 dataset that never needs refreshing. Recorded as a README limitation.

### D2 — Shaping stays in Power Query; Postgres is not used to pre-shape
**Rejected:** building tidy SQL views so Power Query has little to do.
**Why:** The `.pbix` is the artifact being inspected. Transformation logic buried in a database view is logic a reviewer never sees. Postgres is the source and the profiling tool; the visible shaping stays in Applied Steps.

This is the deliberate tension with D3 — see the criterion there.

### D3 — Category-name translation is joined in SQL, not Power Query
**Rejected:** merging the translation lookup as a Power Query step.
**Why:** Roche's Maxim — *transform as far upstream as possible, and as far downstream as necessary.* The operative criterion is **whose logic is it**:

- **Dataset-general** logic belongs upstream. *Any* report on Olist wants English category names; nobody would ever want the Portuguese-only version. It is a static 1:1 lookup that will never change.
- **Report-specific** logic stays downstream, where it reads as a deliberate analytical choice.

"It's important" is not the criterion — plenty of important logic belongs downstream.

### D4 — Delivered-orders filter lives in Power Query *(confirmed)*
**Why:** Direct application of the D3 criterion, opposite answer. Filtering to delivered orders exists only because the question is about delivery lateness; a revenue report would want cancelled orders included. Report-specific, so it stays visible in Applied Steps.
**Confirmed by profiling:** of the 775 orders with no item rows, none have status `delivered` (they are `unavailable`, `canceled`, `created`, `invoiced`, `shipped`). The delivered-orders filter therefore removes all of them as a side effect, with no special handling needed.

### D9 — Multi-review orders: keep the earliest review per order
**Finding:** 547 orders carry more than one review (543 with two, 4 with three). Of those, 345 agree on the score and **202 disagree** — 37%. Material, not cosmetic.

**Rejected alternatives:**
- *Average the scores.* Produces 4.5-star reviews that never existed and makes "% of 1-star orders" incoherent as a metric.
- *Keep the latest.* The later review is more likely to reflect customer-service recovery than the delivery experience.
- *Leave duplicates in.* The join to orders would fan out those 547 rows, and every average would silently double-weight them.

**Rule:** earliest `review_creation_date` per `order_id`, tie-broken by `review_answer_timestamp`. The business question is whether the delivery experience drove the score, and the first response is least contaminated by what happened afterwards.

**Baseline to verify against:** average review score across all 99,224 raw rows is **4.0864**. After dedup the average must be recomputed and the difference explained, not just observed.

### D10 — `review_id` is not a key
`review_id` repeats across *different* orders with identical scores and creation dates — a Kaggle anonymisation artifact, not a business fact. It must not be used as a primary key, a dimension key, or a `DISTINCTCOUNT` target. This is a separate problem from D9: D9 is one order reviewed twice, D10 is one identifier reused across unrelated orders.

### D5 — Repo carries both `.pbip` and `.pbix`
**Why:** They solve different problems.
- `.pbip` (TMDL + PBIR) is a folder of text — DAX measures, relationships, and M queries become readable on the GitHub page without installing anything. It stores the *definition* only, so it will not open with data.
- `.pbix` in Import mode has the data cached inside it, so it opens and renders for anyone with no database.

Verify the PBIP/PBIR preview toggle state in this Desktop build before relying on it — the format was still finishing its preview run through mid-2026.

### D6 — Publishing: attempt Publish to web, plan for it being blocked
Publish to web requires a Pro or PPU license *and* a tenant-admin setting, and new embed codes are blocked by default. On a university tenant this will probably fail. Fallback is a PDF export plus an unlisted recorded walkthrough. Olist is public data, so nothing here constrains the design either way.

### D7 — Geolocation table excluded
~1M rows, and customer/seller state is sufficient granularity for the question.

### D8 — Fact grain is order items, not orders
Price and freight live in `olist_order_items_dataset`. An order with three items is three fact rows.

### D11 — 8 delivered orders with no delivery date: excluded from lateness, not deleted
**Finding:** 8 orders have status `delivered` but a null `order_delivered_customer_date`. One (`2d858f45…`) also has no carrier date.
**Rejected:** deleting the rows, or imputing a delivery date.
**Why:** These orders have real items and real revenue. Deleting them to fix a delivery problem would silently change the revenue total. Imputing a date would invent a lateness value that does not exist.
**Rule:** the rows stay in the model. Lateness measures filter them out via `order_delivered_customer_date IS NOT NULL`. A row can be valid for one question and unusable for another — that is a per-metric filter, not a row deletion.

### D12 — Implausible delivery estimates: left as-is, documented
**Finding:** a small number of orders carry estimates months beyond a delivery that actually took days (worst: purchased 2018-03-06, estimated 2018-08-03, delivered 2018-03-09 → −147 days). **The corrupt column is `order_estimated_delivery_date`, not the delivery date** — the deliveries themselves are normal and fast.
**Scale, measured:** promise lead time (estimate − purchase) has mean 24.4 days and median 24 — near-identical, so the process is well-behaved for effectively the whole population. Only 236 orders exceed 60 days (0.24%), 19 exceed 90, 4 exceed 120. Max 156.
**Rejected:** capping, excluding, or flagging the outliers.
**Why:** 0.02% of rows. Special-case logic here adds a code path a reviewer must understand in exchange for a change in the hundredths of a day. Documented instead.
**Note:** these rows do not affect the late rate at all — no rule flips a three-day delivery to "late". They affect only average-days-early. Same rows, different exposure per metric.

### D13 — Order status: terminal vs in-flight, not "delivered vs not"
The seven non-delivered statuses are two different things and must not be lumped together:
- **Terminal:** `canceled` (625), `unavailable` (609). These will never be delivered.
- **In-flight at export cut-off:** `shipped` (1,107), `processing` (301), `invoiced` (314), `approved` (2), `created` (5). These would have progressed had the export run later.

Saying "1.1% of orders are still in transit" about cancelled orders would be wrong. Any status-based visual must respect this split.

### D14 — The `clean` layer is built as views, not tables
**Rejected:** materialised tables with declared primary and foreign keys.

**Why the "but constraints demonstrate modeling" argument fails here:**
**Power BI does not read database constraints.** Not primary keys, not foreign keys, not check constraints. Each table or view arrives as a flat rectangle of rows and columns; nothing else crosses the connector. The star schema, relationships, cardinality and cross-filter direction are all built by hand in Power BI's Model view, and would be built identically from CSVs. Declaring `PRIMARY KEY (order_id)` in Postgres creates zero relationships in the `.pbix`.

So tables-vs-views is invisible to the Power BI artifact, and the decision comes down to source-side hygiene:
- Nothing is copied, so `clean` can never drift out of sync with `raw`.
- No rebuild step for anyone cloning the repo.
- The definition of "clean" is readable SQL rather than a load script that ran once and left no trace.
- Power Query folds against a view exactly as against a table, so D1's folding argument is unaffected.

**What the clean layer deliberately does NOT do:** compute `days_late`, filter to delivered orders, or remove columns. All three belong in Power Query per D2 — `days_late` especially, since burying the project's central calculation in a view definition would hide it from anyone reading the `.pbix`. Views are also named semantically (`clean.orders`, not `clean.fact_orders`) because the geography-dimension decision is still open and star-schema shaping is Phase 3.

### D15 — Six tables imported, `clean.payments` excluded
Payments answer none of the project's question — not lateness, not review score, not seller or state attribution. Importing it would add a *second fact table at a different grain* (103,886 payment rows against 99,440 orders), creating an ambiguous model and a table with no purpose. Tier 1 bans unused columns; a table nobody uses is worse. Re-addable in ten minutes if payment method ever matters.

### D16 — Import mode, not DirectQuery
**Why, in descending order:**
1. **DirectQuery would break D5.** The `.pbix` on GitHub only opens for a reviewer because Import caches data inside it. Under DirectQuery the file is an empty shell pointing at `localhost:5432`.
2. **DAX gets restricted.** Time intelligence and calculation groups are limited or unavailable — half the Tier 1 and Tier 2 targets sit in that zone.
3. **Refresh has no value.** DirectQuery's advantage is live data. Olist stopped in October 2018.

### D17 — Columns kept via Choose Columns (allow-list), not Remove Columns
*Remove Columns* writes a deny-list into the M code; *Choose Columns* writes an allow-list. If a column is later added to a source view, the deny-list lets it flow silently into the model. The allow-list keeps the model's shape a decision rather than a consequence of whatever the source contains.

**Kept on `orders`: all nine columns, including `order_approved_at` and `order_delivered_carrier_date`.** These look like funnel noise but decompose the delay into three intervals — purchase→approved (payment processing), approved→carrier (**seller prep time**), carrier→customer (**carrier transit**). That separates "this seller sat on orders for six days" from "this seller ships same-day but the carrier is slow in Bahia." Necessary for attributing blame correctly, which is half the project's question.

**Dropped:** `shipping_limit_date`; all review text and metadata except `order_id` and `review_score`; all product physical attributes and `product_category_pt`; both zip prefixes.
**Rejected keeping `review_comment_message`:** free text, 58,247 nulls, near-unique values — the worst-compressing column in the model. If the qualitative angle is wanted later, derive a `Has Comment` flag instead, which supports "73% of late orders left a written complaint vs 31% of on-time" — a better dashboard fact than one cherry-picked quote.

### D18 — Money columns forced to Fixed Decimal Number
Npgsql maps Postgres `numeric(10,2)` to Power Query's `type number`, a 64-bit float. Summing 112,650 floats accumulates error: a revenue total can surface as `13591643.700000018`, which formatting hides but equality comparisons don't. Fixed Decimal Number stores four exact decimal places.

This is the **one** place a `Changed Type` step is justified — everywhere else, types are declared once in the `clean` views (D14) and re-declaring them in Power Query would create two sources of truth with nothing keeping them in sync.

### D19 — `Days Late` and `Is Late` derived in Power Query, on `orders`
**Grain:** lateness is an attribute of an *order*, not an order item. On `order_items`, one late order with three items would contribute three late rows and every rate would be weighted by basket size.

**Unit:** both dates cast to `date` before subtracting. The estimate is midnight — Olist promised a *day*, not a moment. Subtracting raw timestamps would make an order arriving 14:00 on its estimated date read as 0.58 days late. Zero = on time.

**Two columns:** `Is Late` derives from `Days Late` rather than recomputing the comparison, so "late" has one definition in the model.

**Three-valued `Is Late`:** true / false / **null**. Null is never collapsed to false — that would count the D11 orders and every cancelled order as "on time".

**Not in DAX:** row-level and non-aggregatable, and Tier 1 bans calculated columns. Power Query is the only place it can go.

### D20 — Applied Steps ordering: filter before derive, for folding
**Query folding** is Power Query translating steps into SQL for the source to execute. It is **sequential** — translation stops at the first untranslatable step, and everything after runs locally regardless.

`Duration.Days(Date.From(...) - Date.From(...))` does not fold. Built in the wrong order (derive, then filter), folding broke at the derivation and the filter ran locally too: Postgres shipped all 99,441 rows for Power BI to discard 2,963. Reordering the filter above the derivations restored folding — Postgres now filters and returns 96,478.

**Verified:** `View Native Query` is enabled on `Navigation` and `Delivered Orders Only`, disabled from `Days Late` onward. Exactly as intended — the expensive operation folds, the cheap one doesn't.

**Rule:** remove → type → filter → derive. Identical output, different volume over the wire.

### D21 — `Order Items` filtered to delivered orders, via an inner merge
**Finding:** with `Orders` filtered to delivered (96,478) but `Order Items` left whole (112,650), the 2,963 filtered-out orders' items would still load.

**The mechanic that makes this dangerous:** unmatched rows do **not** disappear. Power BI creates a blank row on the one side and assigns every orphan to it, so those items stay fully aggregatable under a `(Blank)` member. `Total Revenue` over `Order Items` would then include cancelled and unavailable orders while every order-level metric covered delivered only — **two headline numbers on the
same page describing different populations, with nothing on screen saying so.**

**Method:** `Order Items` has no status column, so the filter comes from `Orders`: Merge Queries → `order_id` → **Inner** → delete the resulting table column without expanding. The join is used purely to drop rows with no delivered parent; nothing is imported from `Orders`.

**Verified:** 110,197 rows, matching a psql inner join on the same condition.

### D22 — Model-layer naming: Title Case tables and columns
`snake_case` is a **database** convention — unambiguous, no quoting, safe in SQL. The `raw` and `clean` layers keep it. The Power BI semantic model is a **presentation layer**: every name appears in the field list, visual headers, axis labels and tooltips. `order_delivered_customer_date` as a chart axis is a leaked implementation detail.

Consistency applies *within* a layer, with a clean break at the connector — which is exactly where the audience changes. Renames are done in Power Query, not model view, so they land in the M code and travel with the `.pbip`.

Also dropped at this point: `order_status` and `order_status_group`. After the delivered filter both are single-valued — worse than unused, since they present as slicers that do nothing.

### D23 — Folding verified across the whole Phase 2 chain
`Order Items` folds through **Kept Analysis Columns → Kept Delivered Rows → Removed Merge Columns**, including the merge. Both sides were still folding against the same Postgres connection, so Power Query generated a single SQL statement with a JOIN and Postgres returned 110,197 rows.

Folding stops at `Money and Freight to Fixed Decimal` and stays stopped for `Kept Model Names`. **Harmless:** both come after every volume-reducing operation and change no row or column counts. Folding governs how much data crosses the wire; by then the wire's work is done.

**This removed a decision rather than forcing one.** Had the merge not folded, the fix would have been a `clean.order_items_delivered` view in Postgres — which would have moved the delivered filter upstream and contradicted D4. It folded, so D4 stands unchallenged.

### D24 — Two fact tables at two grains, not one flattened fact
**Two business processes, not one:** an order being *sold* (item grain) and an order being *delivered and rated* (order grain). Kimball: each distinct process earns its own fact table, and grain is declared before anything else.

- `Orders` — one row per order. Days Late, Is Late, Review Score.
- `Order Items` — one row per item within an order. Price, Freight.

**Rejected: flattening lateness and review score down onto `Order Items`.** Tempting, because seller-level lateness would then be trivial — seller filters items, items already carry lateness. But an order with three items would carry its review score three times, so `AVERAGE(Review Score)` would weight every order by its item count: a 1-star review on a five-item order counting five times as much as one on a single-item order. **The headline finding — lateness vs review score — would be silently distorted by basket size.** Workable around in DAX, but that means defensive code in every measure to undo a problem the model created.

### D25 — Seller attribution is by allocation, and it is non-additive
**The constraint:** lateness is observed at *order* grain; blame is wanted at *seller* grain; the data contains no mechanism to apportion one to the other. No model fixes this — the information was never captured.

**Measured before deciding:** 97,388 orders have one seller, 1,219 have two, 54 have three, 3 have four, 2 have five. **98.7% single-seller.**

**Rule:** every seller on a late order is charged with that lateness. Summing "late orders" across sellers overshoots the true count by roughly 5% (about 1,343 seller-order pairs against 1,278 multi-seller orders). Non-additive by construction — must be stated in the measure catalog so nobody sums the column and expects the order total.

**Rejected: attributing lateness to the farthest seller.** Invents an attribution the data cannot support — distance is not even in the model (D7 dropped geolocation), and the theory is unverified. The delay may have been the *nearest* seller sitting on the order for a week. Never let a model assert something the data cannot support; that is worse than a metric with a caveat.

**Better framing available:** `Approved Date` → `Carrier Date` is the closest thing to a seller-controlled interval (D17). "Orders involving this seller take 6 days to reach the carrier vs a 2-day median" is a defensible seller-behaviour claim, unlike blaming them for carrier transit through Bahia.

### D26 — `Reviews` merged into `Orders`, not kept as a related table
Same grain, same business process, same event — Kimball says one fact table.

**Measured first:** of 96,478 delivered orders, 95,832 have a review and **646 do not** (0.67%).

**Left Outer join, never Inner.** Inner would silently drop those 646 orders, shrinking the revenue total to fix a review problem — the trap D11 avoided. Blank Review Scores are correct: `AVERAGE` ignores blanks, so the average covers reviewed orders only while the unreviewed orders still count in Total Orders and revenue.

**Rejected: separate table on a one-to-one relationship.** Adds a relationship and gains nothing; one-to-one filtering behaves differently from one-to-many and cross-filter direction gets murky.

The `Reviews` query has **Enable load** unticked — it stays in the file as a documented intermediate step without creating an unused model table.

### D27 — Dedicated `Date` table, built in DAX, 2016-01-01 to 2018-12-31
**Why a date table when `Orders` already has five date columns:**
1. Time intelligence (`TOTALYTD`, `SAMEPERIODLASTYEAR`, `DATEADD`) requires a marked date table with contiguous days. The Tier 2 MIS page is built on these.
2. **Gaps lie.** Grouped by a fact's own date column, a day with no orders is simply omitted and the line connects across it invisibly. A date dimension has every day, so absence shows as zero.
3. Two date roles need one shared dimension, or they can never be compared.

**Full calendar years, not the data range:** YTD over a year starting in September is nonsense. The end date must also cover `Estimated Delivery Date`, which runs to 2018-11-12 — later than any actual delivery.

**Rejected `CALENDARAUTO()`:** infers its range by scanning every date column in the model, so the range would silently change if a stray date column ever appeared. Explicit boundaries mean the model does what the code says.

**Not a Tier 1 violation.** "Measures, not calculated columns" exists to stop business logic freezing into fact-table columns that ignore filter context. Date attributes are the textbook exception — dimensional attributes sliced *by*, not measurements aggregated.

`Month` and `Weekday` are text and must be **Sort by Column** on their number equivalents, or they sort alphabetically (Apr, Aug, Dec…). Table is **Marked as Date Table**.

### D28 — Single-direction relationships kept, despite a visibly broken filter
**The symptom:** `Sellers[State]` against `AVERAGE(Orders[Days Late])` returns
**−11.88 for every state** — the grand total repeated on every row.

**The cause:** `Sellers → Order Items` is one-to-many, so the filter propagates. `Order Items → Orders` is many-to-one, and **filters do not travel from the many side to the one side.** The seller filter reaches `Order Items` and stops. Orders never hears about it.

**Rejected: bidirectional cross-filtering on `Order Items → Orders`.** It works, and it creates ambiguity — `Date` also filters `Orders`, so filters could then reach `Order Items` by more than one path, resolved by rules nobody wrote and nobody can see. Results become dependent on which visuals happen to be on the page.

**The fix is DAX, not modeling:** `CROSSFILTER` / `TREATAS` open that path for one measure rather than model-wide. Phase 4. This is genuine filter-context manipulation rather than `CALCULATE` as a glorified `SUMIF`.

**The model is correct as built.** A repeated grand total across every row of a dimension means the filter never arrived — recognising that symptom is worth as much as knowing this particular cause.

### D29 — Page designed for an operations manager, not a recruiter
**Audience priority:** (1) an Olist operations manager deciding *which sellers or regions to intervene with this week, and whether it is improving*; (2) a recruiter who spends ninety seconds and never touches a slicer; (3) visual appeal.

**Why not design for the recruiter:** a specific decision produces a sharper page, and a sharp page reads well to a recruiter anyway. Designing *for* the recruiter produces something that looks impressive and decides nothing.

**On "pretty" ranking third:** most of what reads as polished *is* clarity — alignment, restrained palette, whitespace, direct labels. Those serve both audiences. Only the purely decorative parts (hero images, gradients, shadows, donut charts) trade off, and those hurt both. So the ranking rarely costs anything.

### D30 — Custom theme: neutrals plus one reserved accent
Blue-grey ramp (`#3D5A73` → `#C9D6DE`) for all neutral series; a single desaturated brick red (`#B4460E`) that appears **only** on lateness and low review scores. Once a reader learns the accent means a problem, the page becomes scannable without a legend — and using it decoratively anywhere would destroy that.

The accent sits at **position 7** in `dataColors` deliberately, so Power BI's automatic assignment never reaches it by accident.

Off-white canvas `#FAF9F6` with pure-white visual backgrounds: white-on-white gives no separation without heavy borders. Gridlines on value axes only, at `#E4E1DA`. Drop shadows off. Type deliberately small (10pt labels, 12pt titles) — Power BI's defaults are large enough to make any page look like a school project.

### D31 — Small-sample guard on the state ranking
```dax
Late Delivery Rate (Min 100 Orders) =
IF ( [Total Orders] >= 100, [Late Delivery Rate] )
```
States under 100 delivered orders drop out rather than topping the chart on thin evidence. The omitted `else` returns blank rather than 0 — same reasoning as `DIVIDE`'s omitted third argument.

**Threshold set at 10% for the accent colour** (~1.5× the national rate), chosen for business meaning, not appearance.

**Rejected: raising the threshold to 12–15% to produce a nicer mix of red and slate.** That is choosing a number backwards — from visual appearance to rule, rather than from meaning to rule. "Why 15%?" would have had no answer.

**The real fix was showing all 27 states rather than Top 10.** Cropping to the top 10 meant every bar was red, so the accent carried no information. With the full list, a red cluster sits above a slate tail and the boundary is visible instantly.

**Sample-size honesty:** AL (21.4%, n=397), MA (17.4%, n=717), SE (15.2%, n=335), PI (13.9%, n=476), CE (13.8%, n=1,279). The *ranking* between them is fragile on those denominators; the *cluster* is not — five neighbouring Northeast states independently at ~3× the national rate is a regional logistics pattern, not sampling noise. The dashboard shows the pattern rather than crowning a loser.

### D32 — Lateness buckets in Power Query, uneven widths
Boundaries: 7+ days early / 1–6 early / on the day / 1–3 late / 4–7 late / 8–14 late / 15+ late.

**Uneven by design** — finer around zero, coarser at the extremes. The difference between 1 and 5 days late matters to a customer; the difference between 60 and 90 does not. Equal-width buckets would put 95% of orders in one bar.

Row-level and non-aggregatable, so Power Query per D19 and Tier 1. A companion `Bucket Order` integer column drives **Sort by column**, or the buckets sort alphabetically.

**Result — the strongest visual on the page:** a monotonic decline from 4.5 to 1.7 stars. This is a **dose-response** relationship, materially harder to dismiss than the binary 4.29-vs-2.27 split, because it shows the effect is continuous rather than a threshold artifact.

**Blank bucket filtered out of the visual:** the 8 D11 orders have null `Days Late` but real review scores, and were rendering as the tallest bar at 4.5. They are not a category — they are an absence being drawn as one.

### D33 — Seller identity: truncated code, distributional framing
The dataset is anonymised; seller IDs are 32-character hashes with no names. `3d871de0142ce09b7081e2b9d1733415` is a row identifier, not something an operations manager can act on.

**Rejected: dropping seller-level analysis for seller city/state.** That would have been a third geography visual answering a question the page already answers twice.

**Chosen:** first 8 characters, uppercased (`Text.Upper(Text.Start([Seller ID], 8))`), with the visual framed **distributionally** rather than as a culprit list. 4.3 billion combinations against 3,095 sellers makes collisions effectively impossible — verified by checking distinct code count still equals 3,095.

**The finding, measured before it was asserted:** 1,274 sellers have at least one late order; the top 20 are involved in **24.7%** of all late orders. Stated as "involved in" rather than "caused" — the figure double-counts multi-seller orders per D25, and precision that can be defended beats a stronger claim that cannot.

**Twenty accounts is a tractable intervention list.** "The Northeast has a logistics problem" is not something an ops manager can act on this week. This is arguably the most operationally useful visual on the page.

### D34 — Ratio measures need numerator *and* denominator in the same context
```dax
Total Orders by Seller =
CALCULATE ( [Total Orders],
            CROSSFILTER ( 'Order Items'[Order ID], Orders[Order ID], BOTH ) )

Late Delivery Rate by Seller =
DIVIDE ( [Late Orders by Seller], [Total Orders by Seller] )
```
`Late Orders by Seller` fixed the numerator's cross-filter problem (D28); the denominator was never fixed. Using the original `Late Delivery Rate` sliced by a seller column would have given **this seller's late orders over everyone's total orders** — a plausible-looking, meaningless number that announces nothing when it is wrong.

### D35 — Page title carries the finding, not just the subject
A text box across the top states the conclusion before any visual:
*"Late deliveries cost an average of 2 stars. 6.8% of orders arrive late; the
Northeast and 20 sellers drive most of it."*

Checklist point 2 — the reader who stops after three seconds still leaves with the finding. This is the single highest-value element on the page for the secondary (recruiter) audience.

**Title set in slate `#2B3440`, not the accent.** The brick red is reserved for "bad" (D30); using it decoratively for a heading would break the convention the rest of the page depends on.

### D36 — Top 12 states shown, as a readability decision
Twenty-seven bars need more vertical room than the page can spare, and the resulting scrollbar hurts more than the omitted states help. Cut to Top 12.

**Logged as readability, not analysis** — unlike D31's 100-order threshold, which is an evidential rule. The distinction matters: one is about what the data can support, the other about what fits on screen. Subtitle states both: *"Top 12 states shown; states under 100 delivered orders excluded."*

The 12th state sits below the national reference line, so the cut does not imply the remaining states are performing acceptably.

### D37 — Trend chart: monthly categorical axis, not daily continuous
Twice built as a continuous daily axis and twice reverted. ~600 daily points swinging to 30% are dominated by day-of-week effects and small-denominator noise on ~200 orders a day — the monthly pattern the title claims becomes invisible.

**The visual misrepresented its own data**, which is worse than any formatting issue. Fixed by returning to `Date[Year Month]` with a `MMM yy` label format (`Jan 17` is half the width of `2017-01`, so labels fit horizontally without rotating).

### D38 — Drillthrough page for state detail
`Customers[State]` set as the drillthrough field on a hidden `State Detail` page. Right-clicking a state on the main chart passes that value into the page's filter context automatically.

Dynamic title built with a card visual bound to:
```dax
Selected State =
"Delivery detail — " & SELECTEDVALUE ( Customers[State], "All states" )
```
`SELECTEDVALUE` returns a column's single value when exactly one is visible in the current filter context and the alternate otherwise. A card bound to a text measure is the standard way to build a dynamic title, since text boxes cannot reference measures.

Page carries the state-scoped KPI row, trend against the national constant line, lateness buckets, and that state's worst sellers — detail the main page has no room for.

### Open decisions
- `Customers` and `Sellers` are separate dimensions attached to different facts (Customers→Orders, Sellers→Order Items). They are not one dimension played twice — they describe different parties to the transaction and are never conformed against each other.
- **Headline lateness metric:** `avg_days_late` averages across two genuinely different populations — 93% arriving early and 6.77% arriving late — and reports a number describing neither (−11.88 days). Late *rate*, or a conditional average over late orders only, are both stronger candidates. Decide in Phase 4.
- **Order with no payment record:** 1 order. Moot unless payments are ever imported (D15).