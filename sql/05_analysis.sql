USE taxi_dwh;

-- 1) Peak hours (all days)
SELECT t.[hour], COUNT(*) AS trips
FROM dw.fact_trips f
JOIN dw.dim_time t ON t.time_key = f.pickup_time_key
GROUP BY t.[hour]
ORDER BY t.[hour];

-- 2) Peak hours: weekdays vs weekends
SELECT d.is_weekend, t.[hour], COUNT(*) AS trips
FROM dw.fact_trips f
JOIN dw.dim_time t ON t.time_key = f.pickup_time_key
JOIN dw.dim_date d ON d.date_key = f.pickup_date_key
GROUP BY d.is_weekend, t.[hour]
ORDER BY d.is_weekend, t.[hour];

-- 3) Top 10 pickup zones by revenue (negative amounts excluded)
SELECT TOP 10 z.borough, z.zone_name,
       COUNT(*) AS trips,
       ROUND(SUM(f.total_amount), 0) AS revenue
FROM dw.fact_trips f
JOIN dw.dim_zone z ON z.zone_key = f.pickup_zone_key
WHERE f.is_negative_amount = 0
GROUP BY z.borough, z.zone_name
ORDER BY revenue DESC;

-- 4) Tips by payment type
-- Note: cash tips are not recorded in TLC data, so cash shows ~0.
SELECT p.payment_type_name,
       COUNT(*) AS trips,
       ROUND(AVG(f.tip_amount), 2) AS avg_tip,
       ROUND(AVG(CASE WHEN f.fare_amount > 0
                      THEN f.tip_amount / f.fare_amount END) * 100, 1) AS avg_tip_pct
FROM dw.fact_trips f
JOIN dw.dim_payment_type p ON p.payment_type_key = f.payment_type_key
WHERE f.is_negative_amount = 0
GROUP BY p.payment_type_name
ORDER BY trips DESC;

-- 5) Before vs after the congestion fee (started 2025-01-05)
-- Descriptive only. The "before" period is Dec 2024 (holiday season).
SELECT
    CASE WHEN d.full_date < '2025-01-05' THEN 'before_5_jan'
         ELSE 'after_5_jan' END AS period,
    COUNT(*) AS trips,
    COUNT(DISTINCT d.full_date) AS days,
    COUNT(*) / COUNT(DISTINCT d.full_date) AS trips_per_day,
    ROUND(AVG(f.total_amount), 2) AS avg_total,
    ROUND(AVG(f.cbd_congestion_fee), 2) AS avg_cbd_fee
FROM dw.fact_trips f
JOIN dw.dim_date d ON d.date_key = f.pickup_date_key
WHERE f.is_negative_amount = 0
GROUP BY CASE WHEN d.full_date < '2025-01-05' THEN 'before_5_jan'
              ELSE 'after_5_jan' END;