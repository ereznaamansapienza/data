"""
Integrate Woodland Trust phenology observations with Open-Meteo ERA5
historical weather, producing one unified DataFrame ready for loading
into a star schema.

Weather is fetched at the CENTROID of each LatitudeBand × LongitudeBand cell.
With 12 unique lat-bands and 13 lon-bands, this is at most 156 API calls for
the entire dataset, and gives each location dimension member a single,
consistent weather series — cleaner for OLAP than per-recorder GPS points.

Open-Meteo Historical Weather API: https://open-meteo.com/en/docs/historical-weather-api
No API key required.
"""

import os
import time
import json
import requests
import pandas as pd
import numpy as np

# --------------------------------------------------------------------------
# CONFIG
# --------------------------------------------------------------------------
PHENOLOGY_CSV = "phenology.csv"
OUTPUT_CSV    = "phenology_weather_unified.csv"
CACHE_DIR     = "weather_cache"

# Daily ERA5 variables to pull.  Extend as needed.
DAILY_VARS = [
    "temperature_2m_mean",
    "temperature_2m_max",
    "temperature_2m_min",
    "precipitation_sum",
]

WINDOW_DAYS   = 60      # look-back window before each event for "recent" weather
GDD_BASE      = 5.0     # base temp (°C) for growing degree day accumulation
REQUEST_PAUSE = 4.0     # seconds between API calls

ARCHIVE_URL = "https://archive-api.open-meteo.com/v1/archive"

os.makedirs(CACHE_DIR, exist_ok=True)


# --------------------------------------------------------------------------
# BAND CENTROID PARSING
# --------------------------------------------------------------------------

def lat_band_centroid(band: str) -> float:
    """'57-58' -> 57.5  (always two positive integers separated by '-')"""
    if "<" in band:
        return 49.0  # Special case for the single '<50' lat band
    lo, hi = band.split("-")
    return (float(lo) + float(hi)) / 2


def lon_band_centroid(band: str) -> float:
    """'-3 to -2' -> -2.5  (uses ' to ' because '-' is ambiguous with negatives)"""
    if "<" in band:
        return -10.0  # Special case for the single '<-5' lon band
    lo, hi = band.split(" to ")
    return (float(lo.strip()) + float(hi.strip())) / 2


# --------------------------------------------------------------------------
# WEATHER FETCHING + CACHING
# --------------------------------------------------------------------------
def fetch_one_chunk(lat, lon, start_date, end_date):
    """Fetch one date range from the API with retry logic."""
    params = {
        "latitude":   lat,
        "longitude":  lon,
        "start_date": start_date,
        "end_date":   end_date,
        "daily":      ",".join(DAILY_VARS),
        "timezone":   "Europe/London",
    }
    for attempt in range(6):
        try:
            r = requests.get(ARCHIVE_URL, params=params, timeout=90)
            if r.status_code == 200:
                return r.json()
            elif r.status_code == 429:
                print(f"    rate-limited, waiting 65s...")
                time.sleep(65)
            else:
                time.sleep(2 ** attempt)
        except requests.exceptions.ReadTimeout:
            print(f"    timeout on attempt {attempt + 1}, retrying...")
            time.sleep(10 * (attempt + 1))
    raise RuntimeError(f"Open-Meteo failed for ({lat},{lon}) {start_date}-{end_date}")


def fetch_location_series(lat: float, lon: float,
                           start_date: str, end_date: str) -> pd.DataFrame:
    """Fetch (or load from cache) a daily weather DataFrame for one location.
    Fetches one year at a time to keep responses small and avoid timeouts."""
    key = f"{lat}_{lon}_{start_date}_{end_date}"
    cache_path = os.path.join(CACHE_DIR, key.replace(" ", "_") + ".parquet")

    if os.path.exists(cache_path):
        return pd.read_parquet(cache_path)

    year_start = int(start_date[:4])
    year_end   = int(end_date[:4])
    chunks = []
    for year in range(year_start, year_end + 1):
        data = fetch_one_chunk(lat, lon, f"{year}-01-01", f"{year}-12-31")
        chunks.append(pd.DataFrame(data["daily"]))
        time.sleep(REQUEST_PAUSE)

    df = pd.concat(chunks, ignore_index=True)
    df["time"] = pd.to_datetime(df["time"])
    df = df.set_index("time")
    df.to_parquet(cache_path)
    return df



# --------------------------------------------------------------------------
# WEATHER FEATURE EXTRACTION PER OBSERVATION
# --------------------------------------------------------------------------

