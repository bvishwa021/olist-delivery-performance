-- =====================================================================
-- Olist — Phase 1, Step A/B: raw layer DDL + load
-- Run with:  psql -U postgres -d olist -f 01_raw_load.sql
-- or paste into an interactive psql session connected to `olist`.
--
-- Every column is text. Nothing is cast, renamed, or filtered here.
-- The raw schema is a faithful mirror of the CSV files, source typos
-- included. All transformation happens in the clean schema.
-- =====================================================================

DROP TABLE IF EXISTS raw.olist_customers_dataset;
CREATE TABLE raw.olist_customers_dataset (
    customer_id              text,
    customer_unique_id       text,
    customer_zip_code_prefix text,
    customer_city            text,
    customer_state           text
);

DROP TABLE IF EXISTS raw.olist_orders_dataset;
CREATE TABLE raw.olist_orders_dataset (
    order_id                      text,
    customer_id                   text,
    order_status                  text,
    order_purchase_timestamp      text,
    order_approved_at             text,
    order_delivered_carrier_date  text,
    order_delivered_customer_date text,
    order_estimated_delivery_date text
);

DROP TABLE IF EXISTS raw.olist_order_items_dataset;
CREATE TABLE raw.olist_order_items_dataset (
    order_id            text,
    order_item_id       text,
    product_id          text,
    seller_id           text,
    shipping_limit_date text,
    price               text,
    freight_value       text
);

DROP TABLE IF EXISTS raw.olist_order_payments_dataset;
CREATE TABLE raw.olist_order_payments_dataset (
    order_id             text,
    payment_sequential   text,
    payment_type         text,
    payment_installments text,
    payment_value        text
);

DROP TABLE IF EXISTS raw.olist_order_reviews_dataset;
CREATE TABLE raw.olist_order_reviews_dataset (
    review_id              text,
    order_id               text,
    review_score           text,
    review_comment_title   text,
    review_comment_message text,
    review_creation_date   text,
    review_answer_timestamp text
);

-- NOTE: 'lenght' is misspelled in the source files. Preserved deliberately.
DROP TABLE IF EXISTS raw.olist_products_dataset;
CREATE TABLE raw.olist_products_dataset (
    product_id                 text,
    product_category_name      text,
    product_name_lenght        text,
    product_description_lenght text,
    product_photos_qty         text,
    product_weight_g           text,
    product_length_cm          text,
    product_height_cm          text,
    product_width_cm           text
);

DROP TABLE IF EXISTS raw.olist_sellers_dataset;
CREATE TABLE raw.olist_sellers_dataset (
    seller_id                text,
    seller_zip_code_prefix   text,
    seller_city              text,
    seller_state             text
);

DROP TABLE IF EXISTS raw.product_category_name_translation;
CREATE TABLE raw.product_category_name_translation (
    product_category_name         text,
    product_category_name_english text
);

-- =====================================================================
-- Load.  \copy is a psql meta-command: it runs client-side, reads the
-- file as YOU, and must sit on a SINGLE LINE. Do not wrap these.
-- =====================================================================

\copy raw.olist_customers_dataset FROM 'C:\data\olist\olist_customers_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy raw.olist_orders_dataset FROM 'C:\data\olist\olist_orders_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy raw.olist_order_items_dataset FROM 'C:\data\olist\olist_order_items_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy raw.olist_order_payments_dataset FROM 'C:\data\olist\olist_order_payments_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy raw.olist_order_reviews_dataset FROM 'C:\data\olist\olist_order_reviews_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy raw.olist_products_dataset FROM 'C:\data\olist\olist_products_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy raw.olist_sellers_dataset FROM 'C:\data\olist\olist_sellers_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy raw.product_category_name_translation FROM 'C:\data\olist\product_category_name_translation.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

-- =====================================================================
-- Baseline counts — checklist step 2.
-- These become the reference numbers for the rest of the project.
-- =====================================================================

SELECT 'customers'   AS table_name, count(*) FROM raw.olist_customers_dataset
UNION ALL SELECT 'orders',          count(*) FROM raw.olist_orders_dataset
UNION ALL SELECT 'order_items',     count(*) FROM raw.olist_order_items_dataset
UNION ALL SELECT 'payments',        count(*) FROM raw.olist_order_payments_dataset
UNION ALL SELECT 'reviews',         count(*) FROM raw.olist_order_reviews_dataset
UNION ALL SELECT 'products',        count(*) FROM raw.olist_products_dataset
UNION ALL SELECT 'sellers',         count(*) FROM raw.olist_sellers_dataset
UNION ALL SELECT 'translation',     count(*) FROM raw.product_category_name_translation
ORDER BY 1;
