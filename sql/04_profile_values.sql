-- =====================================================================
-- Olist — Phase 1, checklist steps 3, 5, 7
--   3. Type audit      — what survives a cast, counted not guessed
--   5. Missingness     — NULL vs empty string, and what missing means
--   7. Ranges & sanity — impossible values and impossible sequences
--
-- Run with:  \i 'C:/data/olist/04_profile_values.sql'
--
-- pg_input_is_valid(value, type) returns true/false instead of raising.
-- That is what makes a census of cast failures possible at all.
-- =====================================================================

\echo '########## STEP 3 — TYPE AUDIT ##########'

\echo '--- A. ORDERS: do the five date columns cast? ---'
SELECT count(*) AS rows,
  count(*) FILTER (WHERE NOT pg_input_is_valid(NULLIF(order_purchase_timestamp,''),'timestamp'))      AS bad_purchase,
  count(*) FILTER (WHERE NOT pg_input_is_valid(NULLIF(order_approved_at,''),'timestamp'))             AS bad_approved,
  count(*) FILTER (WHERE NOT pg_input_is_valid(NULLIF(order_delivered_carrier_date,''),'timestamp'))  AS bad_carrier,
  count(*) FILTER (WHERE NOT pg_input_is_valid(NULLIF(order_delivered_customer_date,''),'timestamp')) AS bad_delivered,
  count(*) FILTER (WHERE NOT pg_input_is_valid(NULLIF(order_estimated_delivery_date,''),'timestamp')) AS bad_estimated
FROM raw.olist_orders_dataset;

\echo '--- B. ORDER_ITEMS: money and dates ---'
SELECT count(*) AS rows,
  count(*) FILTER (WHERE NOT pg_input_is_valid(NULLIF(order_item_id,''),'integer'))         AS bad_item_id,
  count(*) FILTER (WHERE NOT pg_input_is_valid(NULLIF(shipping_limit_date,''),'timestamp')) AS bad_ship_limit,
  count(*) FILTER (WHERE NOT pg_input_is_valid(NULLIF(price,''),'numeric'))                 AS bad_price,
  count(*) FILTER (WHERE NOT pg_input_is_valid(NULLIF(freight_value,''),'numeric'))         AS bad_freight
FROM raw.olist_order_items_dataset;

\echo '--- C. PAYMENTS ---'
SELECT count(*) AS rows,
  count(*) FILTER (WHERE NOT pg_input_is_valid(NULLIF(payment_sequential,''),'integer'))   AS bad_sequential,
  count(*) FILTER (WHERE NOT pg_input_is_valid(NULLIF(payment_installments,''),'integer')) AS bad_installments,
  count(*) FILTER (WHERE NOT pg_input_is_valid(NULLIF(payment_value,''),'numeric'))        AS bad_value
FROM raw.olist_order_payments_dataset;

\echo '--- D. REVIEWS ---'
SELECT count(*) AS rows,
  count(*) FILTER (WHERE NOT pg_input_is_valid(NULLIF(review_score,''),'integer'))              AS bad_score,
  count(*) FILTER (WHERE NOT pg_input_is_valid(NULLIF(review_creation_date,''),'timestamp'))    AS bad_creation,
  count(*) FILTER (WHERE NOT pg_input_is_valid(NULLIF(review_answer_timestamp,''),'timestamp')) AS bad_answer
FROM raw.olist_order_reviews_dataset;

\echo '--- E. PRODUCTS: the numeric attributes ---'
SELECT count(*) AS rows,
  count(*) FILTER (WHERE NOT pg_input_is_valid(NULLIF(product_name_lenght,''),'integer'))        AS bad_name_len,
  count(*) FILTER (WHERE NOT pg_input_is_valid(NULLIF(product_description_lenght,''),'integer')) AS bad_desc_len,
  count(*) FILTER (WHERE NOT pg_input_is_valid(NULLIF(product_photos_qty,''),'integer'))         AS bad_photos,
  count(*) FILTER (WHERE NOT pg_input_is_valid(NULLIF(product_weight_g,''),'numeric'))           AS bad_weight,
  count(*) FILTER (WHERE NOT pg_input_is_valid(NULLIF(product_length_cm,''),'numeric'))          AS bad_length
FROM raw.olist_products_dataset;

\echo '########## STEP 5 — MISSINGNESS: NULL vs EMPTY STRING ##########'

\echo '--- F. ORDERS: this is the important one ---'
SELECT count(*) AS rows,
  count(*) FILTER (WHERE order_approved_at IS NULL)             AS approved_null,
  count(*) FILTER (WHERE order_approved_at = '')                AS approved_empty,
  count(*) FILTER (WHERE order_delivered_carrier_date IS NULL)  AS carrier_null,
  count(*) FILTER (WHERE order_delivered_carrier_date = '')     AS carrier_empty,
  count(*) FILTER (WHERE order_delivered_customer_date IS NULL) AS delivered_null,
  count(*) FILTER (WHERE order_delivered_customer_date = '')    AS delivered_empty
