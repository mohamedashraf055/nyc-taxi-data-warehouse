# Data Quality Log

Source: NYC TLC Yellow Taxi trip records, Dec 2024 to Jun 2025 (7 monthly Parquet files).

## Rules

| Check | Decision |
|---|---|
| Dropoff before pickup | Rejected (moved to dw.rejected_trips) |
| Pickup outside the file's month | Rejected |
| Null pickup/dropoff datetime | Rejected |
| Dropoff date out of dim_date range | Rejected |
| Negative fare or total amount | Loaded, flagged (is_negative_amount) |
| Zero trip distance | Loaded, flagged (is_zero_distance) |
| Zero passengers | Loaded, flagged (is_zero_passengers) |
| Null passenger count | Loaded as NULL (unknown is not zero) |
| Unknown codes (rate, payment, vendor) | Mapped to key -1 (Unknown) |

Each row gets exactly one reject reason (first matching rule wins), so nothing is counted twice.

## Reconciliation (staging = fact + rejected)

| Month | Staging | Fact | Rejected | Result |
|---|---|---|---|---|
| 2024-12 | 3,668,371 | 3,668,238 | 133 | OK |
| 2025-01 | 3,475,226 | 3,475,080 | 146 | OK |
| 2025-02 | 3,577,543 | 3,577,419 | 124 | OK |
| 2025-03 | 4,145,257 | 4,145,143 | 114 | OK |
| 2025-04 | 3,970,553 | 3,970,383 | 170 | OK |
| 2025-05 | 4,591,845 | 4,591,720 | 125 | OK |
| 2025-06 | 4,322,960 | 4,322,709 | 251 | OK |

The reconcile task in the Airflow DAG fails the run if the equation does not hold.

## Observations

- January 2025: 540,149 trips have payment_type = 0 (Flex Fare), with missing RatecodeID and passenger_count. The TLC dictionary does not explain the missing values, so the cause is unknown.
- Average distance per zone shows extreme values in low-volume zones (e.g. 100+ miles), which suggests bad meter data.
- cbd_congestion_fee exists only from Jan 2025 (fee started Jan 5, 2025); Dec 2024 is NULL.
- Cash tips are not recorded by TLC, so cash tip = 0 is a data limitation.
