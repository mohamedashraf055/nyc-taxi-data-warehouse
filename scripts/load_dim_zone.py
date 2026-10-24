import pandas as pd
import pyodbc
import os
from dotenv import load_dotenv
load_dotenv()
PWD = os.environ["MSSQL_SA_PASSWORD"]

df = pd.read_csv("data/raw/taxi_zone_lookup.csv")
df = df.fillna("Unknown")

conn = pyodbc.connect(
    "DRIVER={ODBC Driver 18 for SQL Server};"
    "SERVER=127.0.0.1,14330;"
    "DATABASE=taxi_dwh;"
    f"UID=sa;PWD={PWD};"
    "TrustServerCertificate=yes;"
)
cur = conn.cursor()

cur.execute("DELETE FROM dw.dim_zone WHERE zone_key <> -1")


conn.commit()

rows = list(df.itertuples(index=False, name=None))
cur.executemany(
    "INSERT INTO dw.dim_zone (zone_key, borough, zone_name, service_zone) VALUES (?, ?, ?, ?)",
    rows,
)
conn.commit()

# 5) تحقق
cur.execute("SELECT COUNT(*) FROM dw.dim_zone")
print("Rows in dim_zone:", cur.fetchone()[0])
conn.close()