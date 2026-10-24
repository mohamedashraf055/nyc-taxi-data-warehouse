import duckdb

con = duckdb.connect()
p = "data/raw/yellow_tripdata_2025-01.parquet"

q = f'''
SELECT
  COUNT(*) AS total_rows,
  SUM(CASE WHEN fare_amount < 0 THEN 1 ELSE 0 END) AS negative_fare,
  SUM(CASE WHEN total_amount < 0 THEN 1 ELSE 0 END) AS negative_total,
  SUM(CASE WHEN tpep_dropoff_datetime < tpep_pickup_datetime THEN 1 ELSE 0 END) AS dropoff_before_pickup,
  SUM(CASE WHEN trip_distance = 0 THEN 1 ELSE 0 END) AS zero_distance,
  SUM(CASE WHEN passenger_count = 0 THEN 1 ELSE 0 END) AS zero_passengers,
  SUM(CASE WHEN passenger_count IS NULL THEN 1 ELSE 0 END) AS null_passengers,
  SUM(CASE WHEN tpep_pickup_datetime < '2025-01-01' OR tpep_pickup_datetime >= '2025-02-01' THEN 1 ELSE 0 END) AS outside_month
FROM '{p}'
'''
print(con.sql(q).df().T.to_string())
