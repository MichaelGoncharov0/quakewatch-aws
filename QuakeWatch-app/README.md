![QuakeWatch logo](static/experts-logo.svg)

# QuakeWatch

**QuakeWatch** is a Flask web application that shows real-time and historical earthquake data from the USGS Earthquake API, with graphs of earthquake counts over time. Templates, utility functions, and route definitions live in separate modules, and the app is containerized with Docker.

## Features

- **Real-Time & Historical Data:** Fetches earthquake data from the USGS API.
- **Graphs:** Shows earthquake counts over various time periods (last N days, 5-year view) using Matplotlib.
- **Top Earthquake Events:** Shows the top 5 earthquakes worldwide (last 30 days) by magnitude.
- **Recent Earthquake Details:** Highlights the most recent earthquake event.
- **REST Endpoints:** Health checks, status, connectivity tests, and raw data.
- **Clean UI:** Bootstrap 5 with a navigation bar and logo.
- **Dockerized:** Runs under `gunicorn` as a non-root user.

## Endpoints

| Path | Description |
|---|---|
| `/` | Main page |
| `/graph-earthquakes` | Graph dashboard (`?days=30&location=Japan`) |
| `/graph-earthquakes.png` | Earthquake count graph image |
| `/graph-earthquakes-5years.png` | 5-year graph image |
| `/telaviv-earthquakes` | Raw JSON for Tel Aviv (last 30 days) |
| `/health` | Health check (used by Kubernetes probes) |
| `/ping` | Returns `pong` |
| `/status` | Service status and uptime |
| `/info` | Application metadata |

## Project Structure

```text
QuakeWatch-app/
├── app.py                   # Application factory and entry point
├── dashboard.py             # Blueprint & route definitions
├── utils.py                 # USGS API helpers, graph generation, Jinja2 filter
├── requirements.txt         # Pinned Python dependencies
├── Dockerfile               # Container image (gunicorn, non-root)
├── .dockerignore
├── static/
│   └── experts-logo.svg     # Logo used in the UI
└── templates/               # Jinja2 HTML templates
    ├── base.html            # Shared layout and navigation
    ├── main_page.html       # Home page
    └── graph_dashboard.html # Graphs and earthquake details
```

## Configuration

The app reads these optional environment variables (in Kubernetes they come from the Helm chart's ConfigMap):

| Variable | Default | Description |
|---|---|---|
| `PORT` | `5000` | Port to listen on |
| `LOG_LEVEL` | `INFO` | Log level for application and access logs (written to stdout) |
| `API_TIMEOUT_SECONDS` | `20` | Timeout for USGS API requests |
| `APP_NAME` | `QuakeWatch` | Shown in `/status` and `/info` |
| `APP_ENV` | `development` | Shown in `/status` |
| `FLASK_DEBUG` | `0` | Set to `1` to enable debug mode (local `python app.py` only) |

## Running Locally

```bash
git clone https://github.com/MichaelGoncharov0/QuakeWatch-repo.git
cd QuakeWatch-repo/QuakeWatch-app

python3 -m venv .venv
source .venv/bin/activate      # On Windows: .venv\Scripts\activate
pip install -r requirements.txt

python app.py
```

Then open http://127.0.0.1:5000.

## Running with Docker

```bash
docker build -t quakewatch:1.0.0 .
docker run --rm -p 5000:5000 quakewatch:1.0.0
```

## Custom Jinja2 Filter

The custom filter `timestamp_to_str` converts epoch timestamps (in milliseconds) to readable UTC strings. It is registered in `create_app()` and used in the templates to format earthquake event times.

## Notes

- **Matplotlib backend:** The app uses the non-GUI `Agg` backend so graphs render on headless servers and containers.
- **macOS SSL warning:** With the system Python on macOS, you may see a urllib3 warning about LibreSSL. It is informational and doesn't affect the app.
