-- Dimensions, fact table and rejected rows table.
-- Note: dw.dim_zone is filled from taxi_zone_lookup.csv by scripts/load_dim_zone.py
USE taxi_dwh;
GO

-- ===== Dimensions =====
CREATE TABLE dw.dim_payment_type (
    payment_type_key  INT          NOT NULL PRIMARY KEY,
    payment_type_name VARCHAR(50)  NOT NULL
);
GO
INSERT INTO dw.dim_payment_type (payment_type_key, payment_type_name) VALUES
(-1, 'Unknown'), (0, 'Flex Fare trip'), (1, 'Credit card'), (2, 'Cash'),
(3, 'No charge'), (4, 'Dispute'), (5, 'Unknown'), (6, 'Voided trip');
GO

CREATE TABLE dw.dim_vendor (
    vendor_key   INT          NOT NULL PRIMARY KEY,
    vendor_name  VARCHAR(80)  NOT NULL
);
GO
INSERT INTO dw.dim_vendor (vendor_key, vendor_name) VALUES
(-1, 'Unknown'), (1, 'Creative Mobile Technologies, LLC'), (2, 'Curb Mobility, LLC'),
(6, 'Myle Technologies Inc'), (7, 'Helix');
GO

CREATE TABLE dw.dim_rate_code (
    rate_code_key   INT          NOT NULL PRIMARY KEY,
    rate_code_name  VARCHAR(50)  NOT NULL
);
GO
INSERT INTO dw.dim_rate_code (rate_code_key, rate_code_name) VALUES
(-1, 'Unknown'), (1, 'Standard rate'), (2, 'JFK'), (3, 'Newark'),
(4, 'Nassau or Westchester'), (5, 'Negotiated fare'), (6, 'Group ride'),
(99, 'Null/unknown');
GO

CREATE TABLE dw.dim_zone (
    zone_key       INT           NOT NULL PRIMARY KEY,
    borough        VARCHAR(50)   NOT NULL,
    zone_name      VARCHAR(100)  NOT NULL,
    service_zone   VARCHAR(50)   NOT NULL
);
GO
INSERT INTO dw.dim_zone (zone_key, borough, zone_name, service_zone)
VALUES (-1, 'Unknown', 'Unknown', 'Unknown');
GO

CREATE TABLE dw.dim_date (
    date_key     INT          NOT NULL PRIMARY KEY,
    full_date    DATE         NOT NULL,
    [year]       INT          NOT NULL,
    [month]      INT          NOT NULL,
    month_name   VARCHAR(20)  NOT NULL,
    [day]        INT          NOT NULL,
    day_of_week  INT          NOT NULL,   -- 1 = Monday ... 7 = Sunday
    day_name     VARCHAR(20)  NOT NULL,
    is_weekend   BIT          NOT NULL
);
GO
WITH dates AS (
    SELECT CAST('2024-01-01' AS DATE) AS d
    UNION ALL
    SELECT DATEADD(DAY, 1, d) FROM dates WHERE d < '2025-12-31'
)
INSERT INTO dw.dim_date
SELECT
    YEAR(d) * 10000 + MONTH(d) * 100 + DAY(d), d, YEAR(d), MONTH(d),
    DATENAME(MONTH, d), DAY(d),
    ((DATEPART(WEEKDAY, d) + @@DATEFIRST - 2) % 7) + 1,
    DATENAME(WEEKDAY, d),
    CASE WHEN ((DATEPART(WEEKDAY, d) + @@DATEFIRST - 2) % 7) + 1 IN (6, 7) THEN 1 ELSE 0 END
FROM dates
OPTION (MAXRECURSION 1000);
GO

CREATE TABLE dw.dim_time (
    time_key     INT          NOT NULL PRIMARY KEY,   -- e.g. 1430 = 14:30
    [hour]       INT          NOT NULL,
    [minute]     INT          NOT NULL,
    time_label   CHAR(5)      NOT NULL,
    day_period   VARCHAR(20)  NOT NULL
);
GO
WITH minutes AS (
    SELECT 0 AS m
    UNION ALL
    SELECT m + 1 FROM minutes WHERE m < 1439
)
INSERT INTO dw.dim_time (time_key, [hour], [minute], time_label, day_period)
SELECT
    (m / 60) * 100 + (m % 60), m / 60, m % 60,
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

-- ===== Fact =====
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

-- Rejected rows: same shape as staging + the reject reason
SELECT TOP 0 *, CAST(NULL AS VARCHAR(50)) AS reject_reason
INTO dw.rejected_trips
FROM stg.yellow_trips;
GO