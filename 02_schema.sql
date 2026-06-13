-- =============================================================================
-- 02_schema.sql
-- Snowflake schema DDL — dimension tables and fact table.
--
-- Hierarchy summary:
--   dim_date:     date → month → season → year → decade
--   dim_location: band_cell → (lat_band, lon_band) → nation
--   dim_species:  species → species_type
--   dim_event:    event → event_category
-- =============================================================================


-- -----------------------------------------------------------------------------
-- DIM_DATE
-- Hierarchy: date → month → season → year → decade
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS dim_date CASCADE;

CREATE TABLE dim_date (
    date_id     SERIAL      PRIMARY KEY,
    full_date   DATE        NOT NULL UNIQUE,
    day         SMALLINT    NOT NULL,
    month       SMALLINT    NOT NULL,
    month_name  VARCHAR(10) NOT NULL,
    season      VARCHAR(10) NOT NULL,
    year        SMALLINT    NOT NULL,
    decade      SMALLINT    NOT NULL
);


-- -----------------------------------------------------------------------------
-- DIM_LOCATION
-- Hierarchy: band_cell → lat_band/lon_band → nation
-- Split into three tables to make the hierarchy explicit and queryable.
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS dim_location CASCADE;
DROP TABLE IF EXISTS dim_lat_band CASCADE;
DROP TABLE IF EXISTS dim_lon_band CASCADE;

CREATE TABLE dim_lat_band (
    lat_band_id SERIAL      PRIMARY KEY,
    lat_band    VARCHAR(10) NOT NULL UNIQUE,   -- e.g. '57-58'
    lat_centroid NUMERIC(6,3) NOT NULL
);

CREATE TABLE dim_lon_band (
    lon_band_id SERIAL      PRIMARY KEY,
    lon_band    VARCHAR(15) NOT NULL UNIQUE,   -- e.g. '-3 to -2'
    lon_centroid NUMERIC(6,3) NOT NULL
);

CREATE TABLE dim_location (
    location_id SERIAL  PRIMARY KEY,
    lat_band_id INT     NOT NULL REFERENCES dim_lat_band(lat_band_id),
    lon_band_id INT     NOT NULL REFERENCES dim_lon_band(lon_band_id),
    band_lat    NUMERIC(6,3) NOT NULL,
    band_lon    NUMERIC(6,3) NOT NULL,
    nation      VARCHAR(20),
    UNIQUE (lat_band_id, lon_band_id)
);


-- -----------------------------------------------------------------------------
-- DIM_SPECIES
-- Hierarchy: species → species_type
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS dim_species CASCADE;
DROP TABLE IF EXISTS dim_species_type CASCADE;

CREATE TABLE dim_species_type (
    species_type_id SERIAL      PRIMARY KEY,
    species_type    VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE dim_species (
    species_id      SERIAL       PRIMARY KEY,
    species         VARCHAR(100) NOT NULL UNIQUE,
    species_type_id INT          NOT NULL REFERENCES dim_species_type(species_type_id)
);


-- -----------------------------------------------------------------------------
-- DIM_EVENT
-- Hierarchy: event → event_category
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS dim_event CASCADE;
DROP TABLE IF EXISTS dim_event_category CASCADE;

CREATE TABLE dim_event_category (
    event_category_id   SERIAL      PRIMARY KEY,
    event_category      VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE dim_event (
    event_id            SERIAL       PRIMARY KEY,
    event               VARCHAR(100) NOT NULL UNIQUE,
    event_category_id   INT          NOT NULL REFERENCES dim_event_category(event_category_id)
);


-- -----------------------------------------------------------------------------
-- FACT_PHENOLOGY_OBSERVATION
-- Grain: one recorded phenological event per species per location per date.
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS fact_phenology_observation CASCADE;

CREATE TABLE fact_phenology_observation (
    observation_id      SERIAL  PRIMARY KEY,
    record_id           BIGINT     NOT NULL,

    -- Dimension foreign keys
    date_id             INT     NOT NULL REFERENCES dim_date(date_id),
    location_id         INT     NOT NULL REFERENCES dim_location(location_id),
    species_id          INT     NOT NULL REFERENCES dim_species(species_id),
    event_id            INT     NOT NULL REFERENCES dim_event(event_id),

    -- Event timing (primary response variable)
    day_of_year         SMALLINT NOT NULL,

    -- Pre-event window measures (60-day look-back before event)
    temp_mean_window    NUMERIC(5,2),
    temp_max_window     NUMERIC(5,2),
    temp_min_window     NUMERIC(5,2),
    temp_std_window     NUMERIC(5,2),
    precip_sum_window   NUMERIC(7,2),
    dry_days_window     SMALLINT,
    gdd_window          NUMERIC(7,2),

    -- Seasonal climate summaries
    temp_mean_spring    NUMERIC(5,2),
    temp_mean_winter    NUMERIC(5,2),
    precip_sum_spring   NUMERIC(7,2),
    et0_sum_spring      NUMERIC(7,2),

    -- Annual climate summaries
    temp_max_year       NUMERIC(5,2),
    temp_min_year       NUMERIC(5,2),
    precip_sum_year     NUMERIC(7,2),
    frost_days_year     SMALLINT,

    -- Phenological timing indicators
    last_frost_doy      SMALLINT,
    spring_onset_doy    SMALLINT
);
