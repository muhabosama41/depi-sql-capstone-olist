"""Small psycopg2 connection-pool wrapper; transformations stay in PostgreSQL."""
from contextlib import contextmanager
from psycopg2.pool import ThreadedConnectionPool
from config import DB_CONFIG

_pool = None

def _get_pool():
    global _pool
    if _pool is None:
        _pool = ThreadedConnectionPool(minconn=1, maxconn=4, **DB_CONFIG)
    return _pool

@contextmanager
def connection():
    pool = _get_pool()
    conn = pool.getconn()
    try:
        yield conn
    except Exception:
        conn.rollback()
        raise
    finally:
        if not conn.closed:
            conn.rollback()
        pool.putconn(conn, close=bool(conn.closed))

def close_pool():
    """Close pooled connections at process shutdown when needed."""
    global _pool
    if _pool is not None:
        _pool.closeall()
        _pool = None
