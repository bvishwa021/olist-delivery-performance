-- =====================================================================
-- Olist — Phase 1, final step: the clean layer
-- Run with:  \i 'C:/data/olist/05_clean_layer.sql'
--
-- Built as VIEWS, not tables. Nothing is copied; every read re-runs the
-- casts against raw. Single source of truth, no rebuild step, and the
-- definition of "clean" is readable SQL rather than a load script that
-- ran once.
--
-- Encodes decisions D3 (translation join), D9 (review dedup),
-- G1 (COALESCE fallback), G5 (Unknown category bucket).
--
-- Deliberately NOT here:
--   * days_late          -> Power Query, per D2. It is the analytical
--                           heart of the project and must stay visible.
--   * delivered filter   -> Power Query, per D4. Report-specific.
--   * column removal     -> Power Query. Folds to SQL anyway, and stays
--                           visible as an Applied Step.
--   * dim_/fact_ prefixes-> Phase 3. The geography decision is still open.
-- =====================================================================

DROP VIEW IF EXISTS clean.orders;
CREATE VIEW clean.orders AS
SELECT
    order_id,
    customer_id,
    order_status,
    order_purchase_timestamp::timestamp      AS order_purchase_timestamp,
    order_approved_at::timestamp             AS order_approved_at,
    order_delivered_carrier_date::timestamp  AS order_delivered_carrier_date,
    order_delivered_customer_date::timestamp AS order_delivered_customer_date,
    order_estimated_delivery_date::timestamp AS order_estimated_delivery_date,
    -- D13: terminal vs in-flight is a real distinction, not "delivered or not"
    CASE order_status
        WHEN 'delivered'                     THEN 'Delivered'
        WHEN 'canceled'                      THEN 'Terminal'
        WHEN 'unavailable'                   THEN 'Terminal'
        ELSE 'In flight'
    END                                      AS order_status_group
FROM raw.olist_orders_dataset;

DROP VIEW IF EXISTS clean.order_items;
CREATE VIEW clean.order_items AS
SELECT
    order_id,
    order_item_id::int                  AS order_item_id,
    product_id,
    seller_id,
    shipping_limit_date::timestamp      AS shipping_limit_date,
    price::numeric(10,2)                AS price,
    freight_value::numeric(10,2)        AS freight_value
FROM raw.olist_order_items_dataset;

DROP VIEW IF EXISTS clean.payments;
CREATE VIEW clean.payments AS
SELECT
    order_id,
    payment_sequential::int      AS payment_sequential,
    payment_type,
    payment_installments::int    AS payment_installments,
    payment_value::numeric(10,2) AS payment_value
FROM raw.olist_order_payments_dataset;

-- ---------------------------------------------------------------------
-- REVIEWS — D9: one row per order, earliest review wins.
--
-- ROW_NUMBER() partitions the rows by order_id, orders each partition by
-- creation date then answer timestamp, and numbers them 1, 2, 3...
-- Keeping rn = 1 keeps the earliest per order. This is portable ANSI SQL;
-- Postgres also has DISTINCT ON, which is shorter but non-standard.
--
-- review_id is NOT a key (D10) and is deliberately not treated as one.
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS clean.reviews;
CREATE VIEW clean.reviews AS
SELECT order_id,
       review_id,
       review_score,
       review_comment_title,
       review_comment_message,
       review_creation_date,
       review_answer_timestamp
FROM (
    SELECT
        order_id,
        review_id,
        review_score::int                   AS review_score,
        review_comment_title,
        review_comment_message,
        review_creation_date::timestamp     AS review_creation_date,
        review_answer_timestamp::timestamp  AS review_answer_timestamp,
        ROW_NUMBER() OVER (
            PARTITION BY order_id
            ORDER BY review_creation_date::timestamp,
                     review_answer_timestamp::timestamp
        ) AS rn
    FROM raw.olist_order_reviews_dataset
) t
WHERE rn = 1;

