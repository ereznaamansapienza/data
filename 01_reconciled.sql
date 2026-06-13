-- =============================================================================
-- 01_reconciled.sql
-- Reconciled layer: import the unified CSV and apply cleaning / enrichment.
--
-- Run order:
--   psql -d phenology_dw -f 01_reconciled.sql
--
-- Prerequisite: the CSV has been imported into a staging table.
-- To create the staging table and import, run first:
--
--   CREATE TABLE staging_phenology_weather (
--       record_id           INT,
--       obs_date            DATE,
--       year                SMALLINT,
--       month               SMALLINT,
--       day                 SMALLINT,
--       band_lat            NUMERIC(6,3),
--       band_lon            NUMERIC(6,3),
--       species             VARCHAR(100),
--       species_type        VARCHAR(50),
--       event               VARCHAR(100),
--       day_of_year         SMALLINT,
--       temp_mean_window    NUMERIC(5,2),
--       temp_max_window     NUMERIC(5,2),
--       temp_min_window     NUMERIC(5,2),
--       temp_std_window     NUMERIC(5,2),
--       precip_sum_window   NUMERIC(7,2),
--       dry_days_window     SMALLINT,
--       gdd_window          NUMERIC(7,2),
--       temp_mean_spring    NUMERIC(5,2),
--       temp_mean_winter    NUMERIC(5,2),
--       precip_sum_spring   NUMERIC(7,2),
--       et0_sum_spring      NUMERIC(7,2),
--       temp_max_year       NUMERIC(5,2),
--       temp_min_year       NUMERIC(5,2),
--       precip_sum_year     NUMERIC(7,2),
--       frost_days_year     SMALLINT,
--       last_frost_doy      SMALLINT,
--       spring_onset_doy    SMALLINT,
--       season              VARCHAR(10)
--   );
--
--   \copy staging_phenology_weather FROM 'phenology_weather_unified.csv'
--       WITH (FORMAT csv, HEADER true, NULL '');
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Create reconciled table with derived columns added
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS reconciled_phenology_weather;

CREATE TABLE reconciled_phenology_weather AS
    SELECT *,
           CAST(NULL AS VARCHAR(20))  AS event_category,
           CAST(NULL AS VARCHAR(20))  AS nation,
           CAST(NULL AS VARCHAR(10))  AS lat_band,
           CAST(NULL AS VARCHAR(15))  AS lon_band,
           CAST(NULL AS SMALLINT)     AS decade
    FROM staging_phenology_weather;


-- -----------------------------------------------------------------------------
-- Derive decade
-- -----------------------------------------------------------------------------
UPDATE reconciled_phenology_weather
SET decade = (year / 10) * 10;


-- -----------------------------------------------------------------------------
-- Derive lat_band and lon_band strings from centroids
-- These become dimension keys in the star schema.
-- -----------------------------------------------------------------------------
UPDATE reconciled_phenology_weather
SET lat_band = CONCAT(FLOOR(band_lat - 0.5)::INT, '-', CEIL(band_lat + 0.5)::INT);

UPDATE reconciled_phenology_weather
SET lon_band = CONCAT(ROUND(band_lon - 0.5, 0)::INT, ' to ', ROUND(band_lon + 0.5, 0)::INT);


-- -----------------------------------------------------------------------------
-- Classify events into phenological categories
-- -----------------------------------------------------------------------------
UPDATE reconciled_phenology_weather
SET event_category =
    CASE
        WHEN event IN ('First flowering', 'Full flowering', 'Flowering over')
            THEN 'Flowering'
        WHEN event IN ('Budburst', 'First leaf', 'Full leaf')
            THEN 'Spring development'
        WHEN event IN ('First ripe fruit')
            THEN 'Fruiting'
        WHEN event IN ('First autumn tinting', 'Full autumn tinting', 'First leaves falling')
            THEN 'Senescence'
        WHEN event IN ('Bare tree', 'Recorded all winter')
            THEN 'Dormancy'
        WHEN event IN ('First cut', 'Last cut')
            THEN 'Management'
        ELSE 'Other'
    END;


-- -----------------------------------------------------------------------------
-- Classify nation from band_lat and band_lon
--
-- UK nations overlap in latitude, so both axes are needed:
--   Scotland:         band_lat >= 55
--   Northern Ireland: band_lat BETWEEN 54 AND 55 AND band_lon < -5
--   Wales:            band_lat BETWEEN 51 AND 53 AND band_lon < -3
--   England:          everything else
--
-- These are approximate (band centroids cover 1° cells) but sufficient
-- for OLAP rollup purposes.
-- -----------------------------------------------------------------------------
UPDATE reconciled_phenology_weather
SET nation =
    CASE
        WHEN band_lat >= 55
            THEN 'Scotland'
        WHEN band_lat BETWEEN 54 AND 55 AND band_lon < -5
            THEN 'Northern Ireland'
        WHEN band_lat BETWEEN 51 AND 53 AND band_lon < -3
            THEN 'Wales'
        ELSE 'England'
    END;

