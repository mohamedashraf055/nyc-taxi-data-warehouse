import duckdb

con = duckdb.connect()
dec = "data/raw/yellow_tripdata_2024-12.parquet"
jan = "data/raw/yellow_tripdata_2025-01.parquet"

def cols(p):
    df = con.sql(f"DESCRIBE SELECT * FROM '{p}'").df()
    return dict(zip(df.column_name, df.column_type))

d, j = cols(dec), cols(jan)
print("Only in Dec:", set(d) - set(j))
print("Only in Jan:", set(j) - set(d))
for c in set(d) & set(j):
    if d[c] != j[c]:
        print("Type changed:", c, d[c], "->", j[c])
print("Comparison done")
