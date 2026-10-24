import os
import re
import urllib.request
from datetime import datetime, timedelta

import pymssql
import pyarrow.parquet as pq
from airflow import DAG
from airflow.operators.python import PythonOperator

RAW_DIR = "/opt/airflow/data/raw"
SQL_DIR = "/opt/airflow/sql"
URL = "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_{month}.parquet"
BATCH_SIZE = 50000

def get_conn():
    return pymssql.connect(server="warehouse-db", user="sa",
                           password=os.environ["MSSQL_PASSWORD"],
                           database="taxi_dwh", autocommit=False)

def download(month, **_):
    path = f"{RAW_DIR}/yellow_tripdata_{month}.parquet"
    if os.path.exists(path):
        print(f"Already exists: {path}")
        return
    os.makedirs(RAW_DIR, exist_ok=True)
    urllib.request.urlretrieve(URL.format(month=month), path)
    print(f"Downloaded: {path}")


def load_staging(month, **_):
    path = f"{RAW_DIR}/yellow_tripdata_{month}.parquet"
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("DELETE FROM stg.yellow_trips WHERE source_month = %s", (month,))
    conn.commit()

    insert_sql = "INSERT INTO stg.yellow_trips VALUES (" + ",".join(["%s"] * 21) + ")"
    pf = pq.ParquetFile(path)
    total = 0
    for batch in pf.iter_batches(batch_size=BATCH_SIZE):
        df = batch.to_pandas()
        # الشهور القديمة ممكن ماتحتويش على cbd_congestion_fee
        if "cbd_congestion_fee" not in df.columns:
            df["cbd_congestion_fee"] = None
        df["source_month"] = month
        df = df.astype(object).where(df.notna(), None)
        cols = ["VendorID", "tpep_pickup_datetime", "tpep_dropoff_datetime",
                "passenger_count", "trip_distance", "RatecodeID",
                "store_and_fwd_flag", "PULocationID", "DOLocationID",
                "payment_type", "fare_amount", "extra", "mta_tax", "tip_amount",
                "tolls_amount", "improvement_surcharge", "total_amount",
                "congestion_surcharge", "Airport_fee", "cbd_congestion_fee",
                "source_month"]
        rows = [tuple(r) for r in df[cols].itertuples(index=False, name=None)]
        cur.executemany(insert_sql, rows)
        conn.commit()
        total += len(rows)
        print(f"Loaded {total:,} rows")
    conn.close()


def transform(month, **_):
    with open(f"{SQL_DIR}/04_transform_month.sql", encoding="utf-8") as f:
        sql = f.read().replace("__MONTH__", month)
    # نقسم على GO ونتجاهل USE
    batches = [b.strip() for b in re.split(r"^\s*GO\s*$", sql, flags=re.M | re.I)]
    conn = get_conn()
    conn.autocommit(True)  # الـ SQL فيه BEGIN TRAN / COMMIT بتاعه
    cur = conn.cursor()
    for b in batches:
        if not b or b.upper().startswith("USE "):
            continue
        # آخر دفعة هي المطابقة SELECT، منفذهاش هنا
        if b.lstrip().upper().startswith("-- 5)"):
            continue
        cur.execute(b)
    conn.close()


def reconcile(month, **_):
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("SELECT COUNT(*) FROM stg.yellow_trips WHERE source_month = %s", (month,))
    s = cur.fetchone()[0]
    cur.execute("SELECT COUNT(*) FROM dw.fact_trips WHERE source_month = %s", (month,))
    f = cur.fetchone()[0]
    cur.execute("SELECT COUNT(*) FROM dw.rejected_trips WHERE source_month = %s", (month,))
    r = cur.fetchone()[0]
    conn.close()
    print(f"{month}: staging={s:,} fact={f:,} rejected={r:,}")
    if s != f + r:
        raise ValueError(f"Reconciliation failed for {month}: {s} != {f} + {r}")


with DAG(
    dag_id="nyc_taxi_monthly",
    start_date=datetime(2024, 12, 1),
    end_date=datetime(2025, 6, 30),
    schedule="@monthly",
    catchup=True,
    max_active_runs=1,
    default_args={"retries": 2, "retry_delay": timedelta(minutes=2)},
) as dag:
    kw = {"month": "{{ ds[:7] }}"}
    t1 = PythonOperator(task_id="download", python_callable=download, op_kwargs=kw)
    t2 = PythonOperator(task_id="load_staging", python_callable=load_staging, op_kwargs=kw)
    t3 = PythonOperator(task_id="transform", python_callable=transform, op_kwargs=kw)
    t4 = PythonOperator(task_id="reconcile", python_callable=reconcile, op_kwargs=kw)
    t1 >> t2 >> t3 >> t4