-- ---------------------------------------------------------------------
-- PRODUCTS — D3 translation join, G1 fallback, G5 Unknown bucket.
--
-- Two nested COALESCEs, in order:
--   1. English name if the translation exists
--   2. otherwise the original Portuguese name  (G1 — 13 products)
--   3. otherwise 'Unknown'                     (G5 — 610 products)
-- LEFT JOIN, never INNER: an inner join would silently drop products.
--
-- Source typos product_name_lenght / product_description_lenght are
-- corrected here. raw keeps them verbatim; renaming is a visible
-- transformation, which is exactly what this layer is for.
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS clean.products;
CREATE VIEW clean.products AS
SELECT
    p.product_id,
    p.product_category_name                       AS product_category_pt,
    COALESCE(
        COALESCE(t.product_category_name_english, p.product_category_name),
        'Unknown'
    )                                             AS product_category,
    p.product_name_lenght::int                    AS product_name_length,
    p.product_description_lenght::int             AS product_description_length,
    p.product_photos_qty::int                     AS product_photos_qty,
    p.product_weight_g::numeric                   AS product_weight_g,
    p.product_length_cm::numeric                  AS product_length_cm,
    p.product_height_cm::numeric                  AS product_height_cm,
    p.product_width_cm::numeric                   AS product_width_cm
FROM raw.olist_products_dataset p
LEFT JOIN raw.product_category_name_translation t
       ON t.product_category_name = p.product_category_name;

-- ---------------------------------------------------------------------
-- CUSTOMERS / SELLERS
--
-- zip_code_prefix stays TEXT. It is an identifier, not a quantity:
-- you never sum it or average it, and casting to int would destroy any
-- leading zero. "Looks numeric" is not a reason to store as numeric.
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS clean.customers;
CREATE VIEW clean.customers AS
SELECT
    customer_id,
    customer_unique_id,
    customer_zip_code_prefix,
    customer_city,
    upper(customer_state) AS customer_state
FROM raw.olist_customers_dataset;

DROP VIEW IF EXISTS clean.sellers;
CREATE VIEW clean.sellers AS
SELECT
    seller_id,
    seller_zip_code_prefix,
    seller_city,
    upper(seller_state) AS seller_state
FROM raw.olist_sellers_dataset;

-- =====================================================================
-- VERIFICATION — compare against the Phase 1 baselines.
-- =====================================================================

\echo '--- 1. Row counts: everything unchanged EXCEPT reviews ---'
SELECT 'orders' AS view_name, count(*) AS rows, 99441 AS expected FROM clean.orders
UNION ALL SELECT 'order_items', count(*), 112650 FROM clean.order_items
UNION ALL SELECT 'payments',    count(*), 103886 FROM clean.payments
UNION ALL SELECT 'products',    count(*),  32951 FROM clean.products
UNION ALL SELECT 'customers',   count(*),  99441 FROM clean.customers
UNION ALL SELECT 'sellers',     count(*),   3095 FROM clean.sellers
UNION ALL SELECT 'reviews',     count(*),  98673 FROM clean.reviews
ORDER BY 1;

\echo '--- 2. D9 dedup: one row per order now? ---'
SELECT count(*) AS rows, count(DISTINCT order_id) AS distinct_orders
FROM clean.reviews;

\echo '--- 3. How much did dedup move the average? Baseline was 4.0864 ---'
SELECT round(avg(review_score), 4) AS avg_after_dedup,
       round(avg(review_score) - 4.0864, 4) AS change_vs_baseline
FROM clean.reviews;

\echo '--- 4. G5/G1: no null categories, and Unknown/Portuguese buckets sized ---'
SELECT count(*) FILTER (WHERE product_category IS NULL)      AS null_category,
       count(*) FILTER (WHERE product_category = 'Unknown')  AS unknown_bucket,
       count(*) FILTER (WHERE product_category = product_category_pt
                          AND product_category <> 'Unknown') AS fell_back_to_pt
FROM clean.products;

\echo '--- 5. D13 status groups ---'
SELECT order_status_group, count(*) AS orders
FROM clean.orders GROUP BY 1 ORDER BY 2 DESC;
