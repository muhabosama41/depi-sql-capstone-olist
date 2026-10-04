# DEPI SQL + Python Capstone — Olist Delivery Reliability

A modular CRISP-DM pipeline that turns the supplied messy Olist PostgreSQL seed into an order-level feature store for delivery-lateness prediction. SQL performs all cleaning, auditing, aggregation, imputation, winsorization, and feature engineering. Python uses a small `psycopg2` connection pool only to coordinate database work and streams CSV results with the standard-library `csv` module. No Pandas or Polars.

## Project objective

Help an e-commerce logistics team prioritize delivery-risk monitoring. The modelling target is `is_late_delivery`: **1** when `order_delivered_customer_date > order_estimated_delivery_date`, otherwise **0**. The modelling cohort contains only `delivered` orders with a purchase time and both delivery dates; records without a known outcome are excluded instead of being labelled as on-time.

Business success checks: complete outcome dates; one row per order; item-key duplicate resolution; source row counts recorded before joins; and SQL transformations executed inside PostgreSQL. No latency baseline is fabricated; capture it locally if your evaluator requires a measured before/after figure.

## Architecture

```text
olist_messy_seed.sql -> public source tables
                             |
                Phase 1: objective + source inventory/counts
                             |
                Phase 2: SQL metadata, EDA, quality audit
                             |
                Phase 3: SQL cleaning views + feature MV
                             |
                PostgreSQL cursor -> bounded fetchmany -> csv.writer
                             |
                  outputs/*.csv
```

Raw public tables remain unchanged. Phase 3 creates `analytics.clean_*` views and `analytics.olist_order_feature_store` materialized view. Re-running Phase 3 replaces those analytics objects and refreshes the CSV; it does not drop or rewrite seed tables.

## Repository map

```text
README.md, requirements.txt, .env.example
config.py, db.py, main.py, etl.py
scripts/phase1.py, phase2.py, phase3.py
sql/audit_queries.sql, data_cleaning.sql, feature_store.sql
notebooks/01_eda_scratchpad.ipynb, 02_feature_engineering_test.ipynb
outputs/phase2_eda_summary.csv
outputs/phase2_quality_audit.csv
outputs/feature_store_export.csv
```

The CSVs in this starter package contain headers only until you run it against your database; no data or results are invented.

## Requirements and setup (Windows PowerShell)

1. Install PostgreSQL and ensure `psql` is on PATH. Create a **dedicated empty database** for the messy exercise. The supplied seed contains `DROP TABLE IF EXISTS` statements and recreates public tables. Running it in a database you care about can destroy same-named tables.

```powershell
createdb -U postgres olist_db
psql -U postgres -d olist_db -v ON_ERROR_STOP=1 -f "C:\Users\DELL\Downloads\data sets\olist_create_scripts\olist_messy_seed.sql"
```

Use `olist_clean_seed.sql` only in a separate database if you want a clean comparison; never load both seeds into the same database. The seed files are inputs, not project scripts, and are not copied into this repository.

2. From this project directory, create an environment and install dependencies:

```powershell
py -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
Copy-Item .env.example .env
```

Edit `.env` with your PostgreSQL host, database, username, and password. Do not commit `.env`.

3. Run the full project or an individual phase:

```powershell
python main.py --all
python main.py --phase 1
python main.py --phase 2
python main.py --phase 3
```

Phase 1 checks the connection and prints exact baseline row counts before joins. Phase 2 inventories public tables, computes SQL-side null/blank and numeric statistics (including median), and runs integrity/range/regex checks before writing CSV reports. Phase 3 creates clean views and the materialized feature store, then streams rows to CSV in batches of 5,000.

## Data quality and transformations

- Null and whitespace-only fields are measured before cleaning; trimming, case normalization, and empty-to-NULL conversion happen in SQL views.
- Item rows are deduplicated with `ROW_NUMBER() OVER (PARTITION BY order_id, order_item_id ...)`.
- Missing/negative item price, freight and payment values are imputed/floored at zero; payment installments are floored at zero. The audit preserves counts from before remediation.
- Item price and freight are capped at SQL-computed 99th percentiles before order aggregation. For production predictive evaluation, estimate caps on training data only and persist them for validation/test scoring.
- Orphan item references are excluded from the feature store by joins to product and seller tables; orphan counts remain in the audit output.
- Payments and items aggregate independently to order grain before joining to avoid join fan-out.
- Customer history uses `COUNT`, `LAG`, and a rolling three-prior-order `SUM`, ordered by purchase time. The current order is excluded from history.
- The target uses delivered orders with complete outcome dates. Actual delivery timestamps and delivery-delay values are not predictor columns.

## Feature Store data dictionary

| Column | PostgreSQL type | Meaning / transformation |
|---|---|---|
| `order_id` | varchar | Unique order key; one row per labelled order. |
| `customer_id` | varchar | Olist customer record key. |
| `customer_key` | varchar | Stable customer ID, falling back to customer record ID. |
| `customer_state` | varchar | Trimmed uppercase state. |
| `order_purchase_timestamp` | timestamp | Purchase time, available at prediction time. |
| `purchase_month` | integer | Month derived from purchase timestamp. |
| `purchase_day_of_week` | integer | PostgreSQL DOW (Sunday=0). |
| `item_count` | bigint | Deduplicated items linked to valid product and seller. |
| `item_value_capped` | numeric(14,2) | Sum of prices after 99th-percentile cap. |
| `freight_value_capped` | numeric(14,2) | Sum of freight after 99th-percentile cap. |
| `avg_item_price_capped` | numeric(14,2) | Average capped item price. |
| `distinct_categories` | bigint | Number of distinct normalized product categories. |
| `product_category_bucket` | varchar | Modal order category mapped to selected major categories, `other`, or `unknown`. |
| `distinct_seller_states` | bigint | Number of seller states in the order. |
| `max_product_weight_g` | integer | Maximum available product weight. |
| `payment_value` | numeric(14,2) | Deduplicated payment sum; missing -> 0. |
| `max_payment_installments` | integer | Maximum nonnegative installment count; missing -> 0. |
| `payment_type_count` | bigint | Number of distinct normalized payment types. |
| `prior_customer_orders` | integer | Earlier labelled delivered orders for this customer. |
| `days_since_prior_purchase` | integer | Calendar days since the preceding labelled order; NULL if none. |
| `prior_three_order_value` | numeric(14,2) | Capped item value sum for up to three earlier orders; missing -> 0. |
| `promised_delivery_days` | numeric | Days from purchase to estimated delivery. |
| `is_late_delivery` | integer | Required binary target: late=1, otherwise 0. |

## Outputs

- `outputs/phase2_eda_summary.csv`: SQL row counts, null counts, numeric MIN/MAX/AVG/STDDEV/MEDIAN, and delivered-cohort target diagnostics.
- `outputs/phase2_quality_audit.csv`: schema inventory, source counts, nulls/blanks, malformed states, negative values, late deliveries, and orphan references.
- `outputs/feature_store_export.csv`: order-grain feature table streamed with `csv.writer`.

## Evaluation notes

The scripts match the supplied seeds' public Olist tables, including the messy seed's marketing tables. The local database is not available in this workspace, so the extracts are header-only and SQL execution against your PostgreSQL instance is unconfirmed. After running, compare the export row count to `SELECT COUNT(*) FROM analytics.olist_order_feature_store` and retain the audit outputs for submission.
