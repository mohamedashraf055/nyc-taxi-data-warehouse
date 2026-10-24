SELECT name FROM sys.databases;

USE taxi_dwh;
GO
CREATE SCHEMA stg;
GO
CREATE SCHEMA dw;
GO

USE taxi_dwh;
GO

CREATE TABLE stg.yellow_trips (
    VendorID              INT,
    tpep_pickup_datetime  DATETIME2,
    tpep_dropoff_datetime DATETIME2,
    passenger_count       BIGINT,
    trip_distance         FLOAT,
    RatecodeID            BIGINT,
    store_and_fwd_flag    VARCHAR(1),
    PULocationID          INT,
    DOLocationID          INT,
    payment_type          BIGINT,
    fare_amount           FLOAT,
    extra                 FLOAT,
    mta_tax               FLOAT,
    tip_amount            FLOAT,
    tolls_amount          FLOAT,
    improvement_surcharge FLOAT,
    total_amount          FLOAT,
    congestion_surcharge  FLOAT,
    Airport_fee           FLOAT,
    cbd_congestion_fee    FLOAT,
    source_month          CHAR(7)
);
GO


USE taxi_dwh;

SELECT payment_type, COUNT(*) AS trips
FROM stg.yellow_trips
GROUP BY payment_type
ORDER BY trips DESC;


SELECT VendorID, COUNT(*) AS trips
FROM stg.yellow_trips
GROUP BY VendorID
ORDER BY trips DESC;

SELECT RatecodeID, COUNT(*) AS trips
FROM stg.yellow_trips
GROUP BY RatecodeID
ORDER BY trips DESC;

SELECT COUNT(*) FROM stg.yellow_trips
WHERE payment_type = 0 AND RatecodeID IS NULL AND passenger_count IS NULL;

USE taxi_dwh;
GO

-- 1) طريقة الدفع
CREATE TABLE dw.dim_payment_type (
    payment_type_key  INT          NOT NULL PRIMARY KEY,
    payment_type_name VARCHAR(50)  NOT NULL
);
GO

USE taxi_dwh;
GO

-- 2) شركة التاكسي
CREATE TABLE dw.dim_vendor (
    vendor_key   INT          NOT NULL PRIMARY KEY,
    vendor_name  VARCHAR(80)  NOT NULL
);
GO

-- 3) نوع التعريفة
CREATE TABLE dw.dim_rate_code (
    rate_code_key   INT          NOT NULL PRIMARY KEY,
    rate_code_name  VARCHAR(50)  NOT NULL
);
GO

USE taxi_dwh;
GO

CREATE TABLE dw.dim_zone (
    zone_key       INT           NOT NULL PRIMARY KEY,
    borough        VARCHAR(50)   NOT NULL,
    zone_name      VARCHAR(100)  NOT NULL,
    service_zone   VARCHAR(50)   NOT NULL
);
GO


-------------------------------------------------------------------------------

INSERT INTO dw.dim_payment_type (payment_type_key, payment_type_name) VALUES
(-1, 'Unknown'),
(0,  'Flex Fare (to verify)'),
(1,  'Credit card'),
(2,  'Cash'),
(3,  'No charge'),
(4,  'Dispute'),
(5,  'Unknown'),
(6,  'Voided trip');
GO



INSERT INTO dw.dim_vendor (vendor_key, vendor_name) VALUES
(-1, 'Unknown'),
(1,  'Creative Mobile Technologies'),
(2,  'VeriFone / Curb (to verify)'),
(6,  'Myle Technologies (to verify)'),
(7,  'Helix (to verify)');
GO



INSERT INTO dw.dim_rate_code (rate_code_key, rate_code_name) VALUES
(-1, 'Unknown'),
(1,  'Standard rate'),
(2,  'JFK'),
(3,  'Newark'),
(4,  'Nassau or Westchester'),
(5,  'Negotiated fare'),
(6,  'Group ride'),
(99, 'Unknown / other (to verify)');
GO

USE taxi_dwh;
GO

