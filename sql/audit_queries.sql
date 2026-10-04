-- SQL-side EDA additions and source integrity diagnostics.
SELECT 'orders'::text AS table_name,'target_cohort'::text AS metric,'is_late_delivery'::text AS column_name,
       COUNT(*)::bigint AS row_count,0::bigint AS null_count,
       NULL::numeric AS min_value,NULL::numeric AS max_value,AVG(CASE WHEN order_delivered_customer_date > order_estimated_delivery_date THEN 1.0 ELSE 0.0 END)::numeric AS avg_value,
       NULL::numeric AS stddev_value,NULL::numeric AS median_value
FROM public.orders WHERE LOWER(BTRIM(order_status))='delivered'
  AND order_delivered_customer_date IS NOT NULL AND order_estimated_delivery_date IS NOT NULL
UNION ALL
SELECT 'order_items','duplicate_item_key','order_id/order_item_id',COUNT(*)::bigint,0,NULL,NULL,NULL,NULL,NULL
FROM (SELECT order_id,order_item_id FROM public.order_items GROUP BY order_id,order_item_id HAVING COUNT(*)>1) d
UNION ALL
SELECT 'order_items','orphan_customer_order','order_id',COUNT(*)::bigint,0,NULL,NULL,NULL,NULL,NULL
FROM public.order_items i LEFT JOIN public.orders o USING(order_id) WHERE o.order_id IS NULL
UNION ALL
SELECT 'order_items','orphan_product','product_id',COUNT(*)::bigint,0,NULL,NULL,NULL,NULL,NULL
FROM public.order_items i LEFT JOIN public.products p USING(product_id) WHERE p.product_id IS NULL
UNION ALL
SELECT 'order_items','orphan_seller','seller_id',COUNT(*)::bigint,0,NULL,NULL,NULL,NULL,NULL
FROM public.order_items i LEFT JOIN public.sellers s USING(seller_id) WHERE s.seller_id IS NULL;
