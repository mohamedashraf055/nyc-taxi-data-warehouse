# Warehouse Design

## Grain
One row in fact_trips = one taxi trip.

## Star schema
- fact_trips: keys to dimensions, measures (distance, duration, fare, tip, tolls, fees, total) and quality flags.
- dim_date, dim_time, dim_zone, dim_payment_type, dim_rate_code, dim_vendor.

## Design decisions
- Role-playing dimensions: date, time and zone are each used twice (pickup and dropoff).
- Unknown member: every dimension has key -1, so unexpected codes never break a load.
- source_month column: each monthly load deletes its month first, so re-running a month does not duplicate rows (idempotent).
- Staging layer (stg) keeps raw data as-is; dw holds the modeled data.
- Flags instead of deletes for suspicious-but-possible rows; only impossible rows are rejected.
- trip_duration_min is derived (dropoff minus pickup).

## Layers
Parquet file -> stg.yellow_trips -> dw.fact_trips (+ dw.rejected_trips)