UPDATE dw.dim_payment_type SET payment_type_name = 'Flex Fare trip'   WHERE payment_type_key = 0;
UPDATE dw.dim_vendor SET vendor_name = 'Curb Mobility, LLC'           WHERE vendor_key = 2;
UPDATE dw.dim_vendor SET vendor_name = 'Myle Technologies Inc'        WHERE vendor_key = 6;
UPDATE dw.dim_vendor SET vendor_name = 'Helix'                        WHERE vendor_key = 7;
UPDATE dw.dim_rate_code SET rate_code_name = 'Null/unknown'           WHERE rate_code_key = 99;
GO

SELECT * FROM dw.dim_payment_type ORDER BY payment_type_key;
SELECT * FROM dw.dim_vendor ORDER BY vendor_key;
SELECT * FROM dw.dim_rate_code ORDER BY rate_code_key;


INSERT INTO dw.dim_zone (zone_key, borough, zone_name, service_zone)
VALUES (-1, 'Unknown', 'Unknown', 'Unknown');
GO

SELECT * FROM dw.dim_zone;

  --------------------------------------------
  USE taxi_dwh;
GO

CREATE TABLE dw.dim_date (
    date_key     INT          NOT NULL PRIMARY KEY,
    full_date    DATE         NOT NULL,
    [year]       INT          NOT NULL,
    [month]      INT          NOT NULL,
    month_name   VARCHAR(20)  NOT NULL,
    [day]        INT          NOT NULL,
    day_of_week  INT          NOT NULL,
    day_name     VARCHAR(20)  NOT NULL,
    is_weekend   BIT          NOT NULL
);
GO

-- يولّد كل الأيام من 2024-01-01 لـ 2025-12-31 تلقائياً
WITH dates AS (
    SELECT CAST('2024-01-01' AS DATE) AS d
    UNION ALL
    SELECT DATEADD(DAY, 1, d) FROM dates WHERE d < '2025-12-31'
)
INSERT INTO dw.dim_date
SELECT
    YEAR(d) * 10000 + MONTH(d) * 100 + DAY(d),
    d,
    YEAR(d),
    MONTH(d),
    DATENAME(MONTH, d),
    DAY(d),
    ((DATEPART(WEEKDAY, d) + @@DATEFIRST - 2) % 7) + 1,   -- 1 = Monday ... 7 = Sunday
    DATENAME(WEEKDAY, d),
    CASE WHEN ((DATEPART(WEEKDAY, d) + @@DATEFIRST - 2) % 7) + 1 IN (6, 7) THEN 1 ELSE 0 END
FROM dates
OPTION (MAXRECURSION 1000);
GO

SELECT COUNT(*) AS days, MIN(full_date) AS first_day, MAX(full_date) AS last_day
FROM dw.dim_date;


------------------------------------------------------------------------------------------
USE taxi_dwh;
GO

CREATE TABLE dw.dim_time (
    time_key     INT          NOT NULL PRIMARY KEY,  -- مثال: 1430 = 14:30
    [hour]       INT          NOT NULL,
    [minute]     INT          NOT NULL,
    time_label   CHAR(5)      NOT NULL,              -- مثال: '14:30'
    day_period   VARCHAR(20)  NOT NULL               -- الفترة من اليوم
);
GO

WITH minutes AS (
    SELECT 0 AS m
    UNION ALL
    SELECT m + 1 FROM minutes WHERE m < 1439
)
INSERT INTO dw.dim_time (time_key, [hour], [minute], time_label, day_period)
SELECT
    (m / 60) * 100 + (m % 60),
    m / 60,
    m % 60,
    RIGHT('0' + CAST(m / 60 AS VARCHAR(2)), 2) + ':' + RIGHT('0' + CAST(m % 60 AS VARCHAR(2)), 2),
    CASE
        WHEN m / 60 BETWEEN 5  AND 11 THEN 'Morning'
        WHEN m / 60 BETWEEN 12 AND 16 THEN 'Afternoon'
        WHEN m / 60 BETWEEN 17 AND 20 THEN 'Evening'
        ELSE 'Night'
    END
