"""Utility helpers for QuakeWatch earthquake data queries and graph generation."""

import io
import os
from collections import defaultdict
from datetime import datetime, timedelta

import matplotlib.pyplot as plt
import requests

COUNTRIES = {
    "Tel Aviv, Israel": {"lat": 32.0853, "lon": 34.7818, "radius": 100},
    "United States (California)": {"lat": 36.7783, "lon": -119.4179, "radius": 300},
    "Japan": {"lat": 36.2048, "lon": 138.2529, "radius": 300},
    "Indonesia": {"lat": -0.7893, "lon": 113.9213, "radius": 300},
    "Chile": {"lat": -35.6751, "lon": -71.5430, "radius": 300},
}

EARTHQUAKE_API_URL = "https://earthquake.usgs.gov/fdsnws/event/1/query"
API_TIMEOUT_SECONDS = int(os.environ.get("API_TIMEOUT_SECONDS", "20"))


def _build_query_params(start_time, latitude, longitude, radius):
    """Create the USGS query parameters for earthquake requests."""
    return {
        "format": "geojson",
        "latitude": latitude,
        "longitude": longitude,
        "maxradiuskm": radius,
        "starttime": start_time,
    }


def _save_figure_to_buffer():
    """Persist the active matplotlib figure to an in-memory PNG buffer."""
    image_buffer = io.BytesIO()
    plt.savefig(image_buffer, format="png")
    plt.close()
    image_buffer.seek(0)
    return image_buffer


def _build_daily_counts(data):
    """Group earthquake events by date and return sorted day labels and counts."""
    counts_by_day = defaultdict(int)
    for feature in data.get("features", []):
        timestamp = feature.get("properties", {}).get("time")
        if timestamp is None:
            continue
        event_date = datetime.utcfromtimestamp(timestamp / 1000).date()
        counts_by_day[event_date] += 1

    days_list = sorted(counts_by_day.keys())
    counts = [counts_by_day[day] for day in days_list]
    return days_list, counts


def generate_graph(days, lat, lon, radius, title_suffix=""):
    """Generate a PNG graph showing earthquake counts for a region."""
    start_time = (datetime.utcnow() - timedelta(days=days)
                  ).strftime("%Y-%m-%d")
    params = _build_query_params(start_time, lat, lon, radius)
    response = requests.get(EARTHQUAKE_API_URL, params=params, timeout=API_TIMEOUT_SECONDS)

    plt.figure(figsize=(10, 5))

    if response.status_code != 200:
        plt.text(
            0.5,
            0.5,
            "Error fetching data",
            horizontalalignment="center",
            verticalalignment="center",
            fontsize=14,
        )
        plt.axis("off")
        return _save_figure_to_buffer()

    data = response.json()
    days_list, counts = _build_daily_counts(data)

    if not days_list:
        plt.text(
            0.5,
            0.5,
            "No earthquake data available",
            horizontalalignment="center",
            verticalalignment="center",
            fontsize=14,
        )
        plt.axis("off")
        return _save_figure_to_buffer()

    plt.bar(days_list, counts)
    plt.xlabel("Date")
    plt.ylabel("Number of Earthquakes")
    plt.title(f"Earthquakes in Last {days} Days {title_suffix}")
    plt.xticks(rotation=45)
    plt.tight_layout()

    return _save_figure_to_buffer()


def get_top_earthquakes(limit=5):
    """Return the strongest earthquakes from the last 30 days."""
    start_time = (datetime.utcnow() - timedelta(days=30)).strftime("%Y-%m-%d")
    params = {
        "format": "geojson",
        "starttime": start_time,
        "minmagnitude": 1,
    }
    response = requests.get(EARTHQUAKE_API_URL, params=params, timeout=API_TIMEOUT_SECONDS)
    top_events = []

    if response.status_code == 200:
        data = response.json()
        events = data.get("features", [])
        top_events = sorted(
            events,
            key=lambda feature: feature.get("properties", {}).get("mag", 0),
            reverse=True,
        )[:limit]

    return top_events


def get_last_earthquake():
    """Return the most recent earthquake in the last 30 days."""
    start_time = (datetime.utcnow() - timedelta(days=30)).strftime("%Y-%m-%d")
    params = {
        "format": "geojson",
        "starttime": start_time,
        "minmagnitude": 1,
    }
    response = requests.get(EARTHQUAKE_API_URL, params=params, timeout=API_TIMEOUT_SECONDS)
    last_event = None

    if response.status_code == 200:
        data = response.json()
        events = data.get("features", [])
        events = sorted(
            events,
            key=lambda feature: feature.get("properties", {}).get("time", 0),
            reverse=True,
        )
        if events:
            last_event = events[0]

    return last_event


def timestamp_to_str(ts):
    """Convert a Unix timestamp in milliseconds to a readable UTC datetime string."""
    return datetime.utcfromtimestamp(ts / 1000).strftime("%Y-%m-%d %H:%M:%S")
