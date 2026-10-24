import duckdb

con = duckdb.connect()
path = "data/raw/yellow_tripdata_2025-01.parquet"

rows = con.sql(f"SELECT COUNT(*) FROM '{path}'").fetchone()[0]
print("Rows:", rows)

print(con.sql(f"DESCRIBE SELECT * FROM '{path}'").df().to_string())