FROM minutes
OPTION (MAXRECURSION 2000);
GO

SELECT COUNT(*) AS minutes_count, MIN(time_key) AS first_key, MAX(time_key) AS last_key
FROM dw.dim_time;

USE taxi_dwh;
SELECT 'dim_date' AS tbl, COUNT(*) AS n FROM dw.dim_date
UNION ALL SELECT 'dim_time', COUNT(*) FROM dw.dim_time
UNION ALL SELECT 'dim_zone', COUNT(*) FROM dw.dim_zone
UNION ALL SELECT 'dim_payment_type', COUNT(*) FROM dw.dim_payment_type
UNION ALL SELECT 'dim_vendor', COUNT(*) FROM dw.dim_vendor
UNION ALL SELECT 'dim_rate_code', COUNT(*) FROM dw.dim_rate_code;

--------------------------------------------------------------------------

USE taxi_dwh;
GO

CREATE TABLE dw.fact_trips (
    trip_id               BIGINT IDENTITY(1,1) PRIMARY KEY,
    source_month          CHAR(7)      NOT NULL,

    
    pickup_date_key       INT NOT NULL REFERENCES dw.dim_date(date_key),
    pickup_time_key       INT NOT NULL REFERENCES dw.dim_time(time_key),
    dropoff_date_key      INT NOT NULL REFERENCES dw.dim_date(date_key),
    dropoff_time_key      INT NOT NULL REFERENCES dw.dim_time(time_key),
    pickup_zone_key       INT NOT NULL REFERENCES dw.dim_zone(zone_key),
    dropoff_zone_key      INT NOT NULL REFERENCES dw.dim_zone(zone_key),
    payment_type_key      INT NOT NULL REFERENCES dw.dim_payment_type(payment_type_key),
    rate_code_key         INT NOT NULL REFERENCES dw.dim_rate_code(rate_code_key),
    vendor_key            INT NOT NULL REFERENCES dw.dim_vendor(vendor_key),

    
    store_and_fwd_flag    CHAR(1)      NULL,
    passenger_count       INT          NULL,

    
    trip_distance         FLOAT        NULL,
    trip_duration_min     FLOAT        NULL,
    fare_amount           FLOAT        NULL,
    extra                 FLOAT        NULL,
    mta_tax               FLOAT        NULL,
    tip_amount            FLOAT        NULL,
    tolls_amount          FLOAT        NULL,
    improvement_surcharge FLOAT        NULL,
    congestion_surcharge  FLOAT        NULL,
    airport_fee           FLOAT        NULL,
    cbd_congestion_fee    FLOAT        NULL,
    total_amount          FLOAT        NULL,

    
    is_negative_amount    BIT NOT NULL,
    is_zero_distance      BIT NOT NULL,
    is_zero_passengers    BIT NOT NULL
);
GO

CREATE INDEX ix_fact_trips_month ON dw.fact_trips (source_month);
GO

---------------------------------------
SELECT TOP 0 *, CAST(NULL AS VARCHAR(50)) AS reject_reason
INTO dw.rejected_trips
FROM stg.yellow_trips;


USE taxi_dwh;
GO

DECLARE @m     CHAR(7) = '2025-01';
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

-- 5) المطابقة: staging = fact + rejected
SELECT
  (SELECT COUNT(*) FROM stg.yellow_trips   WHERE source_month = '2025-01') AS staging_rows,
  (SELECT COUNT(*) FROM dw.fact_trips      WHERE source_month = '2025-01') AS fact_rows,
  (SELECT COUNT(*) FROM dw.rejected_trips  WHERE source_month = '2025-01') AS rejected_rows;

  SELECT
  SUM(CAST(is_negative_amount AS INT)) AS negative_amount,
  SUM(CAST(is_zero_distance AS INT))   AS zero_distance,
  SUM(CAST(is_zero_passengers AS INT)) AS zero_passengers
FROM dw.fact_trips;