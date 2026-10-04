-- Labelled, order-grain feature store. SQL-only preparation and window features.
DROP MATERIALIZED VIEW IF EXISTS analytics.olist_order_feature_store;
CREATE MATERIALIZED VIEW analytics.olist_order_feature_store AS
WITH price_caps AS (
  SELECT percentile_cont(0.99::double precision) WITHIN GROUP(ORDER BY price::double precision)::numeric price_p99,
         percentile_cont(0.99::double precision) WITHIN GROUP(ORDER BY freight_value::double precision)::numeric freight_p99
  FROM analytics.clean_order_items
), item_base AS (
  SELECT i.*,p.product_category_name,p.product_weight_g,s.seller_state,caps.price_p99,caps.freight_p99
  FROM analytics.clean_order_items i CROSS JOIN price_caps caps
  JOIN analytics.clean_products p USING(product_id)
  JOIN analytics.clean_sellers s USING(seller_id)
), item_features AS (
  SELECT order_id,COUNT(*) item_count,SUM(LEAST(price,price_p99))::numeric(14,2) item_value_capped,
         SUM(LEAST(freight_value,freight_p99))::numeric(14,2) freight_value_capped,
         AVG(LEAST(price,price_p99))::numeric(14,2) avg_item_price_capped,
         COUNT(DISTINCT product_category_name) distinct_categories,
         MODE() WITHIN GROUP(ORDER BY product_category_name) dominant_category,
         COUNT(DISTINCT seller_state) distinct_seller_states,MAX(product_weight_g) max_product_weight_g
  FROM item_base GROUP BY order_id
), payment_features AS (
  SELECT order_id,SUM(payment_value)::numeric(14,2) payment_value,MAX(payment_installments) max_payment_installments,
         COUNT(DISTINCT payment_type) payment_type_count FROM analytics.clean_order_payments GROUP BY order_id
), order_context AS (
  SELECT o.order_id,o.customer_id,COALESCE(c.customer_unique_id,o.customer_id) customer_key,c.customer_state,
         o.order_purchase_timestamp,
         EXTRACT(EPOCH FROM(o.order_estimated_delivery_date-o.order_purchase_timestamp))/86400.0 promised_delivery_days,
         EXTRACT(MONTH FROM o.order_purchase_timestamp)::integer purchase_month,
         EXTRACT(DOW FROM o.order_purchase_timestamp)::integer purchase_day_of_week,
         i.item_count,i.item_value_capped,i.freight_value_capped,i.avg_item_price_capped,
         i.distinct_categories,
         CASE WHEN i.dominant_category IN ('bed_bath_table','health_beauty','sports_leisure','computers_accessories','furniture_decor','housewares','watches_gifts','telephony') THEN i.dominant_category
              WHEN i.dominant_category IS NULL THEN 'unknown' ELSE 'other' END product_category_bucket,
         i.distinct_seller_states,i.max_product_weight_g,
         p.payment_value,p.max_payment_installments,p.payment_type_count,
         CASE WHEN o.order_delivered_customer_date>o.order_estimated_delivery_date THEN 1 ELSE 0 END is_late_delivery
  FROM analytics.clean_orders o JOIN analytics.clean_customers c USING(customer_id)
  JOIN item_features i USING(order_id) LEFT JOIN payment_features p USING(order_id)
  WHERE o.order_status='delivered' AND o.order_purchase_timestamp IS NOT NULL
    AND o.order_delivered_customer_date IS NOT NULL AND o.order_estimated_delivery_date IS NOT NULL
), history AS (
  SELECT *,COUNT(*) OVER(PARTITION BY customer_key ORDER BY order_purchase_timestamp,order_id
                         ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) prior_customer_orders,
         LAG(order_purchase_timestamp) OVER(PARTITION BY customer_key ORDER BY order_purchase_timestamp,order_id) prior_purchase_timestamp,
         SUM(item_value_capped) OVER(PARTITION BY customer_key ORDER BY order_purchase_timestamp,order_id
                         ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING)::numeric(14,2) prior_three_order_value
  FROM order_context
)
SELECT order_id,customer_id,customer_key,customer_state,order_purchase_timestamp,purchase_month,purchase_day_of_week,
       item_count,item_value_capped,freight_value_capped,avg_item_price_capped,distinct_categories,product_category_bucket,
       distinct_seller_states,max_product_weight_g,COALESCE(payment_value,0)::numeric(14,2) payment_value,
       COALESCE(max_payment_installments,0) max_payment_installments,COALESCE(payment_type_count,0) payment_type_count,
       GREATEST(prior_customer_orders,0)::integer prior_customer_orders,
       CASE WHEN prior_purchase_timestamp IS NULL THEN NULL
            ELSE order_purchase_timestamp::date-prior_purchase_timestamp::date END days_since_prior_purchase,
       COALESCE(prior_three_order_value,0)::numeric(14,2) prior_three_order_value,
       ROUND(promised_delivery_days::numeric,2) promised_delivery_days,is_late_delivery
FROM history;
CREATE UNIQUE INDEX olist_order_feature_store_order_id_uq ON analytics.olist_order_feature_store(order_id);
