-- =============================================================================
-- 01_reconciled.sql
-- Reconciled layer: clean and enrich the staged data.
--
-- Derived columns added:
--   lat_band, lon_band  — band strings derived from centroids
--   decade              — derived from year
--   event_category      — phenological classification of event
--   nation              — UK nation derived from coordinates
--   region              — ONS/standard region derived from coordinates
-- =============================================================================

DROP TABLE IF EXISTS reconciled_phenology_weather;

CREATE TABLE reconciled_phenology_weather AS
    SELECT *,
           CAST(NULL AS VARCHAR(10))  AS lat_band,
           CAST(NULL AS VARCHAR(15))  AS lon_band,
           CAST(NULL AS SMALLINT)     AS decade,
           CAST(NULL AS VARCHAR(20))  AS event_category,
           CAST(NULL AS VARCHAR(30))  AS nation,
           CAST(NULL AS VARCHAR(50))  AS region
    FROM staging_phenology_weather;


-- -----------------------------------------------------------------------------
-- Derive band strings from centroids
-- -----------------------------------------------------------------------------
UPDATE reconciled_phenology_weather
SET lat_band = CONCAT(FLOOR(band_lat - 0.5)::INT, '-', CEIL(band_lat + 0.5)::INT);

UPDATE reconciled_phenology_weather
SET lon_band = CONCAT(ROUND(band_lon - 0.5, 0)::INT, ' to ', ROUND(band_lon + 0.5, 0)::INT);


-- -----------------------------------------------------------------------------
-- Derive decade
-- -----------------------------------------------------------------------------
UPDATE reconciled_phenology_weather
SET decade = (year / 10) * 10;


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
        WHEN event IN ('First recorded')
            THEN 'Emergence'
        ELSE 'Other'
    END;


-- -----------------------------------------------------------------------------
-- Classify nation
-- UK nations overlap in latitude so longitude is needed to distinguish them.
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
        WHEN band_lon < -10
            THEN 'Other'
        ELSE 'England'
    END;


-- -----------------------------------------------------------------------------
-- Classify region (ONS regions for England, nations elsewhere)
-- Each 1°x1° band cell is assigned to its best-fit standard region.
-- -----------------------------------------------------------------------------
UPDATE reconciled_phenology_weather
SET region =
    CASE
        -- Scotland regions
        WHEN band_lat >= 57                                     THEN 'Scottish Highlands'
        WHEN band_lat BETWEEN 55 AND 57 AND band_lon < -4      THEN 'Scottish West'
        WHEN band_lat BETWEEN 55 AND 57 AND band_lon >= -4     THEN 'Scottish East'

        -- Northern Ireland
        WHEN band_lat BETWEEN 54 AND 55 AND band_lon < -5      THEN 'Northern Ireland'

        -- Wales
        WHEN band_lat BETWEEN 51 AND 53 AND band_lon < -3      THEN 'Wales'

        -- England (ONS regions, approximate by lat/lon band)
        WHEN band_lat BETWEEN 54 AND 55 AND band_lon > -5 AND band_lon <= -3  THEN 'North West'
        WHEN band_lat BETWEEN 54 AND 55 AND band_lon > -3                     THEN 'North East'
        WHEN band_lat BETWEEN 53 AND 54 AND band_lon <= -2                    THEN 'North West'
        WHEN band_lat BETWEEN 53 AND 54 AND band_lon > -2                     THEN 'Yorkshire and Humber'
        WHEN band_lat BETWEEN 52 AND 53 AND band_lon <= -2                    THEN 'West Midlands'
        WHEN band_lat BETWEEN 52 AND 53 AND band_lon > -2                     THEN 'East Midlands'
        WHEN band_lat BETWEEN 51 AND 52 AND band_lon <= -2                    THEN 'South West'
        WHEN band_lat BETWEEN 51 AND 52 AND band_lon BETWEEN -2 AND 0         THEN 'South East'
        WHEN band_lat BETWEEN 51 AND 52 AND band_lon > 0                      THEN 'East of England'
        WHEN band_lat BETWEEN 50 AND 51                                       THEN 'South West'
        WHEN band_lat < 50                                                    THEN 'South West'
        ELSE 'Other'
    END;


-- -----------------------------------------------------------------------------
-- Sanity checks
-- -----------------------------------------------------------------------------
SELECT nation, COUNT(*) AS n
FROM reconciled_phenology_weather
GROUP BY nation ORDER BY n DESC;

SELECT region, COUNT(*) AS n
FROM reconciled_phenology_weather
GROUP BY region ORDER BY n DESC;

SELECT event_category, COUNT(*) AS n
FROM reconciled_phenology_weather
GROUP BY event_category ORDER BY n DESC;

SELECT COUNT(*) AS rows_missing_weather
FROM reconciled_phenology_weather
WHERE temp_mean_window IS NULL;
