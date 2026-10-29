"""QuakeWatch Flask application entry point."""

import logging
import os
import sys

import matplotlib
from flask import Flask, request

from dashboard import dashboard_blueprint
from utils import timestamp_to_str  # Import our custom filter

# Force non-GUI backend (safe here: no figures have been created yet)
matplotlib.use('Agg')


def _configure_logging(flask_app):
    """Send application and access logs to stdout so `docker logs`/`kubectl logs` see them."""
    log_level = os.environ.get('LOG_LEVEL', 'INFO').upper()

    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s'))

    flask_app.logger.handlers = [handler]
    flask_app.logger.setLevel(log_level)

    usage_logger = logging.getLogger('usage')
    usage_logger.handlers = [handler]
    usage_logger.setLevel(log_level)
    usage_logger.propagate = False
    return usage_logger


def create_app():
    """Create and configure the QuakeWatch Flask application."""
    flask_app = Flask(__name__)
    usage_logger = _configure_logging(flask_app)

    @flask_app.before_request
    def log_request_info():
        usage_logger.info("%s - %s %s", request.remote_addr, request.method, request.url)

    # Register our blueprint
    flask_app.register_blueprint(dashboard_blueprint)

    # Register custom Jinja2 filter so templates can use |timestamp_to_str
    flask_app.jinja_env.filters['timestamp_to_str'] = timestamp_to_str

    return flask_app


if __name__ == '__main__':
    # Local development server only; the container runs gunicorn instead.
    app = create_app()
    app.run(
        host='0.0.0.0',
        port=int(os.environ.get('PORT', '5000')),
        debug=os.environ.get('FLASK_DEBUG', '0') == '1',
    )
