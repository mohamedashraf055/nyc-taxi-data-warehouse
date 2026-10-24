USE taxi_dwh;
GO

-- صفحة الوقت: مشاوير حسب الشهر واليوم والساعة
CREATE VIEW dw.v_trips_by_hour AS
SELECT f.source_month, d.full_date, d.day_name, d.is_weekend,
       t.[hour] AS pickup_hour,
       COUNT(*) AS trips,
       SUM(f.total_amount) AS revenue,
       SUM(f.tip_amount)   AS tips
FROM dw.fact_trips f
JOIN dw.dim_date d ON d.date_key = f.pickup_date_key
JOIN dw.dim_time t ON t.time_key = f.pickup_time_key
WHERE f.is_negative_amount = 0
GROUP BY f.source_month, d.full_date, d.day_name, d.is_weekend, t.[hour];
GO

-- صفحة المناطق
CREATE VIEW dw.v_trips_by_zone AS
SELECT f.source_month, z.borough, z.zone_name,
       COUNT(*) AS trips,
       SUM(f.total_amount) AS revenue,
       AVG(f.trip_distance) AS avg_distance
FROM dw.fact_trips f
JOIN dw.dim_zone z ON z.zone_key = f.pickup_zone_key
WHERE f.is_negative_amount = 0
GROUP BY f.source_month, z.borough, z.zone_name;
GO

-- صفحة جودة الداتا
CREATE VIEW dw.v_data_quality AS
SELECT source_month, 'rejected' AS category, reject_reason AS detail, COUNT(*) AS n
FROM dw.rejected_trips
GROUP BY source_month, reject_reason
UNION ALL
SELECT source_month, 'flag', 'negative_amount', SUM(CAST(is_negative_amount AS INT)) FROM dw.fact_trips GROUP BY source_month
UNION ALL
SELECT source_month, 'flag', 'zero_distance',   SUM(CAST(is_zero_distance AS INT))   FROM dw.fact_trips GROUP BY source_month
UNION ALL
SELECT source_month, 'flag', 'zero_passengers', SUM(CAST(is_zero_passengers AS INT)) FROM dw.fact_trips GROUP BY source_month;
GO