def weather_features(series: pd.DataFrame, event_date: pd.Timestamp) -> dict:
    """
    Compute phenology-relevant weather features from the daily series.

    The scientifically meaningful signals for phenology are the accumulated
    warmth *before* the event, not the weather on the day itself.
    """
    year = event_date.year
    window_start = event_date - pd.Timedelta(days=WINDOW_DAYS)

    window = series.loc[window_start:event_date]
    spring = series.loc[f"{year}-02-01": f"{year}-04-30"]
    winter = series.loc[f"{year-1}-12-01": f"{year}-02-28"]

    gdd = (window["temperature_2m_mean"] - GDD_BASE).clip(lower=0).sum()

    return {
        # Recent window (WINDOW_DAYS before event)
        "temp_mean_window":    window["temperature_2m_mean"].mean(),
        "temp_max_window":     window["temperature_2m_max"].max(),
        "temp_min_window":     window["temperature_2m_min"].min(),
        "precip_sum_window":   window["precipitation_sum"].sum(),
        "gdd_window":          round(gdd, 2),
        # Seasonal aggregates (useful for OLAP correlation analyses)
        "temp_mean_spring":    spring["temperature_2m_mean"].mean(),   # Feb–Apr
        "temp_mean_winter":    winter["temperature_2m_mean"].mean(),   # Dec–Feb
    }


# --------------------------------------------------------------------------
# MAIN ETL
# --------------------------------------------------------------------------

def main():
    print("Loading phenology data...")
    ph = pd.read_csv(PHENOLOGY_CSV, parse_dates=["ObservationDate"])

    # Drop rows we can't use
    ph = ph.dropna(subset=["ObservationDate", "LatitudeBand", "LongitudeBand"])

    # Parse band centroids — one centroid pair per unique band combination
    ph["band_lat"] = ph["LatitudeBand"].map(lat_band_centroid)
    ph["band_lon"] = ph["LongitudeBand"].map(lon_band_centroid)

    unique_locations = (
        ph[["LatitudeBand", "LongitudeBand", "band_lat", "band_lon"]]
        .drop_duplicates()
        .reset_index(drop=True)
    )
    print(f"  {len(ph):,} observations | "
          f"{len(unique_locations)} unique band cells | "
          f"{ph['Species'].nunique()} species | "
          f"{ph['SpeciesType'].nunique()} species types")

    start_date = f"{ph['Year'].min()}-01-01"
    end_date   = f"{ph['Year'].max()}-12-31"
    print(f"  Date span: {start_date} to {end_date}\n")

    # Fetch one full-span series per unique location (≤156 API calls total)
    series_by_band = {}
    for i, loc in unique_locations.iterrows():
        label = f"{loc['LatitudeBand']} / {loc['LongitudeBand']}"
        print(f"  [{i+1}/{len(unique_locations)}] fetching ERA5 for {label} "
              f"({loc['band_lat']}, {loc['band_lon']})")
        key = (loc["LatitudeBand"], loc["LongitudeBand"])
        series_by_band[key] = fetch_location_series(
            loc["band_lat"], loc["band_lon"], start_date, end_date
        )

    # Compute weather features for every observation
    print("\nComputing weather features per observation...")
    feats = []
    for row in ph.itertuples(index=False):
        key = (row.LatitudeBand, row.LongitudeBand)
        s   = series_by_band[key]
        feats.append(weather_features(s, row.ObservationDate))

    unified = pd.concat([ph.reset_index(drop=True),
                         pd.DataFrame(feats)], axis=1)

    # Convenience: day-of-year is your core "event timing" measure
    unified["day_of_year"] = unified["ObservationDate"].dt.dayofyear

    # Columns relevant to star schema dimensions / facts
    dim_cols  = ["Year", "Month", "Day", "LatitudeBand", "LongitudeBand",
                 "band_lat", "band_lon", "Species", "SpeciesType", "Event"]
    meas_cols = ["day_of_year", "temp_mean_window", "temp_max_window",
                 "temp_min_window", "precip_sum_window", "gdd_window",
                 "temp_mean_spring", "temp_mean_winter"]
    id_cols   = ["RecordID", "RecorderID", "ObservationDate",
                 "Latitude", "Longitude"]

    unified = unified[id_cols + dim_cols + meas_cols]
    unified.to_csv(OUTPUT_CSV, index=False)
    print(f"\nWrote {len(unified):,} rows -> {OUTPUT_CSV}")
    print("\nSample row:")
    print(unified.iloc[0].to_string())


if __name__ == "__main__":
    main()