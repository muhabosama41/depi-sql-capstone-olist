"""Environment-backed PostgreSQL connection settings."""
import os
from pathlib import Path
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parent
load_dotenv(ROOT / ".env")
DB_CONFIG = {
    "host": os.getenv("PGHOST", "localhost"),
    "port": int(os.getenv("PGPORT", "5432")),
    "dbname": os.getenv("PGDATABASE", "olist_db"),
    "user": os.getenv("PGUSER", "postgres"),
    "password": os.getenv("PGPASSWORD", ""),
    "sslmode": os.getenv("PGSSLMODE", "prefer"),
    "connect_timeout": int(os.getenv("PGCONNECT_TIMEOUT", "10")),
}
SQL_DIR = ROOT / "sql"
OUTPUT_DIR = ROOT / "outputs"
