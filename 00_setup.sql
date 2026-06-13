-- =============================================================================
-- 00_setup.sql
-- Creates the database staging table.
--
-- Run order:
--   1. Create the database (run once in terminal):
--        createdb phenology_dw
--
--   2. Import the CSV (run once in terminal, from the directory containing the CSV):
--        psql -d phenology_dw -c "\copy staging_phenology_weather
--            FROM 'phenology_weather_unified.csv'
--            WITH (FORMAT csv, HEADER true, NULL '');"
--
--   3. Then run the pipeline in order:
--        psql -d phenology_dw -f 00_setup.sql
--        psql -d phenology_dw -f 01_reconciled.sql
--        psql -d phenology_dw -f 02_schema.sql
--        psql -d phenology_dw -f 03_load.sql
-- =============================================================================

DROP TABLE IF EXISTS staging_phenology_weather;

CREATE TABLE staging_phenology_weather (
    record_id           BIGINT,
    obs_date            DATE,
    year                SMALLINT,
    month               SMALLINT,
    day                 SMALLINT,
    band_lat            NUMERIC(6,3),
    band_lon            NUMERIC(6,3),
    species             VARCHAR(100),
    species_type        VARCHAR(50),
    event               VARCHAR(100),
    day_of_year         SMALLINT,
    temp_mean_window    NUMERIC(5,2),
    temp_max_window     NUMERIC(5,2),
    temp_min_window     NUMERIC(5,2),
    temp_std_window     NUMERIC(5,2),
    precip_sum_window   NUMERIC(7,2),
    dry_days_window     SMALLINT,
    gdd_window          NUMERIC(7,2),
    temp_mean_spring    NUMERIC(5,2),
    temp_mean_winter    NUMERIC(5,2),
    precip_sum_spring   NUMERIC(7,2),
    et0_sum_spring      NUMERIC(7,2),
    temp_max_year       NUMERIC(5,2),
    temp_min_year       NUMERIC(5,2),
    precip_sum_year     NUMERIC(7,2),
    frost_days_year     SMALLINT,
    last_frost_doy      SMALLINT,
    spring_onset_doy    SMALLINT,
    season              VARCHAR(10)
);
