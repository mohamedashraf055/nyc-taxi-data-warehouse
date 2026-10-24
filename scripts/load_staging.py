import pyodbc
import pyarrow.parquet as pq
import os
from dotenv import load_dotenv
load_dotenv()
PWD = os.environ["MSSQL_SA_PASSWORD"]

MONTH = "2025-01"
PATH = f"data/raw/yellow_tripdata_{MONTH}.parquet"
BATCH_SIZE = 50000

conn = pyodbc.connect(
    "DRIVER={ODBC Driver 18 for SQL Server};"
    "SERVER=127.0.0.1,14330;"
    "DATABASE=taxi_dwh;"
    f"UID=sa;PWD={PWD};"
    "TrustServerCertificate=yes;"
)
cur = conn.cursor()
cur.fast_executemany = True

cur.execute("DELETE FROM stg.yellow_trips WHERE source_month = ?", MONTH)
conn.commit()

insert_sql = "INSERT INTO stg.yellow_trips VALUES (" + ",".join(["?"] * 21) + ")"

pf = pq.ParquetFile(PATH)
total = 0
for batch in pf.iter_batches(batch_size=BATCH_SIZE):
    df = batch.to_pandas()
    df["source_month"] = MONTH
    df = df.astype(object).where(df.notna(), None)
    rows = [tuple(r) for r in df.itertuples(index=False, name=None)]
    cur.executemany(insert_sql, rows)
    conn.commit()
    total += len(rows)
    print(f"Loaded {total:,} rows")

cur.execute("SELECT COUNT(*) FROM stg.yellow_trips WHERE source_month = ?", MONTH)
print("Rows in staging:", cur.fetchone()[0])
conn.close()