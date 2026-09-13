-- =====================================================================
-- Olist — Phase 1, checklist steps 8 & 9: overlap, integrity, coverage
-- Run with:  \i 'C:/data/olist/03_profile_integrity.sql'
--
-- Cardinality tells you the size of a set. It never tells you the size
-- of an intersection. Everything below tests intersections directly.
-- Every check runs in BOTH directions — orphans hide on either side.
-- =====================================================================

\echo '=== A. ORDERS <-> ORDER_ITEMS ==='
SELECT
  (SELECT count(*) FROM raw.olist_orders_dataset o
     WHERE NOT EXISTS (SELECT 1 FROM raw.olist_order_items_dataset i
                        WHERE i.order_id = o.order_id))         AS orders_with_no_items,
  (SELECT count(DISTINCT i.order_id) FROM raw.olist_order_items_dataset i
     WHERE NOT EXISTS (SELECT 1 FROM raw.olist_orders_dataset o
                        WHERE o.order_id = i.order_id))         AS item_orders_not_in_orders;

\echo '=== B. Which STATUS are the item-less orders? (the likely explanation) ==='
SELECT o.order_status, count(*) AS orders_with_no_items
FROM raw.olist_orders_dataset o
WHERE NOT EXISTS (SELECT 1 FROM raw.olist_order_items_dataset i
                   WHERE i.order_id = o.order_id)
GROUP BY 1 ORDER BY 2 DESC;

\echo '=== C. ORDERS <-> PAYMENTS ==='
SELECT
  (SELECT count(*) FROM raw.olist_orders_dataset o
     WHERE NOT EXISTS (SELECT 1 FROM raw.olist_order_payments_dataset p
                        WHERE p.order_id = o.order_id))         AS orders_with_no_payment,
  (SELECT count(DISTINCT p.order_id) FROM raw.olist_order_payments_dataset p
     WHERE NOT EXISTS (SELECT 1 FROM raw.olist_orders_dataset o
                        WHERE o.order_id = p.order_id))         AS payment_orders_not_in_orders;

\echo '=== D. ORDERS <-> REVIEWS ==='
SELECT
  (SELECT count(*) FROM raw.olist_orders_dataset o
     WHERE NOT EXISTS (SELECT 1 FROM raw.olist_order_reviews_dataset r
                        WHERE r.order_id = o.order_id))         AS orders_with_no_review,
  (SELECT count(DISTINCT r.order_id) FROM raw.olist_order_reviews_dataset r
     WHERE NOT EXISTS (SELECT 1 FROM raw.olist_orders_dataset o
                        WHERE o.order_id = r.order_id))         AS review_orders_not_in_orders;

\echo '=== E. REVIEWS: how many orders carry more than one review? ==='
SELECT reviews_per_order, count(*) AS n_orders
FROM (SELECT order_id, count(*) AS reviews_per_order
      FROM raw.olist_order_reviews_dataset GROUP BY 1) t
GROUP BY 1 ORDER BY 1;

\echo '=== F. REVIEWS: sample of orders with multiple reviews ==='
SELECT r.order_id, r.review_id, r.review_score, r.review_creation_date, r.review_answer_timestamp
FROM raw.olist_order_reviews_dataset r
JOIN (SELECT order_id FROM raw.olist_order_reviews_dataset
      GROUP BY 1 HAVING count(*) > 1 ORDER BY 1 LIMIT 3) d
  ON d.order_id = r.order_id
ORDER BY r.order_id, r.review_creation_date;

\echo '=== G. REVIEWS: do duplicate review_ids differ, or are they identical rows? ==='
SELECT r.review_id, r.order_id, r.review_score, r.review_creation_date
FROM raw.olist_order_reviews_dataset r
JOIN (SELECT review_id FROM raw.olist_order_reviews_dataset
      GROUP BY 1 HAVING count(*) > 1 ORDER BY 1 LIMIT 3) d
  ON d.review_id = r.review_id
ORDER BY r.review_id;

\echo '=== H. PRODUCTS: nulls hidden by count(DISTINCT) ==='
SELECT count(*) AS rows,
       count(product_category_name) AS non_null_category,
       count(*) - count(product_category_name) AS null_category
FROM raw.olist_products_dataset;

\echo '=== I. CATEGORY TRANSLATION COVERAGE — both directions ==='
SELECT
  (SELECT count(DISTINCT p.product_category_name)
     FROM raw.olist_products_dataset p
     WHERE p.product_category_name IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM raw.product_category_name_translation t
                        WHERE t.product_category_name = p.product_category_name))
                                                        AS categories_with_no_translation,
  (SELECT count(*) FROM raw.product_category_name_translation t
     WHERE NOT EXISTS (SELECT 1 FROM raw.olist_products_dataset p
                        WHERE p.product_category_name = t.product_category_name))
                                                        AS translations_matching_no_product;

\echo '=== J. Which categories are untranslated, and how many products do they cover? ==='
SELECT p.product_category_name, count(*) AS n_products
FROM raw.olist_products_dataset p
WHERE p.product_category_name IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM raw.product_category_name_translation t
                   WHERE t.product_category_name = p.product_category_name)
GROUP BY 1 ORDER BY 2 DESC;

\echo '=== K. ORDER_ITEMS -> PRODUCTS / SELLERS ==='
SELECT
  (SELECT count(DISTINCT i.product_id) FROM raw.olist_order_items_dataset i
     WHERE NOT EXISTS (SELECT 1 FROM raw.olist_products_dataset p
                        WHERE p.product_id = i.product_id))  AS item_products_not_in_products,
  (SELECT count(DISTINCT i.seller_id) FROM raw.olist_order_items_dataset i
     WHERE NOT EXISTS (SELECT 1 FROM raw.olist_sellers_dataset s
                        WHERE s.seller_id = i.seller_id))    AS item_sellers_not_in_sellers;

\echo '=== L. ORDERS -> CUSTOMERS ==='
SELECT count(*) AS orders_with_no_customer
FROM raw.olist_orders_dataset o
WHERE NOT EXISTS (SELECT 1 FROM raw.olist_customers_dataset c
                   WHERE c.customer_id = o.customer_id);
