"""Phase 3: run SQL feature-store DDL and stream rows to CSV."""
import csv
from config import OUTPUT_DIR, SQL_DIR
from db import connection

def run():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    with connection() as conn:
        with conn.cursor() as cur:
            cur.execute((SQL_DIR / "data_cleaning.sql").read_text(encoding="utf-8-sig"))
            cur.execute((SQL_DIR / "feature_store.sql").read_text(encoding="utf-8-sig"))
            cur.execute("SELECT * FROM analytics.olist_order_feature_store ORDER BY order_id")
            path = OUTPUT_DIR / "feature_store_export.csv"
            with path.open("w", newline="", encoding="utf-8") as stream:
                writer = csv.writer(stream)
                writer.writerow([d.name for d in cur.description])
                while batch := cur.fetchmany(5000):
                    writer.writerows(batch)
        conn.commit()
    print(f"Phase 3 complete. Exported {path} in bounded batches using csv.writer.")
