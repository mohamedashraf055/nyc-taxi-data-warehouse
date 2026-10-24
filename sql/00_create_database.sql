-- Creates the database, schemas and the raw staging table.
CREATE DATABASE taxi_dwh;
GO
USE taxi_dwh;
GO
CREATE SCHEMA stg;
GO
CREATE SCHEMA dw;
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