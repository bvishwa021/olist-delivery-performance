-- =====================================================================
-- Olist — Phase 1, checklist step 1: establish grain
-- Run with:  \i 'C:/data/olist/02_profile_grain.sql'
--
-- For each table: how many rows, and how many DISTINCT values in the
-- column(s) we believe define the grain. If they match, that column set
-- is the grain. If distinct < rows, our assumption is wrong.
-- =====================================================================

\echo '--- 1. CUSTOMERS: is customer_id the person, or something else? ---'
SELECT count(*)                          AS rows,
       count(DISTINCT customer_id)       AS distinct_customer_id,
       count(DISTINCT customer_unique_id) AS distinct_customer_unique_id
FROM raw.olist_customers_dataset;

\echo '--- 2. ORDERS: one row per order? ---'
SELECT count(*)                    AS rows,
       count(DISTINCT order_id)    AS distinct_order_id,
       count(DISTINCT customer_id) AS distinct_customer_id
FROM raw.olist_orders_dataset;

\echo '--- 3. ORDER_ITEMS: order_id alone is not unique. What is? ---'
SELECT count(*)                                       AS rows,
       count(DISTINCT order_id)                       AS distinct_order_id,
       count(DISTINCT (order_id, order_item_id))      AS distinct_order_plus_item,
       count(DISTINCT product_id)                     AS distinct_product_id
FROM raw.olist_order_items_dataset;

\echo '--- 4. PAYMENTS: same question, different key ---'
SELECT count(*)                                            AS rows,
       count(DISTINCT order_id)                            AS distinct_order_id,
       count(DISTINCT (order_id, payment_sequential))      AS distinct_order_plus_seq
FROM raw.olist_order_payments_dataset;

\echo '--- 5. REVIEWS: look carefully at all three numbers ---'
SELECT count(*)                   AS rows,
       count(DISTINCT review_id)  AS distinct_review_id,
       count(DISTINCT order_id)   AS distinct_order_id
FROM raw.olist_order_reviews_dataset;

\echo '--- 6. PRODUCTS ---'
SELECT count(*)                             AS rows,
       count(DISTINCT product_id)           AS distinct_product_id,
       count(DISTINCT product_category_name) AS distinct_category
FROM raw.olist_products_dataset;

\echo '--- 7. SELLERS ---'
SELECT count(*)                   AS rows,
       count(DISTINCT seller_id)  AS distinct_seller_id
FROM raw.olist_sellers_dataset;

\echo '--- 8. TRANSLATION ---'
SELECT count(*)                                  AS rows,
       count(DISTINCT product_category_name)     AS distinct_pt,
       count(DISTINCT product_category_name_english) AS distinct_en
FROM raw.product_category_name_translation;
