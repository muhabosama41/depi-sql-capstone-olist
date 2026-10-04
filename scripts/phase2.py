"""Phase 2: structural inventory, database-side EDA, and quality log."""
import csv
from psycopg2 import sql
from config import OUTPUT_DIR
from config import SQL_DIR
from db import connection

def _write(path, header, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(header)
        writer.writerows(rows)

def run():
    eda, audit = [], []
    with connection() as conn, conn.cursor() as cur:
        cur.execute("""SELECT table_name,column_name,data_type,is_nullable
                      FROM information_schema.columns WHERE table_schema='public'
                      ORDER BY table_name,ordinal_position""")
        columns = cur.fetchall()
        if not columns:
            raise RuntimeError("No public tables found. Load the supplied Olist seed first.")
        cur.execute("""SELECT tc.table_name,kcu.column_name,tc.constraint_type,
                            ccu.table_name,ccu.column_name
                     FROM information_schema.table_constraints tc
                     JOIN information_schema.key_column_usage kcu
                       ON tc.constraint_name=kcu.constraint_name AND tc.table_schema=kcu.table_schema
                     LEFT JOIN information_schema.constraint_column_usage ccu
                       ON ccu.constraint_name=tc.constraint_name AND ccu.table_schema=tc.table_schema
                     WHERE tc.table_schema='public' AND tc.constraint_type IN ('PRIMARY KEY','FOREIGN KEY','UNIQUE')
                     ORDER BY tc.table_name,tc.constraint_type,kcu.ordinal_position""")
        constraints = cur.fetchall()
        by_table = {}
        for table, col, typ, nullable in columns:
            by_table.setdefault(table, []).append((col, typ, nullable))
            audit.append(("schema", table, col, typ, nullable, "", "column inventory"))
        for table, col, kind, ref_table, ref_col in constraints:
            details = kind if not ref_table else f"{kind} references {ref_table}.{ref_col}"
            audit.append(("constraint", table, col, "", "NO", "", details))
        for table, cols in by_table.items():
            ident = sql.Identifier("public", table)
            cur.execute(sql.SQL("SELECT COUNT(*) FROM {}").format(ident))
            n = cur.fetchone()[0]
            audit.append(("row_count", table, "*", "bigint", "NO", n, "baseline before joins"))
            for col, typ, nullable in cols:
                cur.execute(sql.SQL("SELECT COUNT(*) FILTER (WHERE {} IS NULL), COUNT(*) FILTER (WHERE {}::text ~ '^\\s*$') FROM {}").format(sql.Identifier(col), sql.Identifier(col), ident))
                nulls, blanks = cur.fetchone()
                if nulls:
                    audit.append(("missing", table, col, typ, nullable, nulls, "SQL NULL values"))
                if typ in ("character varying", "character", "text") and blanks:
                    audit.append(("blank_text", table, col, typ, nullable, blanks, "empty or whitespace-only values"))
                if typ in ("integer", "bigint", "numeric", "real", "double precision"):
                    cur.execute(sql.SQL("""SELECT COUNT(*), MIN({0}), MAX({0}), AVG({0}::numeric),
                        STDDEV_SAMP({0}::numeric), percentile_cont(0.5::double precision) WITHIN GROUP (ORDER BY {0}::double precision)
                        FROM {1} WHERE {0} IS NOT NULL""").format(sql.Identifier(col), ident))
                    cnt, low, high, avg, sd, median = cur.fetchone()
                    eda.append((table, "numeric_distribution", col, cnt, nulls, low, high, avg, sd, median))
        cur.execute("""SELECT 'customers','customer_state',COUNT(*) FROM public.customers
                      WHERE customer_state IS NOT NULL AND BTRIM(customer_state) !~ '^[A-Za-z]{2}$'
                      UNION ALL SELECT 'sellers','seller_state',COUNT(*) FROM public.sellers
                      WHERE seller_state IS NOT NULL AND BTRIM(seller_state) !~ '^[A-Za-z]{2}$'
                      UNION ALL SELECT 'order_items','price',COUNT(*) FROM public.order_items WHERE price < 0
                      UNION ALL SELECT 'order_items','freight_value',COUNT(*) FROM public.order_items WHERE freight_value < 0
                      UNION ALL SELECT 'orders','delivery_dates',COUNT(*) FROM public.orders
                      WHERE order_delivered_customer_date > order_estimated_delivery_date
                      UNION ALL SELECT 'order_items','orphan_order_id',COUNT(*) FROM public.order_items i
                      LEFT JOIN public.orders o USING(order_id) WHERE o.order_id IS NULL
                      UNION ALL SELECT 'order_items','orphan_product_id',COUNT(*) FROM public.order_items i
                      LEFT JOIN public.products p USING(product_id) WHERE p.product_id IS NULL
                      UNION ALL SELECT 'order_items','orphan_seller_id',COUNT(*) FROM public.order_items i
                      LEFT JOIN public.sellers s USING(seller_id) WHERE s.seller_id IS NULL""")
        for table, col, count in cur.fetchall():
            audit.append(("defect", table, col, "", "", count, "regex, range, lateness, or referential-integrity check"))
        cur.execute("""WITH caps AS (
                       SELECT percentile_cont(0.99::double precision) WITHIN GROUP (ORDER BY price) price_p99,
                              percentile_cont(0.99::double precision) WITHIN GROUP (ORDER BY freight_value) freight_p99
                       FROM public.order_items)
                     SELECT 'price', COUNT(*) FROM public.order_items,caps WHERE price>price_p99
                     UNION ALL
                     SELECT 'freight_value', COUNT(*) FROM public.order_items,caps WHERE freight_value>freight_p99""")
        for col, count in cur.fetchall():
            audit.append(("outlier_cap", "order_items", col, "numeric", "YES", count, "records above SQL-computed 99th percentile"))
        cur.execute((SQL_DIR / "audit_queries.sql").read_text(encoding="utf-8-sig"))
        eda.extend(cur.fetchall())
    _write(OUTPUT_DIR / "phase2_eda_summary.csv", ["table_name","metric","column_name","row_count","null_count","min_value","max_value","avg_value","stddev_value","median_value"], eda)
    _write(OUTPUT_DIR / "phase2_quality_audit.csv", ["audit_type","table_name","column_name","data_type","is_nullable","count","details"], audit)
    print(f"Phase 2 complete. Wrote {len(eda)} SQL summary rows and {len(audit)} audit rows.")
