"""Phase 1: business objective, target, source readiness, and baseline counts."""
from db import connection
from psycopg2 import sql

REQUIRED = ("orders", "order_items", "customers", "products", "sellers", "order_payments")

def run():
    print("Objective: identify late-delivery orders for logistics intervention.")
    print("Target: 1 when delivered_customer_date > estimated_delivery_date, else 0.")
    print("Only delivered orders with both dates are labelled, avoiding false negatives and label leakage.")
    print("Success criteria: zero duplicate order-item keys after cleaning; complete target labels; SQL-side transformations.")
    with connection() as conn, conn.cursor() as cur:
        cur.execute("SELECT current_database(), current_user, version()")
        database, user, version = cur.fetchone()
        cur.execute("SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE'")
        present = {r[0] for r in cur.fetchall()}
        missing = sorted(set(REQUIRED) - present)
        if missing:
            raise RuntimeError("Missing source tables in public schema: " + ", ".join(missing) + ". Load olist_messy_seed.sql first; see README.")
        print(f"Connected to {database} as {user}; {version.split(',')[0]}.")
        for table in REQUIRED:
            cur.execute(sql.SQL("SELECT COUNT(*) FROM public.{}").format(sql.Identifier(table)))
            print(f"public.{table}: {cur.fetchone()[0]:,} rows")
    print("Phase 1 complete.")
