## Data Dictionary
Tables, grain, key columns, and what was filtered out. **Row counts and grain below are verified against the loaded data.**

| Table | Rows | Verified grain | Role |
|---|---:|---|---|
| `olist_orders_dataset` | 99,441 | `order_id` | fact source / date logic |
| `olist_order_items_dataset` | 112,650 | `(order_id, order_item_id)` | **fact grain** |
| `olist_order_reviews_dataset` | 99,224 | *none unique* — see D9, D10 | fact source |
| `olist_order_payments_dataset` | 103,886 | `(order_id, payment_sequential)` | fact source |
| `olist_customers_dataset` | 99,441 | `customer_id` | dimension |
| `olist_sellers_dataset` | 3,095 | `seller_id` | dimension |
| `olist_products_dataset` | 32,951 | `product_id` | dimension |
| `product_category_name_translation` | 71 | `product_category_name` | lookup |
| `olist_geolocation_dataset` | — | — | **excluded, see D7** |

**`customer_id` is not a person.** It is a per-order surrogate key: 99,441 `customer_id` values against 96,096 `customer_unique_id` values. The repeat customer is `customer_unique_id`. Any "number of customers" metric built on `customer_id` is really a count of orders.

**Referential integrity (verified, both directions):** no orphans anywhere — order_items, payments, and reviews all resolve to `orders`; order_items resolve to both `products` and `sellers`; orders resolve to `customers`. All gaps are parents with no children, never children with no parent:

| Gap | Count | Disposition |
|---|---:|---|
| orders with no item rows | 775 | none are `delivered`; removed by D4 |
| orders with no payment | 1 | investigate before building payment measures |
| orders with no review | 768 | expected; not every order gets reviewed |
| products with no category | 610 | needs an explicit "Unknown" bucket |

**Date roles in `orders`:** `order_purchase_timestamp` drives sales-over-time. `order_estimated_delivery_date` vs `order_delivered_customer_date` drives lateness. One active relationship to the date table; the other via `USERELATIONSHIP`.

*(Column-level type and null detail added as profiling produces it.)*

### Verified baselines — Phase 1

Every figure below was measured against the loaded raw data. **These are the reference numbers.** Any measure built in Phase 4 must reproduce them, and any divergence must be explained before the build moves on.

| Metric | Value |
|---|---:|
| Purchase date window | 2016-09-04 → 2018-10-17 |
| Delivered orders | 96,478 |
| Delivered orders with a delivery date | 96,470 |
| Late orders (delivered after estimate) | 6,534 |
| **Late rate** | **6.77%** |
| Average days late (all delivered) | −11.88 |
| Days late, range | −147 to +188 |
| Promise lead time — mean / median / p99 / max | 24.4 / 24 / 51 / 156 |
| Average review score (all 99,224 raw rows) | 4.0864 |
| Price range | 0.85 – 6,735.00 |
| Order items with zero freight | 383 |

**Clean layer, verified after build:** all view row counts match raw exactly except `clean.reviews`, which is 98,673 — precisely the 551 duplicate rows D9 removes, one row per order confirmed. Average review score after dedup is **4.0873**, up 0.0009 from the raw baseline. The dropped later reviews averaged roughly 3.93, so a second review does tend to be worse than the first — a suggestive direction on 551 rows, and an effect of one thousandth of a star on the headline. A note, not a result.

Status groups (D13): Delivered 96,478 / In flight 1,729 / Terminal 1,234 — sums to 99,441.

**Model tables as loaded (Phase 2, verified):**

| Table | Rows | Note |
|---|---:|---|
| Orders | 96,478 | delivered only (D4) |
| Order Items | 110,197 | delivered only (D21) |
| Reviews | 98,673 | deduplicated (D9) |
| Products | 32,951 | |
| Customers | 99,441 | |
| Sellers | 3,095 | |

`Is Late` = true on **6,534** rows, matching the Phase 1 late-order baseline exactly. `Days Late` ranges −147 to +188, also matching.

**Financial baselines (delivered orders only), verified in both Postgres and Power BI to the penny:**

| Metric | Value |
|---|---:|
| Revenue (sum of Price) | 13,221,498.11 |
| Freight (sum of Freight) | 2,198,275.64 |
| Orders with items | 96,478 |
| Orders with a review | 95,832 |
| Orders without a review | 646 |

The Power BI figure matching Postgres exactly is the verification of D18 — had the money columns stayed floating point, the totals would have diverged in the trailing decimals.

**Relationships (all one-to-many, all single-direction, dimension → fact):**

| From (many) | To (one) | On | Active |
|---|---|---|---|
| Orders | Customers | Customer ID | yes |
| Orders | Date | Purchase Date → Date | **yes** |
| Orders | Date | Delivery Date → Date | **no** (role-playing, D27) |
| Order Items | Orders | Order ID | yes |
| Order Items | Products | Product ID | yes |
| Order Items | Sellers | Seller ID | yes |

Hidden from report view: all key columns, plus `Date[Month Number]` and `Date[Weekday Number]` (they exist only to sort their text equivalents).

**Review score distribution (raw rows, before D9 dedup):**

| Score | Rows |
|---:|---:|
| 1 | 11,424 |
| 2 | 3,151 |
| 3 | 8,179 |
| 4 | 19,142 |
| 5 | 57,328 |

**Type audit:** zero cast failures across every column of every table — timestamps, integers, numerics all clean. Missing values arrived as genuine `NULL`, not empty strings, so strict casting costs nothing here.

**Missing dates are structural, not defects:** all 2,965 orders with no delivery date are non-`delivered` statuses, except the 8 covered by D11.

**Sequence anomalies:** 1,359 orders reached the carrier before their recorded approval date, and 23 were delivered before reaching the carrier. Zero orders were approved or delivered before purchase. The first two are almost certainly seller status-update lag rather than corrupt data; neither affects lateness, which is computed from purchase and delivery only.

**Date roles in `orders`:** `order_purchase_timestamp` drives sales-over-time. `order_estimated_delivery_date` vs `order_delivered_customer_date` drives lateness. One active relationship to the date table; the other via `USERELATIONSHIP`.

*(Column-level detail added as profiling produces it.)*