FROM raw.olist_orders_dataset;

\echo '--- G. Missing delivery date BY STATUS: is missing structural or a defect? ---'
SELECT order_status,
       count(*) AS orders,
       count(*) FILTER (WHERE NULLIF(order_delivered_customer_date,'') IS NULL) AS no_delivery_date,
       count(*) FILTER (WHERE NULLIF(order_approved_at,'')             IS NULL) AS no_approval_date
FROM raw.olist_orders_dataset
GROUP BY 1 ORDER BY 2 DESC;

\echo '--- H. REVIEWS: free-text columns ---'
SELECT count(*) AS rows,
  count(*) FILTER (WHERE review_comment_title IS NULL)   AS title_null,
  count(*) FILTER (WHERE review_comment_title = '')      AS title_empty,
  count(*) FILTER (WHERE review_comment_message IS NULL) AS message_null,
  count(*) FILTER (WHERE review_comment_message = '')    AS message_empty
FROM raw.olist_order_reviews_dataset;

\echo '########## STEP 7 — RANGES & SANITY ##########'

\echo '--- I. Date window: does it match the stated Sept 2016 - Oct 2018? ---'
SELECT min(NULLIF(order_purchase_timestamp,'')::timestamp)      AS first_purchase,
       max(NULLIF(order_purchase_timestamp,'')::timestamp)      AS last_purchase,
       min(NULLIF(order_delivered_customer_date,'')::timestamp) AS first_delivery,
       max(NULLIF(order_delivered_customer_date,'')::timestamp) AS last_delivery,
       max(NULLIF(order_estimated_delivery_date,'')::timestamp) AS last_estimate
FROM raw.olist_orders_dataset;

\echo '--- J. Impossible sequences: time running backwards ---'
SELECT
  count(*) FILTER (WHERE NULLIF(order_approved_at,'')::timestamp
                       < NULLIF(order_purchase_timestamp,'')::timestamp)      AS approved_before_purchase,
  count(*) FILTER (WHERE NULLIF(order_delivered_carrier_date,'')::timestamp
                       < NULLIF(order_approved_at,'')::timestamp)             AS carrier_before_approved,
  count(*) FILTER (WHERE NULLIF(order_delivered_customer_date,'')::timestamp
                       < NULLIF(order_purchase_timestamp,'')::timestamp)      AS delivered_before_purchase,
  count(*) FILTER (WHERE NULLIF(order_delivered_customer_date,'')::timestamp
                       < NULLIF(order_delivered_carrier_date,'')::timestamp)  AS delivered_before_carrier
FROM raw.olist_orders_dataset;

\echo '--- K. Money: zeros, negatives, extremes ---'
SELECT
  count(*) FILTER (WHERE NULLIF(price,'')::numeric  = 0) AS price_zero,
  count(*) FILTER (WHERE NULLIF(price,'')::numeric  < 0) AS price_negative,
  min(NULLIF(price,'')::numeric)                         AS price_min,
  max(NULLIF(price,'')::numeric)                         AS price_max,
  count(*) FILTER (WHERE NULLIF(freight_value,'')::numeric = 0) AS freight_zero,
  count(*) FILTER (WHERE NULLIF(freight_value,'')::numeric < 0) AS freight_negative,
  max(NULLIF(freight_value,'')::numeric)                        AS freight_max
FROM raw.olist_order_items_dataset;

\echo '--- L. review_score: what values actually occur? ---'
SELECT review_score, count(*) AS n
FROM raw.olist_order_reviews_dataset
GROUP BY 1 ORDER BY 1;

\echo '--- M. order_status distribution (drives the D4 filter) ---'
SELECT order_status, count(*) AS orders,
       round(100.0 * count(*) / sum(count(*)) OVER (), 2) AS pct
FROM raw.olist_orders_dataset
GROUP BY 1 ORDER BY 2 DESC;

\echo '--- N. LATENESS: the distribution the whole project rests on ---'
SELECT
  count(*)                                               AS delivered_orders,
  count(*) FILTER (WHERE days_late > 0)                  AS late_orders,
  round(100.0 * count(*) FILTER (WHERE days_late > 0) / count(*), 2) AS pct_late,
  min(days_late)                                         AS earliest_days,
  max(days_late)                                         AS latest_days,
  round(avg(days_late), 2)                               AS avg_days_late
FROM (
  SELECT (NULLIF(order_delivered_customer_date,'')::timestamp::date
        - NULLIF(order_estimated_delivery_date,'')::timestamp::date) AS days_late
  FROM raw.olist_orders_dataset
  WHERE order_status = 'delivered'
    AND NULLIF(order_delivered_customer_date,'') IS NOT NULL
    AND NULLIF(order_estimated_delivery_date,'') IS NOT NULL
) t;
