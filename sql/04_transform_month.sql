
USE taxi_dwh;
GO

DECLARE @m     CHAR(7) = '__MONTH__';
DECLARE @start DATE    = CAST(@m + '-01' AS DATE);
DECLARE @end   DATE    = DATEADD(MONTH, 1, @start);

SET XACT_ABORT ON;
BEGIN TRAN;

-- 1) امسح الشهر ده (عشان إعادة التشغيل ما تكررش الصفوف)
DELETE FROM dw.fact_trips     WHERE source_month = @m;
DELETE FROM dw.rejected_trips WHERE source_month = @m;

-- 2) صنّف كل صف: سبب رفض واحد بس (بالأولوية) أو NULL لو صالح
SELECT s.*,
  CASE
    WHEN tpep_pickup_datetime IS NULL OR tpep_dropoff_datetime IS NULL THEN 'null_datetime'
    WHEN tpep_dropoff_datetime < tpep_pickup_datetime                  THEN 'dropoff_before_pickup'
    WHEN tpep_pickup_datetime < @start OR tpep_pickup_datetime >= @end THEN 'pickup_outside_month'
    WHEN tpep_dropoff_datetime >= '2026-01-01'                         THEN 'dropoff_out_of_range'
    ELSE NULL
  END AS reject_reason
INTO #classified
FROM stg.yellow_trips s
WHERE s.source_month = @m;

-- 3) المرفوض
INSERT INTO dw.rejected_trips
SELECT * FROM #classified WHERE reject_reason IS NOT NULL;

-- 4) الصالح في fact_trips
INSERT INTO dw.fact_trips (
    source_month, pickup_date_key, pickup_time_key, dropoff_date_key, dropoff_time_key,
    pickup_zone_key, dropoff_zone_key, payment_type_key, rate_code_key, vendor_key,
    store_and_fwd_flag, passenger_count,
    trip_distance, trip_duration_min, fare_amount, extra, mta_tax, tip_amount,
    tolls_amount, improvement_surcharge, congestion_surcharge, airport_fee,
    cbd_congestion_fee, total_amount,
    is_negative_amount, is_zero_distance, is_zero_passengers)
SELECT
    c.source_month,
    YEAR(c.tpep_pickup_datetime)*10000 + MONTH(c.tpep_pickup_datetime)*100 + DAY(c.tpep_pickup_datetime),
    DATEPART(HOUR, c.tpep_pickup_datetime)*100 + DATEPART(MINUTE, c.tpep_pickup_datetime),
    YEAR(c.tpep_dropoff_datetime)*10000 + MONTH(c.tpep_dropoff_datetime)*100 + DAY(c.tpep_dropoff_datetime),
    DATEPART(HOUR, c.tpep_dropoff_datetime)*100 + DATEPART(MINUTE, c.tpep_dropoff_datetime),
    ISNULL(pz.zone_key, -1),
    ISNULL(dz.zone_key, -1),
    ISNULL(p.payment_type_key, -1),
    ISNULL(r.rate_code_key, -1),
    ISNULL(v.vendor_key, -1),
    c.store_and_fwd_flag,
    CAST(c.passenger_count AS INT),
    c.trip_distance,
    DATEDIFF(SECOND, c.tpep_pickup_datetime, c.tpep_dropoff_datetime) / 60.0,
    c.fare_amount, c.extra, c.mta_tax, c.tip_amount, c.tolls_amount,
    c.improvement_surcharge, c.congestion_surcharge, c.Airport_fee,
    c.cbd_congestion_fee, c.total_amount,
    CASE WHEN c.fare_amount < 0 OR c.total_amount < 0 THEN 1 ELSE 0 END,
    CASE WHEN c.trip_distance = 0 THEN 1 ELSE 0 END,
    CASE WHEN c.passenger_count = 0 THEN 1 ELSE 0 END
FROM #classified c
LEFT JOIN dw.dim_zone         pz ON pz.zone_key         = c.PULocationID
LEFT JOIN dw.dim_zone         dz ON dz.zone_key         = c.DOLocationID
LEFT JOIN dw.dim_payment_type p  ON p.payment_type_key  = c.payment_type
LEFT JOIN dw.dim_rate_code    r  ON r.rate_code_key     = c.RatecodeID
LEFT JOIN dw.dim_vendor       v  ON v.vendor_key        = c.VendorID
WHERE c.reject_reason IS NULL;

DROP TABLE #classified;
COMMIT;
GO