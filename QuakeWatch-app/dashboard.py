"""Flask blueprint with the QuakeWatch dashboard routes."""

import os
from datetime import datetime, timedelta

import requests
from flask import Blueprint, render_template, jsonify, request, send_file, current_app

from utils import (
    API_TIMEOUT_SECONDS,
    COUNTRIES,
    EARTHQUAKE_API_URL,
    generate_graph,
    get_last_earthquake,
    get_top_earthquakes,
)

dashboard_blueprint = Blueprint('dashboard', __name__)

START_TIME = datetime.utcnow()


def _format_uptime():
    """Return the process uptime as a human-readable string."""
    total_seconds = int((datetime.utcnow() - START_TIME).total_seconds())
    hours, remainder = divmod(total_seconds, 3600)
    minutes, seconds = divmod(remainder, 60)
    return f"{hours}h {minutes}m {seconds}s"


class EarthquakeDashboard:
    """Groups the dashboard routes registered on dashboard_blueprint."""

    @staticmethod
    @dashboard_blueprint.route('/')
    def main_page():
        """Render the main landing page."""
        return render_template('main_page.html')

    @staticmethod
    @dashboard_blueprint.route('/ping')
    def ping():
        """Simple liveness check."""
        return 'pong', 200

    @staticmethod
    @dashboard_blueprint.route('/health')
    def health():
        """Return application health status."""
        return jsonify(status='ok', message='Application is healthy'), 200

    @staticmethod
    @dashboard_blueprint.route('/status')
    def status():
        """Return basic service status information."""
        status_info = {
            'service': os.environ.get('APP_NAME', 'QuakeWatch'),
            'environment': os.environ.get('APP_ENV', 'development'),
            'status': 'running',
            'uptime': _format_uptime()
        }
        return jsonify(status_info), 200

    @staticmethod
    @dashboard_blueprint.route('/info')
    def info():
        """Return general application metadata."""
        app_info = {
            'name': os.environ.get('APP_NAME', 'QuakeWatch'),
            'version': '1.0.0',
            'author': 'Michael Goncharov',
            'description': 'Earthquake dashboard powered by the USGS Earthquake API'
        }
        return jsonify(app_info), 200

    @staticmethod
    @dashboard_blueprint.route('/telaviv-earthquakes')
    def telaviv_earthquakes():
        """Return raw Tel Aviv earthquake data (last 30 days)."""
        start_time = (datetime.utcnow() - timedelta(days=30)).strftime('%Y-%m-%d')
        params = {
            'format': 'geojson',
            'latitude': 32.0853,
            'longitude': 34.7818,
            'maxradiuskm': 100,
            'starttime': start_time
        }
        response = requests.get(EARTHQUAKE_API_URL, params=params, timeout=API_TIMEOUT_SECONDS)
        if response.status_code == 200:
            data = response.json()
            processed_events = []
            for feature in data.get('features', []):
                properties = feature.get('properties', {})
                geometry = feature.get('geometry', {})
                coordinates = geometry.get('coordinates', [])
                event_data = {
                    'magnitude': properties.get('mag'),
                    'place': properties.get('place'),
                    'time': properties.get('time'),
                    'coordinates': {
                        'longitude': coordinates[0] if len(coordinates) > 0 else None,
                        'latitude': coordinates[1] if len(coordinates) > 1 else None,
                        'depth': coordinates[2] if len(coordinates) > 2 else None,
                    },
                    'type': properties.get('type')
                }
                processed_events.append(event_data)
            result = {
                'count': len(processed_events),
                'events': processed_events
            }
            return jsonify(result), 200

        current_app.logger.error("Error fetching data from USGS API")
        return jsonify(error="Error fetching data from USGS API"), response.status_code

    @staticmethod
    @dashboard_blueprint.route('/graph-earthquakes.png')
    def graph_earthquakes_image():
        """Return a PNG graph of earthquakes for the selected location and days."""
        days = int(request.args.get('days', 30))
        loc_name = request.args.get('location', "Tel Aviv, Israel")
        location = COUNTRIES.get(loc_name, COUNTRIES["Tel Aviv, Israel"])
        img = generate_graph(days, location["lat"], location["lon"], location["radius"])
        return send_file(img, mimetype='image/png')

    @staticmethod
    @dashboard_blueprint.route('/graph-earthquakes-5years.png')
    def graph_earthquakes_5years_image():
        """Return a PNG graph of earthquakes over the last 5 years."""
        days = 5 * 365  # Approximate days in 5 years
        loc_name = request.args.get('location', "Tel Aviv, Israel")
        location = COUNTRIES.get(loc_name, COUNTRIES["Tel Aviv, Israel"])
        img = generate_graph(
            days,
            location["lat"],
            location["lon"],
            location["radius"],
            title_suffix="(5 Years)",
        )
        return send_file(img, mimetype='image/png')

    @staticmethod
    @dashboard_blueprint.route('/graph-earthquakes')
    def graph_earthquakes_page():
        """Render the graph dashboard page."""
        days = int(request.args.get('days', 30))
        loc_name = request.args.get('location', "Tel Aviv, Israel")
        top_events = get_top_earthquakes(limit=5)
        last_event = get_last_earthquake()

        return render_template('graph_dashboard.html',
                               days=days,
                               current_location=loc_name,
                               countries=list(COUNTRIES.keys()),
                               top_events=top_events,
                               last_event=last_event)

# The static methods in EarthquakeDashboard register the routes automatically.
