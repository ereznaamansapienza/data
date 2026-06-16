-- =============================================================================
-- 03_load.sql
-- Populate all dimension tables then the fact table from reconciled layer.
-- Run after 01_reconciled.sql and 02_schema.sql.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- dim_date
-- -----------------------------------------------------------------------------
INSERT INTO dim_date (full_date, day, month, month_name, season, year, decade)
SELECT DISTINCT
    obs_date,
    day,
    month,
    TO_CHAR(obs_date, 'Month') AS month_name,
    season,
    year,
    decade
FROM reconciled_phenology_weather
ON CONFLICT (full_date) DO NOTHING;


-- -----------------------------------------------------------------------------
-- dim_nation
-- -----------------------------------------------------------------------------
INSERT INTO dim_nation (nation)
SELECT DISTINCT nation
FROM reconciled_phenology_weather
WHERE nation IS NOT NULL
ON CONFLICT (nation) DO NOTHING;


-- -----------------------------------------------------------------------------
-- dim_region
-- -----------------------------------------------------------------------------
INSERT INTO dim_region (region, nation_id)
SELECT DISTINCT
    r.region,
    n.nation_id
FROM reconciled_phenology_weather r
JOIN dim_nation n ON n.nation = r.nation
WHERE r.region IS NOT NULL
ON CONFLICT (region) DO NOTHING;


-- -----------------------------------------------------------------------------
-- dim_location
-- -----------------------------------------------------------------------------
INSERT INTO dim_location (lat_band, lon_band, band_lat, band_lon, region_id)
SELECT DISTINCT
    r.lat_band,
    r.lon_band,
    r.band_lat,
    r.band_lon,
    rg.region_id
FROM reconciled_phenology_weather r
JOIN dim_region rg ON rg.region = r.region
ON CONFLICT (lat_band, lon_band) DO NOTHING;


-- -----------------------------------------------------------------------------
-- dim_species_type
-- -----------------------------------------------------------------------------
INSERT INTO dim_species_type (species_type)
SELECT DISTINCT species_type
FROM reconciled_phenology_weather
WHERE species_type IS NOT NULL
ON CONFLICT (species_type) DO NOTHING;


-- -----------------------------------------------------------------------------
-- dim_species
-- -----------------------------------------------------------------------------
INSERT INTO dim_species (species, species_type_id)
SELECT DISTINCT
    r.species,
    st.species_type_id
FROM reconciled_phenology_weather r
JOIN dim_species_type st ON st.species_type = r.species_type
ON CONFLICT (species) DO NOTHING;


-- -----------------------------------------------------------------------------
-- dim_event_category
-- -----------------------------------------------------------------------------
INSERT INTO dim_event_category (event_category)
SELECT DISTINCT event_category
FROM reconciled_phenology_weather
WHERE event_category IS NOT NULL
ON CONFLICT (event_category) DO NOTHING;


-- -----------------------------------------------------------------------------
-- dim_event
-- -----------------------------------------------------------------------------
INSERT INTO dim_event (event, event_category_id)
SELECT DISTINCT
    r.event,
    ec.event_category_id
FROM reconciled_phenology_weather r
JOIN dim_event_category ec ON ec.event_category = r.event_category
ON CONFLICT (event) DO NOTHING;


-- -----------------------------------------------------------------------------
-- fact_phenology_observation
-- -----------------------------------------------------------------------------
INSERT INTO fact_phenology_observation (
    record_id,
    date_id, location_id, species_id, event_id,
    day_of_year,
    temp_mean_window, temp_max_window, temp_min_window, temp_std_window,
    precip_sum_window, dry_days_window, gdd_window,
    temp_mean_spring, temp_mean_winter, precip_sum_spring, et0_sum_spring,
    temp_max_year, temp_min_year, precip_sum_year, frost_days_year,
    last_frost_doy, spring_onset_doy
)
SELECT
    r.record_id,
    d.date_id,
    l.location_id,
    s.species_id,
    e.event_id,
    r.day_of_year,
    r.temp_mean_window, r.temp_max_window, r.temp_min_window, r.temp_std_window,
    r.precip_sum_window, r.dry_days_window, r.gdd_window,
    r.temp_mean_spring, r.temp_mean_winter, r.precip_sum_spring, r.et0_sum_spring,
    r.temp_max_year, r.temp_min_year, r.precip_sum_year, r.frost_days_year,
    r.last_frost_doy, r.spring_onset_doy
FROM reconciled_phenology_weather r
JOIN dim_date     d  ON d.full_date  = r.obs_date
JOIN dim_location l  ON l.lat_band   = r.lat_band
                    AND l.lon_band   = r.lon_band
JOIN dim_species  s  ON s.species    = r.species
JOIN dim_event    e  ON e.event      = r.event;


-- -----------------------------------------------------------------------------
-- Verify row counts
-- -----------------------------------------------------------------------------
SELECT 'dim_date'                     AS tbl, COUNT(*) AS n FROM dim_date
UNION ALL SELECT 'dim_nation',                 COUNT(*) FROM dim_nation
UNION ALL SELECT 'dim_region',                 COUNT(*) FROM dim_region
UNION ALL SELECT 'dim_location',               COUNT(*) FROM dim_location
UNION ALL SELECT 'dim_species_type',           COUNT(*) FROM dim_species_type
UNION ALL SELECT 'dim_species',                COUNT(*) FROM dim_species
UNION ALL SELECT 'dim_event_category',         COUNT(*) FROM dim_event_category
UNION ALL SELECT 'dim_event',                  COUNT(*) FROM dim_event
UNION ALL SELECT 'fact_phenology_observation', COUNT(*) FROM fact_phenology_observation
ORDER BY tbl;
