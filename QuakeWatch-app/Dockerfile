FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=5000

WORKDIR /app

# Install runtime dependencies
COPY requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Run as an unprivileged user (UID matches the Helm chart securityContext)
RUN useradd --uid 10001 --create-home --shell /usr/sbin/nologin appuser

# Copy application source code
COPY --chown=appuser:appuser . .

USER 10001

# Build the Matplotlib font cache at image build time instead of on every pod start
RUN python -c "import matplotlib.pyplot"

EXPOSE 5000

# Production WSGI server instead of the Flask development server
CMD ["sh", "-c", "exec gunicorn --bind 0.0.0.0:${PORT} --workers 2 --timeout 60 --access-logfile - 'app:create_app()'"]
