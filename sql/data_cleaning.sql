-- SQL-side relational cleaning and deduplication. Raw tables are preserved.
CREATE SCHEMA IF NOT EXISTS analytics;
CREATE OR REPLACE VIEW analytics.clean_orders AS
SELECT BTRIM(order_id) order_id,BTRIM(customer_id) customer_id,LOWER(NULLIF(BTRIM(order_status),'')) order_status,
       order_purchase_timestamp,order_approved_at,order_delivered_carrier_date,order_delivered_customer_date,order_estimated_delivery_date
FROM (SELECT o.*,ROW_NUMBER() OVER(PARTITION BY BTRIM(order_id) ORDER BY order_purchase_timestamp NULLS LAST) rn
      FROM public.orders o WHERE NULLIF(BTRIM(order_id),'') IS NOT NULL) q WHERE rn=1;
CREATE OR REPLACE VIEW analytics.clean_order_items AS
SELECT BTRIM(order_id) order_id,order_item_id,BTRIM(product_id) product_id,BTRIM(seller_id) seller_id,shipping_limit_date,
       GREATEST(COALESCE(price,0),0)::numeric(12,2) price,GREATEST(COALESCE(freight_value,0),0)::numeric(12,2) freight_value
FROM (SELECT i.*,ROW_NUMBER() OVER(PARTITION BY BTRIM(order_id),order_item_id
      ORDER BY (product_id IS NOT NULL) DESC,(seller_id IS NOT NULL) DESC,(price IS NOT NULL) DESC) rn
      FROM public.order_items i WHERE NULLIF(BTRIM(order_id),'') IS NOT NULL AND order_item_id IS NOT NULL) q WHERE rn=1;
CREATE OR REPLACE VIEW analytics.clean_customers AS
SELECT BTRIM(customer_id) customer_id,NULLIF(BTRIM(customer_unique_id),'') customer_unique_id,customer_zip_code_prefix,
       NULLIF(LOWER(BTRIM(customer_city)),'') customer_city,UPPER(NULLIF(BTRIM(customer_state),'')) customer_state
FROM (SELECT c.*,ROW_NUMBER() OVER(PARTITION BY BTRIM(customer_id) ORDER BY (customer_unique_id IS NOT NULL) DESC) rn
      FROM public.customers c WHERE NULLIF(BTRIM(customer_id),'') IS NOT NULL) q WHERE rn=1;
CREATE OR REPLACE VIEW analytics.clean_products AS
SELECT q.product_id,
       COALESCE(NULLIF(LOWER(BTRIM(t.product_category_name_english)),''),q.product_category_name) product_category_name,
       q.product_weight_g,q.product_length_cm,q.product_height_cm,q.product_width_cm
FROM (
  SELECT BTRIM(product_id) product_id,NULLIF(LOWER(BTRIM(product_category_name)),'') product_category_name,
         product_weight_g,product_length_cm,product_height_cm,product_width_cm
  FROM (SELECT p.*,ROW_NUMBER() OVER(PARTITION BY BTRIM(product_id) ORDER BY product_id) rn
        FROM public.products p WHERE NULLIF(BTRIM(product_id),'') IS NOT NULL) dedup
  WHERE rn=1
) q
LEFT JOIN public.product_category_translation t
  ON LOWER(BTRIM(t.product_category_name))=q.product_category_name;
CREATE OR REPLACE VIEW analytics.clean_sellers AS
SELECT BTRIM(seller_id) seller_id,seller_zip_code_prefix,NULLIF(LOWER(BTRIM(seller_city)),'') seller_city,
       UPPER(NULLIF(BTRIM(seller_state),'')) seller_state
FROM (SELECT s.*,ROW_NUMBER() OVER(PARTITION BY BTRIM(seller_id) ORDER BY seller_id) rn
      FROM public.sellers s WHERE NULLIF(BTRIM(seller_id),'') IS NOT NULL) q WHERE rn=1;
CREATE OR REPLACE VIEW analytics.clean_order_payments AS
SELECT BTRIM(order_id) order_id,payment_sequential,LOWER(NULLIF(BTRIM(payment_type),'')) payment_type,
       GREATEST(COALESCE(payment_installments,0),0) payment_installments,GREATEST(COALESCE(payment_value,0),0)::numeric(12,2) payment_value
FROM (SELECT p.*,ROW_NUMBER() OVER(PARTITION BY BTRIM(order_id),payment_sequential
      ORDER BY (payment_value IS NOT NULL) DESC,payment_value DESC) rn
      FROM public.order_payments p WHERE NULLIF(BTRIM(order_id),'') IS NOT NULL) q WHERE rn=1;
